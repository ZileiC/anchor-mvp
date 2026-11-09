#!/usr/bin/env python
"""Developer CLI for the deterministic Anchor demo seed.

Run from ``anchor/backend`` with the project venv:

    ..\\.venv\\Scripts\\python.exe ..\\scripts\\seed_demo.py
    ..\\.venv\\Scripts\\python.exe ..\\scripts\\seed_demo.py --check

The demo world itself lives in ``app/demo_seed.py`` (shared with the packaged
``anchor_backend.exe``); this file is only the command line around it.

``--check`` seeds a throw-away temporary database, runs the seeder twice to prove
idempotency, generates the previous week's digest to prove the adequate-data rule
passes, prints a summary and deletes the temporary database. It never writes to
the configured ``ANCHOR_DB_PATH``.

``--demo-window`` widens the greeting window to 09:00–21:00 (the window the
packaged Windows demo uses); without it the historical 09:00–11:00 window is
kept, so the default seed behaviour is unchanged.
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path
from typing import Optional, Sequence

SCRIPTS_DIR = Path(__file__).resolve().parent
ANCHOR_DIR = SCRIPTS_DIR.parent
BACKEND_DIR = ANCHOR_DIR / "backend"
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.clock import Clock  # noqa: E402
from app.config import Settings  # noqa: E402
from app.db import Database  # noqa: E402
from app.demo_seed import (  # noqa: E402
    ACTIVITY_ROTATION,
    CAREGIVER_ID,
    CAREGIVER_NAME,
    DEMO_GREETING_WINDOW,
    NORMAL_GREETING_WINDOW,
    OBSERVATION_PLAN,
    SENIOR_ID,
    SENIOR_NAME,
    SHARE_TOPICS,
    seed_demo,
    weekly_digest,
)


def check(settings: Settings, demo_window: bool = False) -> int:
    """Seed a temporary database twice and validate; never touches the real DB."""
    with tempfile.TemporaryDirectory(prefix="anchor-demo-check-") as tmp:
        temp_settings = settings.with_(db_path=str(Path(tmp) / "demo-check.db"))
        database = Database(temp_settings.db_path)
        database.migrate()
        clock = Clock()
        try:
            first = seed_demo(database, clock, temp_settings, demo_window=demo_window)
            second = seed_demo(database, clock, temp_settings, demo_window=demo_window)
            problems: list[str] = []
            if first != second:
                problems.append(f"seeding is not idempotent: {first} != {second}")
            expected = {
                "users": 2,
                "contacts": 2,
                "observations": len(OBSERVATION_PLAN),
                "memories": 1,
                "activity_rotation": len(ACTIVITY_ROTATION),
            }
            for key, value in expected.items():
                if second.get(key) != value:
                    problems.append(f"{key}: expected {value}, got {second.get(key)}")
            if second.get("relationship") != "accepted":
                problems.append("relationship is not accepted")
            if second.get("share_topics") != list(SHARE_TOPICS):
                problems.append(f"share topics incomplete: {second.get('share_topics')}")
            if second.get("designated_device_id") != "anchor-win-demo-1":
                problems.append("designated device missing")

            greeting_start, greeting_end = (
                DEMO_GREETING_WINDOW if demo_window else NORMAL_GREETING_WINDOW
            )
            preferences = database.query_one(
                "SELECT greeting_start, greeting_end FROM preferences WHERE senior_id = ?",
                (SENIOR_ID,),
            )
            if preferences != {"greeting_start": greeting_start, "greeting_end": greeting_end}:
                problems.append(f"greeting window wrong: {preferences}")

            digest = weekly_digest(database, clock, temp_settings)
            if digest["status"] != "draft" or not digest["items"]:
                problems.append(f"previous-week digest was not generated: {digest['status']}")

            print(f"demo senior #{SENIOR_ID} {SENIOR_NAME}; caregiver #{CAREGIVER_ID} {CAREGIVER_NAME}")
            print(json.dumps({**second, "digest_status": digest["status"]}, ensure_ascii=False))
            if problems:
                for problem in problems:
                    print(f"CHECK FAILED: {problem}", file=sys.stderr)
                return 1
            print("CHECK OK: demo data is idempotent and supports a weekly digest")
            return 0
        finally:
            database.close()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Seed Anchor demo data")
    parser.add_argument("--check", action="store_true", help="validate on a temp DB, write nothing")
    parser.add_argument("--db", default=None, help="override ANCHOR_DB_PATH")
    parser.add_argument(
        "--demo-window",
        action="store_true",
        help="widen the greeting window to 09:00-21:00 (packaged demo default)",
    )
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    settings = Settings.from_env()
    if args.db:
        settings = settings.with_(db_path=args.db)
    if args.check:
        return check(settings, demo_window=args.demo_window)

    database = Database(settings.db_path)
    database.migrate()
    clock = Clock()
    try:
        summary = seed_demo(database, clock, settings, demo_window=args.demo_window)
        summary["digest"] = weekly_digest(database, clock, settings)
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        print(f"seeded demo data into {settings.db_path}")
        return 0
    finally:
        database.close()


if __name__ == "__main__":
    raise SystemExit(main())
