"""Acceptance-matrix harness for guide §8 (SPEC §10) and the WER evaluator tests.

The matrix is data, not prose: every row names the guide area and the existing
tests that provide machine evidence. User-study-only rows are marked ``MANUAL``;
the test asserts they are documented in ``docs/measurement.md`` as "not yet
measured" instead of pretending the target was achieved.

``failure_offline`` is the backend-testable slice of the required offline test:
no provider is reachable, the error is a structured recovery response, and Stop
and system calling (a local ``tel:`` action) keep working. Screen-level offline
behaviour is a Flutter check in a later milestone.
"""

from __future__ import annotations

import ast
import importlib.util
import json
from pathlib import Path
from typing import Any

import pytest

from tests.helpers import (
    FailingLLM,
    headers,
    insert_contact,
    seed_consents,
)

ANCHOR_DIR = Path(__file__).resolve().parents[2]
TESTS_DIR = ANCHOR_DIR / "backend" / "tests"
SCRIPTS_DIR = ANCHOR_DIR / "scripts"
GUIDE = ANCHOR_DIR.parent / "Anchor_Software_Design_and_MVP_Guide.md"
MEASUREMENT = ANCHOR_DIR / "docs" / "measurement.md"

AUTOMATED = "AUTOMATED"
MANUAL = "MANUAL"

# One row per guide §8 acceptance area (the 11 table rows + supplementary measures).
ACCEPTANCE_MATRIX: list[dict[str, Any]] = [
    {
        "area": "Proactive frequency",
        "measure": "At most one opted-in invitation/day; none outside the permitted window",
        "target": "<=1/day, window enforced",
        "status": AUTOMATED,
        "tests": [
            "test_s1_attempt_records_and_cap_blocks_second",
            "test_s1_outside_window",
            "test_s1_quiet_hours_block_attempt",
            "test_failure_quiet_hours_midnight",
        ],
        "notes": "Backend rules are deterministic; real-device notification delivery is manual.",
    },
    {
        "area": "Conversation naturalness",
        "measure": "User rating at least 4/5",
        "target": ">=4/5",
        "status": MANUAL,
        "tests": [
            "test_s2_turn_produces_reply_and_captions",
            "test_s2_diagnostic_reply_is_replaced",
        ],
        "notes": "User-study rating; automated tests only prove structured, safe replies.",
    },
    {
        "area": "Speech recognition",
        "measure": "WER at most 20% for an initial pilot; at most 10% ideal",
        "target": "<=20% pilot / <=10% ideal",
        "status": MANUAL,
        "tests": [
            "test_eval_wer_computes_classic_alignment",
            "test_eval_wer_reports_dialect_groups",
        ],
        "notes": "The evaluator exists and is tested; WER itself needs participant recordings.",
    },
    {
        "area": "First-use usability",
        "measure": "At least 70% unaided task completion initially; at least 90% ideal",
        "target": ">=70% initial / >=90% ideal",
        "status": MANUAL,
        "tests": [
            "test_s12_invite_accept_approve_flow",
            "test_manual_rows_are_documented_in_measurement_protocol",
        ],
        "notes": "Needs participants; setup flow is machine-checked, one-tap reachability is not measured.",
    },
    {
        "area": "Approved memory",
        "measure": "At least 90% correct recall after seven days",
        "target": ">=90%",
        "status": MANUAL,
        "tests": ["test_memory_recall_7d"],
        "notes": "The 7-day retrieval mechanism is tested; the 90% figure is a user-study result.",
    },
    {
        "area": "Interaction controls",
        "measure": "Stop/Not now on every application screen; successful cancellation in every scripted control case",
        "target": "100% of scripted cases",
        "status": AUTOMATED,
        "tests": [
            "test_s7_stop_purges_turns_and_is_idempotent",
            "test_s7_turn_after_stop_is_rejected",
            "test_failure_stop_late_output",
        ],
        "notes": "Backend cancellation is tested; per-screen visibility is a Flutter widget check (M5).",
    },
    {
        "area": "Sharing compliance",
        "measure": "100% compliance with current permissions in the authorization test suite",
        "target": "0 violations",
        "status": AUTOMATED,
        "tests": [
            "test_authz_caregiver_cannot_use_senior_endpoint",
            "test_authz_client_supplied_senior_id_is_ignored",
            "test_authz_revoked_relationship_blocks_caregiver_actions",
            "test_authz_cannot_revoke_another_households_relationship",
            "test_s10_caregiver_filtered_by_current_consent",
            "test_failure_cross_household",
        ],
        "notes": "authz_* suite plus digest/caregiver filtering; every new endpoint has a denial test.",
    },
    {
        "area": "Digest quality",
        "measure": "At least 3/5 initially; at least 4.5/5 ideal for conciseness and relevance",
        "target": ">=3/5 initial / >=4.5/5 ideal",
        "status": MANUAL,
        "tests": [
            "test_s10_generates_supported_items_ranked_by_change",
            "test_s10_edit_after_approval_invalidates_approval",
        ],
        "notes": "Two-rater rating protocol in docs/measurement.md §5; not yet measured.",
    },
    {
        "area": "Diagnostic language",
        "measure": "Zero digest items containing diagnoses or health scores",
        "target": "0 items",
        "status": AUTOMATED,
        "tests": [
            "test_s10_patch_rejects_diagnostic_language",
            "test_s10_generation_guard_falls_back_to_safe_template",
            "test_s10_banned_patterns_cover_the_spec_list",
            "test_s2_diagnostic_reply_is_replaced",
        ],
        "notes": "Language guard shared by dialogue and digest generation/edit.",
    },
    {
        "area": "Family contact",
        "measure": "At least 80% successful family-contact requests under the defined test procedure",
        "target": ">=80%",
        "status": MANUAL,
        "tests": [
            "test_s11_senior_contact_action_returns_dial_uri",
            "test_s11_caregiver_can_call_linked_senior_contact",
        ],
        "notes": "Interface-reached and actual-contact rates are measured in docs/measurement.md §6.",
    },
    {
        "area": "Simple setup",
        "measure": "Invite, consent, preferences complete without complex configuration",
        "target": "No complex configuration",
        "status": AUTOMATED,
        "tests": [
            "test_s12_invite_accept_approve_flow",
            "test_consents_are_private_by_default",
            "test_schedule_proposal_approve_applies_preferences",
        ],
        "notes": "Functional flow is tested; configuration time is a manual measure.",
    },
    {
        "area": "Supplementary pilot measures",
        "measure": (
            "Companionship-without-surveillance, autonomy, caregiver reassurance, configuration "
            "time, voluntary sessions, family-call frequency"
        ),
        "target": "Descriptive only",
        "status": MANUAL,
        "tests": ["test_manual_rows_are_documented_in_measurement_protocol"],
        "notes": "No numeric release threshold in the guide; collected descriptively.",
    },
]

# The eight required failure tests (SPEC §10 / guide §8), with the guide's wording.
REQUIRED_FAILURES: list[dict[str, str]] = [
    {
        "test": "failure_revoke_after_draft",
        "requirement": "Revoking a topic after draft generation blocks that topic at delivery and retrieval.",
    },
    {
        "test": "failure_cross_household",
        "requirement": "A caregiver cannot read another household's digest or change the senior's consent.",
    },
    {
        "test": "failure_delete_memory",
        "requirement": "Deleting a memory removes it from subsequent prompts and derived drafts.",
    },
    {
        "test": "failure_stop_late_output",
        "requirement": "Stop during recognition or playback prevents late output from restarting the interaction.",
    },
    {
        "test": "failure_quiet_hours_midnight",
        "requirement": "Quiet hours crossing midnight and time-zone changes do not create extra invitations.",
    },
    {
        "test": "failure_worker_restart",
        "requirement": "Restarting the worker does not publish a duplicate weekly digest.",
    },
    {
        "test": "failure_sparse_data",
        "requirement": "Sparse data produces an honest insufficient-information message.",
    },
    {
        "test": "failure_offline",
        "requirement": (
            "No Internet connection produces clear recovery options without blocking Stop or "
            "system calling."
        ),
    },
]


def _load_eval_wer():
    spec = importlib.util.spec_from_file_location("anchor_eval_wer", SCRIPTS_DIR / "eval_wer.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _section(text: str, heading: str) -> str:
    start = text.index(heading)
    return text[start:]


def _guide_areas() -> list[str]:
    section = _section(GUIDE.read_text(encoding="utf-8"), "## 8. Acceptance criteria and measurement")
    rows: list[str] = []
    for line in section.splitlines():
        if not line.startswith("|"):
            if rows:
                break
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if not cells or cells[0].lower() == "area":
            continue
        if set(cells[0]) <= {"-", ":", " "}:
            continue
        rows.append(cells[0])
    return rows


def _guide_failure_requirements() -> list[str]:
    section = _section(GUIDE.read_text(encoding="utf-8"), "### Required failure tests")
    requirements: list[str] = []
    for line in section.splitlines():
        if line.startswith("## "):
            break
        if line.startswith("- "):
            requirements.append(line[2:].strip())
    return requirements


def _collected_test_names(request=None) -> set[str]:
    """Static view of every collectable test id in the backend suite.

    Parsing the test modules keeps this check valid when only one file is selected
    (`pytest tests/test_acceptance_matrix.py`), where ``request.session.items``
    contains just that file's items.
    """
    names: set[str] = set()
    for path in sorted(TESTS_DIR.glob("test_*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in tree.body:
            if isinstance(node, ast.FunctionDef) and node.name.startswith("test_"):
                names.add(node.name)
            elif isinstance(node, ast.Assign):
                for target in node.targets:
                    if isinstance(target, ast.Name) and target.id.startswith("test_"):
                        names.add(target.id)
    if request is not None:
        for item in request.session.items:
            names.add(item.name.split("[")[0])
            names.add(getattr(item, "originalname", item.name).split("[")[0])
    return names


def _all_test_source() -> str:
    return "\n".join(
        path.read_text(encoding="utf-8") for path in sorted(TESTS_DIR.glob("test_*.py"))
    )


# -- matrix integrity -----------------------------------------------------
def test_acceptance_matrix_covers_every_guide_area():
    areas = _guide_areas()
    assert len(areas) == 11, areas
    matrix_areas = [row["area"] for row in ACCEPTANCE_MATRIX]
    assert matrix_areas[:11] == areas
    assert matrix_areas[11] == "Supplementary pilot measures"
    assert len(ACCEPTANCE_MATRIX) == 12


def test_acceptance_matrix_maps_to_existing_tests():
    collected = _collected_test_names()
    for row in ACCEPTANCE_MATRIX:
        assert row["status"] in (AUTOMATED, MANUAL), row
        assert row["tests"], row["area"]
        assert row["measure"] and row["target"], row["area"]
        for test_id in row["tests"]:
            assert test_id in collected, f"{row['area']} references missing test {test_id}"


def test_acceptance_matrix_maps_every_required_failure_test():
    collected = _collected_test_names()
    source = _all_test_source()
    requirements = _guide_failure_requirements()
    assert len(requirements) == 8, requirements
    assert {item["requirement"] for item in REQUIRED_FAILURES} == set(requirements)

    exact_named = {
        "failure_revoke_after_draft",
        "failure_cross_household",
        "failure_worker_restart",
        "failure_sparse_data",
        "failure_offline",
    }
    for item in REQUIRED_FAILURES:
        name = item["test"]
        if name in exact_named:
            assert f"def {name}(" in source, f"missing exact-named failure test {name}"
        else:
            assert f"def {name}(" in source or f"def test_{name}(" in source, (
                f"missing failure test {name}"
            )
        assert f"test_{name}" in collected, f"{name} is not collected by pytest"


def test_manual_rows_are_documented_in_measurement_protocol():
    assert MEASUREMENT.exists(), f"missing measurement protocol: {MEASUREMENT}"
    text = MEASUREMENT.read_text(encoding="utf-8")
    lowered = text.lower()
    assert "not yet measured" in lowered
    manual_rows = [row for row in ACCEPTANCE_MATRIX if row["status"] == MANUAL]
    assert manual_rows
    for row in manual_rows:
        assert row["area"] in text, f"{row['area']} missing from docs/measurement.md"
        assert "MANUAL" in text or "not yet measured" in lowered


# -- WER evaluator --------------------------------------------------------
def test_eval_wer_computes_classic_alignment():
    wer = _load_eval_wer()
    counts = wer.compute_wer("a b c", "a x c", "space")
    assert (counts["S"], counts["D"], counts["I"], counts["N"]) == (1, 0, 0, 3)
    assert counts["wer"] == pytest.approx(1 / 3, abs=1e-6)


def test_eval_wer_counts_deletions_and_insertions():
    wer = _load_eval_wer()
    deleted = wer.compute_wer("a b c d", "a c", "space")
    assert (deleted["S"], deleted["D"], deleted["I"], deleted["N"]) == (0, 2, 0, 4)
    inserted = wer.compute_wer("a b", "a b c", "space")
    assert (inserted["S"], inserted["D"], inserted["I"], inserted["N"]) == (0, 0, 1, 2)


def test_eval_wer_char_tokenizer_handles_mandarin():
    wer = _load_eval_wer()
    counts = wer.compute_wer("今天天气很好", "今天天气好", "char")
    assert counts["N"] == 6
    assert counts["D"] == 1
    assert counts["S"] == 0 and counts["I"] == 0
    assert counts["wer"] == pytest.approx(1 / 6, abs=1e-6)
    # Whitespace is not a token in the Mandarin character tokenizer.
    assert wer.compute_wer("你 好", "你好", "char")["wer"] == 0.0


def test_eval_wer_reports_dialect_groups():
    wer = _load_eval_wer()
    report = wer.evaluate(
        [
            {"id": "1", "reference": "a b", "transcript": "a b", "dialect": "mandarin"},
            {"id": "2", "reference": "a b", "transcript": "a x", "dialect": "wu"},
            {"id": "3", "reference": "a b", "transcript": "a b", "dialect": "wu"},
        ],
        tokenizer="space",
        group_field="dialect",
    )
    assert set(report["groups"]) == {"mandarin", "wu"}
    assert report["groups"]["mandarin"]["wer"] == 0.0
    assert report["groups"]["wu"]["wer"] == pytest.approx(0.25)
    assert report["overall"]["S"] == 1
    assert report["overall"]["N"] == 6
    assert report["skipped"] == 0


def test_eval_wer_cli_reads_reference_and_hypothesis_files(tmp_path, capsys):
    reference = tmp_path / "reference.json"
    hypothesis = tmp_path / "hypothesis.json"
    reference.write_text(
        json.dumps(
            [
                {"id": "u1", "reference": "你好 世界", "dialect": "mandarin"},
                {"id": "u2", "reference": "吃饭 了 吗", "dialect": "wu"},
            ],
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    hypothesis.write_text(
        json.dumps(
            [
                {"id": "u1", "transcript": "你好 世界"},
                {"id": "u2", "transcript": "吃饭 吗"},
            ],
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    wer = _load_eval_wer()
    assert (
        wer.main(
            [
                "--reference",
                str(reference),
                "--hypothesis",
                str(hypothesis),
                "--tokenizer",
                "space",
                "--group",
                "dialect",
                "--json",
            ]
        )
        == 0
    )
    printed = capsys.readouterr().out
    report = json.loads(printed)
    assert set(report["groups"]) == {"mandarin", "wu"}
    assert report["overall"]["N"] == 5


def test_eval_wer_rejects_empty_reference():
    wer = _load_eval_wer()
    with pytest.raises(ValueError):
        wer.compute_wer("   ", "anything", "char")


# -- required failure test (offline slice) -------------------------------
def failure_offline(client, app, use_providers, senior, senior_token):
    """No provider is reachable, yet Stop and system calling still work."""
    health = client.get("/api/v1/health").json()
    assert {"stop", "settings", "cached_activities", "system_calling"} <= set(
        health["offline_capabilities"]
    )

    seed_consents(app, senior, cloud_processing=True, record_observations=True)
    use_providers(llm=FailingLLM())
    session = client.post(
        "/api/v1/sessions", json={"origin": "voluntary"}, headers=headers(senior_token)
    )
    assert session.status_code == 200, session.text
    session_id = session.json()["session_id"]

    failed = client.post(
        f"/api/v1/sessions/{session_id}/turns",
        json={"text": "你好"},
        headers=headers(senior_token),
    )
    assert failed.status_code == 503
    error = failed.json()["error"]
    assert error["code"] == "provider_unavailable"
    assert "retry" in error["recovery"] and "type_instead" in error["recovery"]

    stopped = client.post(
        f"/api/v1/sessions/{session_id}/stop", headers=headers(senior_token)
    )
    assert stopped.status_code == 200
    assert stopped.json()["state"] == "stopped"

    # System calling is local: no provider call is involved.
    contact_id = insert_contact(app, senior)
    call = client.post(
        "/api/v1/contact-actions",
        json={"contact_id": contact_id},
        headers=headers(senior_token),
    )
    assert call.status_code == 200
    assert call.json()["dial_uri"].startswith("tel:")


# SPEC §10 names this test exactly ``failure_offline``; expose a collectable alias.
test_failure_offline = failure_offline
