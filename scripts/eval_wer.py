#!/usr/bin/env python
"""Word error rate evaluator for the §8 speech-recognition measurement.

WER = (substitutions + deletions + insertions) / reference tokens.

Mandarin has no word delimiters, so the default tokenizer is ``char``: whitespace
is removed and every remaining character is one token. ``--tokenizer space`` is
available for pre-segmented reference transcripts (for example after jieba or a
human word segmentation). Punctuation is kept as a token; the protocol in
``docs/measurement.md`` requires one consistent rule across runs.

Input JSON may be a list of records or an object ``{"items": [...]}``. A reference
record needs ``id`` and ``reference``; its transcript may be embedded as
``hypothesis``/``transcript`` or supplied separately with ``--hypothesis`` (records
matched by ``id``). An optional ``dialect`` field is reported as its own group so a
Mandarin group and dialect groups are never averaged into one number.

Usage::

    python scripts/eval_wer.py --reference ref.json --hypothesis hyp.json \
        --tokenizer char --group dialect
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Iterable, Optional, Sequence

TOKENIZERS = ("char", "space")
DEFAULT_TOKENIZER = "char"


def tokenize(text: str, tokenizer: str = DEFAULT_TOKENIZER) -> list[str]:
    if not isinstance(text, str):
        raise ValueError("text must be a string")
    if tokenizer == "char":
        return [character for character in text if not character.isspace()]
    if tokenizer == "space":
        return [token for token in text.split() if token]
    raise ValueError(f"unknown tokenizer: {tokenizer!r}; use one of {list(TOKENIZERS)}")


def align_counts(reference: Iterable[str], hypothesis: Iterable[str]) -> dict[str, int]:
    """Levenshtein alignment returning substitution/deletion/insertion counts."""
    ref = list(reference)
    hyp = list(hypothesis)
    n, m = len(ref), len(hyp)
    # dp[i][j] = edit distance between ref[:i] and hyp[:j]
    dp = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        dp[i][0] = i
    for j in range(m + 1):
        dp[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            cost = 0 if ref[i - 1] == hyp[j - 1] else 1
            dp[i][j] = min(
                dp[i - 1][j - 1] + cost,
                dp[i - 1][j] + 1,
                dp[i][j - 1] + 1,
            )

    substitutions = deletions = insertions = 0
    i, j = n, m
    while i > 0 or j > 0:
        if i > 0 and j > 0 and ref[i - 1] == hyp[j - 1] and dp[i][j] == dp[i - 1][j - 1]:
            i -= 1
            j -= 1
        elif i > 0 and j > 0 and dp[i][j] == dp[i - 1][j - 1] + 1:
            substitutions += 1
            i -= 1
            j -= 1
        elif i > 0 and dp[i][j] == dp[i - 1][j] + 1:
            deletions += 1
            i -= 1
        else:
            insertions += 1
            j -= 1
    return {"S": substitutions, "D": deletions, "I": insertions, "N": n}


def compute_wer(
    reference: str, hypothesis: str, tokenizer: str = DEFAULT_TOKENIZER
) -> dict[str, Any]:
    ref_tokens = tokenize(reference, tokenizer)
    if not ref_tokens:
        raise ValueError("reference transcript has no tokens")
    counts = align_counts(ref_tokens, tokenize(hypothesis, tokenizer))
    counts["wer"] = round((counts["S"] + counts["D"] + counts["I"]) / counts["N"], 6)
    counts["reference_tokens"] = counts["N"]
    return counts


def _records(payload: Any, label: str) -> list[dict[str, Any]]:
    if isinstance(payload, list):
        records = payload
    elif isinstance(payload, dict) and isinstance(payload.get("items"), list):
        records = payload["items"]
    elif isinstance(payload, dict) and all(isinstance(value, dict) for value in payload.values()):
        records = list(payload.values())
    else:
        raise ValueError(f"{label} must be a list or an object with an 'items' list")
    return [record for record in records if isinstance(record, dict)]


def load_records(path: str | Path, label: str = "reference") -> list[dict[str, Any]]:
    with Path(path).open("r", encoding="utf-8") as handle:
        return _records(json.load(handle), label)


def _transcript(record: dict[str, Any]) -> Optional[str]:
    for key in ("transcript", "hypothesis"):
        value = record.get(key)
        if isinstance(value, str):
            return value
    return None


def _accumulate(bucket: dict[str, Any], counts: dict[str, int]) -> None:
    for key in ("S", "D", "I"):
        bucket[key] += counts[key]
    bucket["N"] += counts["N"]
    bucket["records"] += 1


def _finalise(bucket: dict[str, Any]) -> dict[str, Any]:
    total = bucket["S"] + bucket["D"] + bucket["I"]
    bucket["wer"] = round(total / bucket["N"], 6) if bucket["N"] else 0.0
    return bucket


def evaluate(
    references: Sequence[dict[str, Any]],
    hypotheses: Optional[Sequence[dict[str, Any]]] = None,
    tokenizer: str = DEFAULT_TOKENIZER,
    group_field: str = "dialect",
) -> dict[str, Any]:
    """Evaluate references against hypotheses; group rows by ``group_field``."""
    hypotheses_by_id: dict[str, dict[str, Any]] = {}
    for record in hypotheses or []:
        identifier = record.get("id")
        if identifier is not None:
            hypotheses_by_id[str(identifier)] = record

    overall: dict[str, Any] = {"S": 0, "D": 0, "I": 0, "N": 0, "records": 0}
    groups: dict[str, dict[str, Any]] = {}
    skipped = 0
    for record in references:
        identifier = str(record.get("id", ""))
        reference_text = record.get("reference")
        if not isinstance(reference_text, str) or not tokenize(reference_text, tokenizer):
            skipped += 1
            continue
        hypothesis_text = _transcript(record)
        if hypothesis_text is None and hypotheses is not None:
            matched = hypotheses_by_id.get(identifier)
            hypothesis_text = _transcript(matched) if matched else None
        if hypothesis_text is None:
            raise ValueError(f"missing transcript for record {identifier or '<no id>'}")
        counts = compute_wer(reference_text, hypothesis_text, tokenizer)
        _accumulate(overall, counts)
        group_name = str(record.get(group_field) or "unspecified")
        bucket = groups.setdefault(
            group_name, {"S": 0, "D": 0, "I": 0, "N": 0, "records": 0}
        )
        _accumulate(bucket, counts)

    return {
        "tokenizer": tokenizer,
        "group": group_field,
        "overall": _finalise(overall),
        "groups": {name: _finalise(bucket) for name, bucket in sorted(groups.items())},
        "skipped": skipped,
    }


def format_report(report: dict[str, Any]) -> str:
    lines = [
        f"tokenizer={report['tokenizer']} groups by {report['group']!r} "
        f"skipped={report['skipped']}",
        f"{'group':<20} {'WER':>8} {'S':>5} {'D':>5} {'I':>5} {'N':>6} {'n':>4}",
    ]
    rows = [("ALL", report["overall"])] + list(report["groups"].items())
    for name, bucket in rows:
        lines.append(
            f"{name:<20} {bucket['wer'] * 100:7.2f}% {bucket['S']:5d} {bucket['D']:5d} "
            f"{bucket['I']:5d} {bucket['N']:6d} {bucket['records']:4d}"
        )
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Compute WER for Anchor speech evaluation")
    parser.add_argument("--reference", required=True, help="reference JSON path")
    parser.add_argument("--hypothesis", default=None, help="optional transcript JSON path")
    parser.add_argument("--tokenizer", choices=TOKENIZERS, default=DEFAULT_TOKENIZER)
    parser.add_argument("--group", default="dialect", help="record field used for grouping")
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON only")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    references = load_records(args.reference, "reference")
    hypotheses = load_records(args.hypothesis, "hypothesis") if args.hypothesis else None
    report = evaluate(references, hypotheses, args.tokenizer, args.group)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(format_report(report))
        print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":  # pragma: no cover - CLI entry point
    sys.exit(main())
