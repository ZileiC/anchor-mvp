"""Adequate-data rule and per-topic comparison against the same person's baseline.

SPEC §7 / guide §5.6:

* a week is describable only with at least 3 distinct observed days in the period
  and at least 6 distinct observed days in the 14 days before it;
* a topic is compared with that same person's per-day rate over the previous 14
  days; a change is a difference of >= 0.5 observations/day, or a topic that had
  no prior evidence at all;
* only observations whose topic is currently permitted for sharing take part in
  the calculation, so a revoked topic cannot leak through aggregate statistics.

This module returns *candidates* with evidence ids only. Raw evidence text never
leaves it; rendering is :mod:`app.digests.render`.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import Any, Iterable

from ..db import Database

CURRENT_WINDOW_DAYS = 7
BASELINE_WINDOW_DAYS = 14
MIN_CURRENT_OBSERVED_DAYS = 3
MIN_PRIOR_OBSERVED_DAYS = 6
CHANGE_THRESHOLD_PER_DAY = 0.5
MAX_ITEMS = 3
MAX_EVIDENCE_PER_ITEM = 3
TOPIC_ORDER = ("participation", "activities", "mood", "meals", "wellbeing")


def as_day(value: str | date) -> date:
    return value if isinstance(value, date) else date.fromisoformat(str(value))


def prior_window(period_start: str | date) -> tuple[date, date]:
    start = as_day(period_start) - timedelta(days=BASELINE_WINDOW_DAYS)
    return start, as_day(period_start)


def _topic_filter(topics: Iterable[str]) -> list[str]:
    permitted = set(topics)
    return [topic for topic in TOPIC_ORDER if topic in permitted]


def observed_days(
    db: Database,
    senior_id: int,
    start: str | date,
    end: str | date,
    topics: Iterable[str],
) -> int:
    """Distinct local dates with at least one observation in ``[start, end)``."""
    topics = _topic_filter(topics)
    if not topics:
        return 0
    placeholders = ",".join("?" for _ in topics)
    row = db.query_one(
        "SELECT COUNT(DISTINCT event_date) AS n FROM observations "
        f"WHERE senior_id = ? AND event_date >= ? AND event_date < ? AND topic IN ({placeholders})",
        (int(senior_id), as_day(start).isoformat(), as_day(end).isoformat(), *topics),
    )
    return int(row["n"]) if row else 0


def adequate_data(
    db: Database,
    senior_id: int,
    period_start: str | date,
    period_end: str | date,
    topics: Iterable[str],
) -> bool:
    """The honest-data gate from SPEC §7.2, restricted to permitted topics."""
    current = observed_days(db, senior_id, period_start, period_end, topics)
    if current < MIN_CURRENT_OBSERVED_DAYS:
        return False
    prior_start, prior_end = prior_window(period_start)
    prior = observed_days(db, senior_id, prior_start, prior_end, topics)
    return prior >= MIN_PRIOR_OBSERVED_DAYS


def topic_counts(
    db: Database,
    senior_id: int,
    start: str | date,
    end: str | date,
    topics: Iterable[str],
) -> dict[str, int]:
    topics = _topic_filter(topics)
    if not topics:
        return {}
    placeholders = ",".join("?" for _ in topics)
    rows = db.query(
        "SELECT topic, COUNT(DISTINCT event_date) AS n FROM observations "
        f"WHERE senior_id = ? AND event_date >= ? AND event_date < ? AND topic IN ({placeholders}) "
        "GROUP BY topic",
        (int(senior_id), as_day(start).isoformat(), as_day(end).isoformat(), *topics),
    )
    return {str(row["topic"]): int(row["n"]) for row in rows}


def _evidence_ids(
    db: Database, senior_id: int, topic: str, start: str | date, end: str | date
) -> list[int]:
    rows = db.query(
        "SELECT id FROM observations "
        "WHERE senior_id = ? AND topic = ? AND event_date >= ? AND event_date < ? "
        "ORDER BY event_date DESC, id DESC LIMIT ?",
        (
            int(senior_id),
            topic,
            as_day(start).isoformat(),
            as_day(end).isoformat(),
            MAX_EVIDENCE_PER_ITEM,
        ),
    )
    return [int(row["id"]) for row in rows]


def select_candidates(
    db: Database,
    senior_id: int,
    period_start: str | date,
    period_end: str | date,
    permitted_topics: Iterable[str],
) -> list[dict[str, Any]]:
    """Rank permitted topics by change first, then frequency (SPEC §7.4).

    Returns at most :data:`MAX_ITEMS` candidates. Every candidate carries at least
    one evidence id from the current period, or it is dropped.
    """
    topics = _topic_filter(permitted_topics)
    if not topics:
        return []
    current_counts = topic_counts(db, senior_id, period_start, period_end, topics)
    prior_start, prior_end = prior_window(period_start)
    baseline_counts = topic_counts(db, senior_id, prior_start, prior_end, topics)

    candidates: list[dict[str, Any]] = []
    for order, topic in enumerate(topics):
        current_count = current_counts.get(topic, 0)
        if current_count == 0:
            continue
        baseline_count = baseline_counts.get(topic, 0)
        current_rate = current_count / CURRENT_WINDOW_DAYS
        baseline_rate = baseline_count / BASELINE_WINDOW_DAYS
        delta = current_rate - baseline_rate
        appeared = baseline_count == 0
        changed = appeared or abs(delta) >= CHANGE_THRESHOLD_PER_DAY
        evidence = _evidence_ids(db, senior_id, topic, period_start, period_end)
        if not evidence:
            continue
        candidates.append(
            {
                "topic": topic,
                "topic_order": order,
                "current_count": current_count,
                "baseline_count": baseline_count,
                "delta": delta,
                "changed": changed,
                "appeared": appeared,
                "evidence_ids": evidence,
            }
        )

    candidates.sort(
        key=lambda item: (
            0 if item["changed"] else 1,
            -abs(item["delta"]),
            -item["current_count"],
            item["topic_order"],
        )
    )
    return candidates[:MAX_ITEMS]


__all__ = [
    "BASELINE_WINDOW_DAYS",
    "CHANGE_THRESHOLD_PER_DAY",
    "CURRENT_WINDOW_DAYS",
    "MAX_EVIDENCE_PER_ITEM",
    "MAX_ITEMS",
    "MIN_CURRENT_OBSERVED_DAYS",
    "MIN_PRIOR_OBSERVED_DAYS",
    "TOPIC_ORDER",
    "adequate_data",
    "as_day",
    "observed_days",
    "prior_window",
    "select_candidates",
    "topic_counts",
]
