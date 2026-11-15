"""Run the TA5 backend smoke over loopback HTTP with disposable synthetic data."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import platform
import secrets
import socket
import subprocess
import sys
import tempfile
import threading
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

import httpx
import uvicorn

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

# Monday in Asia/Shanghai. A fixed clock makes the report period reproducible.
FIXTURE_TIME = datetime(2026, 11, 16, 1, tzinfo=timezone.utc)
AUDIO = base64.b64encode(b"synthetic ASR fixture").decode("ascii")
PREFIX = "/api/v1"


class SmokeFailure(RuntimeError):
    """A failed check with a safe diagnostic for the evidence file."""


def require(condition, message):
    if not condition:
        raise SmokeFailure(message)


def request(http, method, path, status=200, *, data=None, token=None, error=None):
    response = http.request(
        method, PREFIX + path, json=data,
        headers={"Authorization": f"Bearer {token}"} if token else None,
    )
    require(response.status_code == status, f"{method} {path}: expected HTTP {status}, "
                                             f"got {response.status_code}")
    payload = response.json()
    if error:
        actual = payload.get("error", {}).get("code")
        require(actual == error, f"{method} {path}: expected error code {error}")
    return payload


@contextmanager
def running_backend(app):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
        server = uvicorn.Server(uvicorn.Config(app, log_level="critical", access_log=False))
        thread = threading.Thread(target=server.run, kwargs={"sockets": [listener]}, daemon=True)
        thread.start()
        try:
            with httpx.Client(
                base_url=f"http://127.0.0.1:{port}", timeout=3, trust_env=False
            ) as http:
                deadline = time.monotonic() + 10
                while not server.started:
                    require(thread.is_alive(), "Backend exited before startup.")
                    require(time.monotonic() < deadline, "Backend startup timed out.")
                    time.sleep(0.05)
                yield http
        finally:
            server.should_exit = True
            thread.join(timeout=5)
            require(not thread.is_alive(), "Backend did not shut down within five seconds.")


def change_consent(http, senior, changes):
    current = request(http, "GET", "/consents", token=senior)
    request(http, "PUT", "/consents", data={
        "base_version": current["version"],
        "changes": changes,
    }, token=senior)


def run_checks(http, adapters, checks):
    from app.providers.asr_fake import FailingASR
    from app.providers.unavailable import UnavailableLLM

    health = request(http, "GET", "/health")
    require(health["status"] == "ok" and health["version"], "Backend health payload is invalid.")
    checks["startup_health"] = {"status": "pass", "api_version": health["version"]}

    senior = request(http, "POST", "/dev/login", data={"user_id": 1})["access_token"]
    caregiver = request(http, "POST", "/dev/login", data={"user_id": 2})["access_token"]
    require(request(http, "GET", "/me", token=senior)["role"] == "senior", "Wrong senior role.")
    family_profile = request(http, "GET", "/me", token=caregiver)
    require(family_profile["role"] == "caregiver" and family_profile["senior_id"] == 1
            and family_profile["relationship_status"] == "accepted", "Wrong caregiver scope.")
    request(http, "GET", "/me", 401, error="unauthorized")
    request(http, "POST", "/sessions", 403, token=caregiver, data={}, error="forbidden")
    request(http, "PUT", "/consents", 403, token=caregiver, data={
        "base_version": 1, "changes": [{"capability": "cloud_processing", "allowed": True}],
    }, error="forbidden")
    checks["role_separation"] = {"status": "pass", "unauthenticated": 401, "caregiver_write": 403}

    def cloud(allowed):
        change_consent(http, senior, [{"capability": "cloud_processing", "allowed": allowed}])

    cloud(False)
    request(http, "POST", "/sessions", 403, token=senior, data={}, error="consent_required")
    cloud(True)
    session = request(http, "POST", "/sessions", token=senior, data={})
    session_path = "/sessions/" + session["session_id"]
    turn_path = session_path + "/turns"
    request(http, "GET", session_path, 403, token=caregiver, error="caregiver_scope_denied")

    asr = adapters["asr"]
    audio_turn = request(http, "POST", turn_path, token=senior, data={"audio_b64": AUDIO})
    require(
        audio_turn["transcript"] == asr.transcript and audio_turn["reply_text"]
        and [entry["role"] for entry in audio_turn["captions"]] == ["senior", "anchor"]
        and len(asr.calls) == 1,
        "Synthetic audio turn did not produce the expected transcript and captions.",
    )
    checks["conversation_turn"] = {"status": "pass", "asr": "stub", "reply": "offline rule"}

    adapters["asr"] = FailingASR()
    unavailable = request(
        http, "POST", turn_path, 503, token=senior, data={"audio_b64": AUDIO},
        error="provider_unavailable",
    )
    require("type_instead" in unavailable["error"]["recovery"], "Typing recovery is missing.")
    typed = request(http, "POST", turn_path, token=senior, data={"text": "Hello from the smoke test."})
    require(typed["reply_text"] and not typed["stopped"], "Typed recovery did not return a reply.")

    llm = adapters["llm"]
    adapters["llm"] = UnavailableLLM()
    request(http, "POST", turn_path, 503, token=senior, data={"text": "Synthetic retry"},
            error="provider_unavailable")
    adapters["llm"] = llm
    adapters["asr"] = asr
    recovered = request(http, "POST", turn_path, token=senior, data={"text": "Synthetic retry"})
    require(recovered["reply_text"], "A new request failed after restoring the local provider.")
    checks["provider_failure_recovery"] = {
        "status": "pass", "asr_failure": 503, "typed_retry": 200, "llm_unavailable": 503,
        "retry_after_provider_restored": 200,
    }

    cloud(False)
    request(http, "POST", turn_path, 403, token=senior, data={"audio_b64": AUDIO},
            error="consent_required")
    require(len(asr.calls) == 1, "A denied session turn invoked the ASR stub.")
    checks["session_cloud_consent"] = {"status": "pass", "denied_before_adapter": True}
    stopped = request(http, "POST", session_path + "/stop", token=senior)
    require(stopped["state"] == "stopped", "Stop did not close the session.")
    require(request(http, "GET", session_path, token=senior)["captions"] == [],
            "Stop did not clear the session captions.")
    request(http, "POST", turn_path, 409, token=senior, data={"text": "Late turn"},
            error="session_stopped")
    checks["stop_after_revocation"] = {"status": "pass", "stop": 200, "late_turn": 409}

    draft = request(http, "POST", "/digests/generate", token=senior)
    require(draft["status"] == "draft" and draft["items"], "Expected a supported synthetic draft.")
    require((draft["period_start"], draft["period_end"]) == ("2026-11-09", "2026-11-16"),
            "Report did not cover the last completed Shanghai week.")
    digest_path = f"/digests/{draft['id']}"
    request(http, "GET", digest_path, 403, token=caregiver, error="caregiver_scope_denied")
    request(http, "POST", digest_path + "/publish", 403, token=caregiver, error="forbidden")
    for _ in range(2):
        result = request(http, "POST", digest_path + "/publish", token=senior)
        require(result["status"] == "delivered", "Approved report was not delivered.")
    reports = request(http, "GET", "/digests", token=caregiver)["items"]
    require(len(reports) == 1 and reports[0]["id"] == draft["id"] and reports[0]["items"],
            "Caregiver did not receive one published report with highlights.")
    reminders = request(http, "GET", "/notifications", token=caregiver)["items"]
    reminder_count = sum(row["kind"] == "digest_ready" for row in reminders)
    require(reminder_count == 1, "Repeated publication did not yield exactly one reminder.")
    checks["digest_review_publish_read"] = {
        "status": "pass", "draft_caregiver_read": 403, "in_app_reminders": reminder_count,
        "period_start": draft["period_start"], "period_end_exclusive": draft["period_end"],
    }

    topics = {item["topic"] for item in reports[0]["items"]}
    change_consent(http, senior, [
        {"capability": "share_topic", "topic": topic, "allowed": False} for topic in sorted(topics)
    ])
    refreshed = request(http, "GET", "/digests", token=caregiver)
    direct = request(http, "GET", digest_path, token=caregiver)
    require(refreshed.get("note") == "insufficient_information"
            and all(not report["items"] for report in refreshed["items"])
            and not direct["items"], "Revoked highlights remained visible on a fresh API read.")
    relationship = request(http, "GET", "/relationships", token=senior)["items"][0]
    request(http, "DELETE", f"/relationships/{relationship['id']}", token=senior)
    require(not request(http, "GET", "/digests", token=caregiver)["items"],
            "Caregiver still sees a digest after unlinking.")
    request(http, "GET", digest_path, 403, token=caregiver, error="caregiver_scope_denied")
    checks["caregiver_refetch_after_revocation"] = {
        "status": "pass", "revoked_topics": len(topics), "direct_read_after_unlink": 403,
    }


def revision():
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True, stderr=subprocess.DEVNULL
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Write the sanitized JSON evidence to this path.")
    args = parser.parse_args()

    # Ignore operator settings and any production SQLite location. Import the
    # app factory only after redirecting the module-level app's default DB.
    for key in list(os.environ):
        if key.upper().startswith("ANCHOR_"):
            del os.environ[key]
    os.environ["ANCHOR_DB_PATH"] = ":memory:"
    from app.clock import FakeClock
    from app.config import Settings
    from app.demo_seed import seed_demo
    from app.main import create_app
    from app.providers.asr_fake import FakeASR
    from app.providers.llm_rule import RuleLLM

    checks = {}
    evidence = {
        "evidence_type": "automated_backend_smoke",
        "checkout_revision": revision(),
        "smoke_script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "executed_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "host": platform.system(),
        "python": platform.python_version(),
        "fixture_clock_utc": FIXTURE_TIME.isoformat(),
        "transport": "loopback HTTP only",
        "providers": "synthetic ASR, local rule LLM, injected unavailability; TTS not called",
        "checks": checks,
    }
    try:
        with tempfile.TemporaryDirectory(prefix="anchor-ta5-") as directory:
            settings = Settings(
                env="test", secret=secrets.token_urlsafe(32),
                db_path=str(Path(directory) / "synthetic.db"), timezone="Asia/Shanghai",
            )
            clock = FakeClock(FIXTURE_TIME)
            adapters = {"asr": FakeASR(), "llm": RuleLLM()}
            app = create_app(settings, clock=clock, providers=adapters)
            try:
                seed_demo(app.state.db, clock, settings, demo_window=True)
                with running_backend(app) as http:
                    run_checks(http, adapters, checks)
            finally:
                app.state.db.close()
        evidence["result"] = "pass"
    except SmokeFailure as error:
        evidence.update(result="fail", failure=str(error))
    except Exception as error:
        # Suppress raw replies, request headers, provider settings and file paths.
        evidence.update(result="fail", failure=f"Unexpected {type(error).__name__}")

    summary = json.dumps(evidence, indent=2) + "\n"
    if args.output:
        args.output.write_text(summary, encoding="utf-8")
    print(summary, end="")
    return 0 if evidence["result"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
