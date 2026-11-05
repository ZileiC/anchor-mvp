"""Identity adapter: HMAC-signed bearer tokens (no password storage).

``issue_token`` accepts either a Clock or an aware datetime so scripts and tests
can be explicit. A production deployment swaps the token source for an OIDC
adapter; the payload shape stays the same.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
from datetime import datetime, timezone
from typing import Any, Union

from fastapi import Request

from .config import Settings
from .errors import unauthorized

TimeSource = Union[Any, datetime]


def _now(source: TimeSource) -> datetime:
    if isinstance(source, datetime):
        return source
    return source.now()


def _b64e(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _b64d(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)


def _sign(payload: str, secret: str) -> str:
    return _b64e(hmac.new(secret.encode("utf-8"), payload.encode("ascii"), hashlib.sha256).digest())


def issue_token(
    settings: Settings,
    user_id: int,
    role: str,
    clock: TimeSource,
) -> tuple[str, dict[str, Any]]:
    moment = _now(clock)
    claims = {
        "sub": int(user_id),
        "role": role,
        "exp": int(moment.timestamp()) + settings.token_ttl_seconds,
    }
    payload = json.dumps(claims, separators=(",", ":"), sort_keys=True)
    encoded = _b64e(payload.encode("utf-8"))
    return f"{encoded}.{_sign(encoded, settings.secret)}", claims


def decode_token(token: str, settings: Settings, clock: TimeSource) -> dict[str, Any]:
    try:
        encoded, signature = token.split(".", 1)
    except ValueError:
        raise unauthorized("Malformed token")
    if not hmac.compare_digest(signature, _sign(encoded, settings.secret)):
        raise unauthorized("Invalid token signature")
    try:
        claims = json.loads(_b64d(encoded).decode("utf-8"))
    except (ValueError, TypeError):
        raise unauthorized("Malformed token payload")
    if int(claims.get("exp", 0)) <= int(_now(clock).timestamp()):
        raise unauthorized("Token expired")
    if claims.get("role") not in ("senior", "caregiver"):
        raise unauthorized("Unknown role")
    return claims


def token_from_request(request: Request) -> str:
    header = request.headers.get("authorization") or ""
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise unauthorized()
    return token.strip()


def get_current_user(request: Request) -> dict[str, Any]:
    state = request.app.state
    claims = decode_token(token_from_request(request), state.settings, state.clock)
    row = state.db.query_one(
        "SELECT id, role, display_name, timezone, locale FROM users WHERE id = ?",
        (claims["sub"],),
    )
    if row is None or row["role"] != claims["role"]:
        raise unauthorized("Unknown user")
    return row
