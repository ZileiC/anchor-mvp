"""Anchor worker: ``python -m app.worker [--once] [--seed-jobs]``.

The worker owns the persistent-job loop described in SPEC §8. ``--once`` queues
anything that is due (this week's digest, today's retention purge) and drains the
queue exactly once, which is what demos and smoke checks use. Continuous mode
sleeps between passes; no test invokes it.
"""

from __future__ import annotations

import argparse
import json
import time
from typing import Optional, Sequence

from .clock import Clock
from .config import Settings
from .context import AppContext
from .db import Database
from .jobs import JobRunner, enqueue_due_jobs


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -m app.worker", description="Anchor job worker")
    parser.add_argument("--once", action="store_true", help="queue due jobs and run them once")
    parser.add_argument(
        "--seed-jobs", action="store_true", help="only queue due jobs, then exit (demo helper)"
    )
    parser.add_argument("--interval", type=int, default=None, help="seconds between passes")
    parser.add_argument("--db", type=str, default=None, help="override ANCHOR_DB_PATH")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    settings = Settings.from_env()
    if args.db:
        settings = settings.with_(db_path=args.db)

    database = Database(settings.db_path)
    database.migrate()
    ctx = AppContext(settings, database, Clock())
    runner = JobRunner(ctx, settings.job_lease_seconds)
    try:
        if args.seed_jobs:
            print(json.dumps(enqueue_due_jobs(ctx), ensure_ascii=False))
            return 0
        if args.once:
            queued = enqueue_due_jobs(ctx)
            executed = runner.run_once()
            print(json.dumps({"queued": queued, "executed": executed}, ensure_ascii=False))
            return 0

        interval = args.interval if args.interval is not None else settings.worker_interval_seconds
        interval = max(1, int(interval))
        print(f"anchor worker running every {interval}s (Ctrl+C to stop)")
        while True:
            enqueue_due_jobs(ctx)
            runner.run_once()
            time.sleep(interval)
    except KeyboardInterrupt:  # pragma: no cover - interactive only
        print("anchor worker stopped")
    finally:
        ctx.close()
    return 0


if __name__ == "__main__":  # pragma: no cover - module entry point
    raise SystemExit(main())
