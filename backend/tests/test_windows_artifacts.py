"""Exercise the real build and ZIP scripts with synthetic local data.

Run with the build requirements installed and PowerShell on PATH. The backend
executable is native to the test host. The ZIP uses runner fixtures so the
checks can also run without a Windows Flutter toolchain.
"""

from __future__ import annotations

import base64
import os
import shutil
import socket
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread
from zipfile import ZipFile

import httpx
import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from windows_artifacts import BACKEND_ENTRY, ArtifactError, check_backend  # noqa: E402

SENTINEL = b"anchor-synthetic-sentinel-98b8c732"


def isolated_env() -> dict[str, str]:
    return {name: value for name, value in os.environ.items() if not name.startswith("ANCHOR_")}


def test_source_packages_only_explicit_backend_resources():
    script = (ROOT / "scripts" / "build_backend.ps1").read_text(encoding="utf-8")
    assert [
        line.strip().split('"')[1] for line in script.splitlines() if "--add-data" in line
    ] == ["migrations/[0-9][0-9][0-9]_*.sql:migrations", "../content/activities.json:content"]
    assert "credentials.env" not in script
    assert "windows_artifacts.py" in script


@pytest.fixture(scope="module")
def packaged_backend(tmp_path_factory):
    pytest.importorskip("PyInstaller")
    pwsh = shutil.which("pwsh") or shutil.which("powershell")
    if not pwsh:
        pytest.skip("PowerShell is required for artifact integration tests")
    checkout = tmp_path_factory.mktemp("anchor-package")
    backend = checkout / "backend"
    backend.mkdir()
    for source, target in (
        (ROOT / "scripts", checkout / "scripts"),
        (ROOT / "content", checkout / "content"),
        (ROOT / "backend" / "app", backend / "app"),
        (ROOT / "backend" / "migrations", backend / "migrations"),
    ):
        shutil.copytree(source, target, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))

    # Call the actual scripts with the already-provisioned build Python.
    common = checkout / "scripts" / "_common.ps1"
    with common.open("a", encoding="utf-8") as stream:
        python = sys.executable.replace("'", "''")
        stream.write(f"\n$script:VenvPython = '{python}'\n")
    for name in ("config/credentials.env", "migrations/local.env"):
        local_file = backend / name
        local_file.parent.mkdir(parents=True, exist_ok=True)
        local_file.write_bytes(b"ANCHOR_LLM_API_KEY=" + SENTINEL + b"\n")

    def run_script(script: str, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [pwsh, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
             str(checkout / "scripts" / script), *args],
            cwd=checkout, env=isolated_env(), capture_output=True, timeout=180,
        )

    build = run_script("build_backend.ps1", "-SkipDeps")
    assert build.returncode == 0, build.stdout.decode(errors="replace")
    artifact = backend / "dist" / ("anchor_backend.exe" if os.name == "nt" else "anchor_backend")
    return checkout, artifact, run_script


def test_executable_excludes_credentials_and_sentinel(packaged_backend):
    _, artifact, _ = packaged_backend
    check_backend(artifact, sentinel=SENTINEL)


def test_windows_zip_excludes_runtime_data(packaged_backend):
    checkout, artifact, run_script = packaged_backend
    runner = checkout / "mobile" / "dist" / "windows"
    for name in (
        "anchor_app.exe", "flutter_windows.dll", "data/icudtl.dat",
        "data/flutter_assets/kernel_blob.bin",
    ):
        path = runner / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"synthetic runner output")
    for name in (
        "config/credentials.env", "backend/config/credentials.env", "backend/data/anchor.db",
        "data/anchor.db-wal", "data/backend.log", ".env.local", "tokens.json",
        "data/flutter_assets/assets/private.json", "operator-settings.ini", "operator.dll",
    ):
        path = runner / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(SENTINEL)
    # Exercise the Windows ZIP path on the host's native PyInstaller output.
    windows_name = artifact.with_name("anchor_backend.exe")
    if artifact != windows_name:
        shutil.copyfile(artifact, windows_name)
    result = run_script("package_windows.ps1", "-SkipBuild", "-Version", "secure-test")
    assert result.returncode == 0, result.stdout.decode(errors="replace")
    output = runner.parent / "AnchorDemo-secure-test.zip"
    with ZipFile(output) as archive:
        assert set(archive.namelist()) == {
            "anchor_app.exe", "flutter_windows.dll", "data/icudtl.dat",
            "data/flutter_assets/kernel_blob.bin", BACKEND_ENTRY, "README-DEMO.txt",
        }
        assert all(SENTINEL not in archive.read(name) for name in archive.namelist())
        check_backend(Path(archive.extract(BACKEND_ENTRY, checkout / "zip-inspection")),
                      sentinel=SENTINEL)
    assert not (checkout / "release").exists()


@pytest.mark.parametrize("kind", ["b", "x"])
def test_dirty_executable_is_rejected_even_when_reusing_a_build(tmp_path, kind):
    pytest.importorskip("PyInstaller")
    from PyInstaller.archive.writers import CArchiveWriter
    from windows_artifacts import package_windows

    payload = tmp_path / "synthetic.env"
    payload.write_bytes(SENTINEL)
    executable = tmp_path / "backend.exe"
    CArchiveWriter(
        str(executable),
        [(name, str(payload), True, kind) for name in (
            "content/activities.json", "migrations/001_init.sql", "config/credentials.env",
        )],
        "python.dll",
    )
    output = tmp_path / "package.zip"
    with pytest.raises(ArtifactError, match="unapproved archive entry"):
        package_windows(tmp_path, executable, tmp_path / "README", output)
    assert not output.exists()


def test_sentinel_check_detects_compressed_payload_with_approved_name(tmp_path):
    pytest.importorskip("PyInstaller")
    from PyInstaller.archive.writers import CArchiveWriter

    payload = tmp_path / "synthetic"
    payload.write_bytes(SENTINEL * 100)
    executable = tmp_path / "backend.exe"
    CArchiveWriter(
        str(executable),
        [(name, str(payload), True, "x") for name in (
            "content/activities.json", "migrations/001_init.sql",
        )],
        "python.dll",
    )
    assert SENTINEL not in executable.read_bytes()
    with pytest.raises(ArtifactError, match="contains the test sentinel"):
        check_backend(executable, sentinel=SENTINEL)


@pytest.fixture
def local_providers():
    calls = []

    class ProviderHandler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_POST(self):
            self.rfile.read(int(self.headers["Content-Length"]))
            if self.headers.get("Authorization") != "Bearer " + SENTINEL.decode():
                self.send_error(401)
                return
            if self.path == "/v1/chat/completions":
                payload = b'{"choices":[{"message":{"content":"Synthetic reply"}}]}'
            elif self.path == "/v1/audio/transcriptions":
                payload = b'{"text":"Synthetic transcript"}'
            else:
                self.send_error(404)
                return
            calls.append(self.path)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(payload)

    with ThreadingHTTPServer(("127.0.0.1", 0), ProviderHandler) as server:
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield f"http://127.0.0.1:{server.server_port}/v1", calls
        finally:
            server.shutdown()
            thread.join()


def test_frozen_start_and_linked_caregiver_runtime_configuration(
    packaged_backend, tmp_path, local_providers
):
    _, artifact, _ = packaged_backend
    provider_url, calls = local_providers
    installed = tmp_path / artifact.name
    shutil.copy2(artifact, installed)
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    env = isolated_env()
    env.update(ANCHOR_HOST="127.0.0.1", ANCHOR_PORT=str(port), ANCHOR_DISCOVERY_PORT="0")
    with subprocess.Popen([str(installed)], env=env, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL) as process:
        try:
            with httpx.Client(base_url=f"http://127.0.0.1:{port}/api/v1",
                              timeout=2.0, trust_env=False) as client:
                deadline = time.monotonic() + 30
                while True:
                    assert process.poll() is None, "Frozen backend exited during startup"
                    try:
                        health = client.get("/health")
                        break
                    except httpx.TransportError:
                        if time.monotonic() > deadline:
                            pytest.fail("Frozen backend did not start")
                        time.sleep(0.1)
                assert health.json()["status"] == "ok"
                login = client.post("/dev/login", json={"user_id": 2})
                assert login.status_code == 200
                client.headers["Authorization"] = "Bearer " + login.json()["access_token"]
                initial = client.get("/providers").json()
                assert initial["llm"]["engine"] == "offline-rule"
                assert initial["asr"]["mode"] == "offline"
                assert not initial["llm"]["key_hint"] and not initial["asr"]["key_hint"]
                configured = client.put("/providers", json={
                    kind: {"api_key": SENTINEL.decode(), "base_url": provider_url}
                    for kind in ("llm", "asr")
                })
                assert configured.status_code == 200
                assert SENTINEL not in configured.content
                current = client.get("/providers").json()
                assert all(current[kind]["engine"] == "http" and current[kind]["configured"]
                           for kind in ("llm", "asr"))
                probe = client.post("/providers/test", json={
                    "audio_b64": base64.b64encode(b"synthetic audio fixture").decode(),
                })
                assert probe.status_code == 200 and SENTINEL not in probe.content
                assert probe.json()["llm"]["reply_sample"] == "Synthetic reply"
                assert probe.json()["asr"]["text_sample"] == "Synthetic transcript"
                assert calls == ["/v1/chat/completions", "/v1/audio/transcriptions"]
        finally:
            if process.poll() is None:
                if os.name == "nt":
                    subprocess.run(["taskkill", "/T", "/F", "/PID", str(process.pid)],
                                   capture_output=True, check=True)
                else:
                    process.terminate()
    assert (tmp_path / "data" / "anchor.db").is_file()
