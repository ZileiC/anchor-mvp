"""Generic notification helpers (SPEC §6.6 / §7 delivery rules).

Notifications never carry health content, transcript text or digest items — only
"something is ready" phrasing, localised to the recipient's stored locale.
"""

from __future__ import annotations

from typing import Any, Optional, Protocol

from ..clock import Clock, iso_utc
from ..db import Database

# (zh-CN, en) title/body pairs; generic by design.
MESSAGES: dict[str, dict[str, tuple[str, str]]] = {
    "relationship_approved": {
        "zh-CN": ("家人已接受连接请求", "现在可以看到经过同意的家庭简报。"),
        "en": ("Family connection accepted", "You can now see the weekly update they share."),
    },
    "relationship_invited": {
        "zh-CN": ("收到一个新的连接邀请", "请在应用里输入邀请码完成连接。"),
        "en": ("New family invitation", "Enter the invitation code in the app to connect."),
    },
    "digest_ready": {
        "zh-CN": ("本周家庭简报已就绪", "打开应用查看老人同意分享的内容。"),
        "en": ("Weekly update ready", "Open the app to read what they agreed to share."),
    },
}


class Notifier(Protocol):
    def notify(self, user_id: int, kind: str, message_key: str) -> int: ...


class DatabaseNotifier:
    """Writes a row to ``notifications``; push delivery is out of MVP scope."""

    def __init__(self, db: Database, clock: Clock) -> None:
        self.db = db
        self.clock = clock

    def notify(self, user_id: int, kind: str, message_key: str) -> int:
        locale = "zh-CN"
        row = self.db.query_one("SELECT locale FROM users WHERE id = ?", (user_id,))
        if row is not None and row["locale"] == "en":
            locale = "en"
        title, body = MESSAGES[message_key][locale]
        return self.db.insert(
            "INSERT INTO notifications(user_id, kind, title, body, created_at) VALUES (?,?,?,?,?)",
            (user_id, kind, title, body, iso_utc(self.clock.now())),
        )


def notification_kind(message_key: str) -> str:
    if message_key == "digest_ready":
        return "digest_ready"
    if message_key.startswith("relationship"):
        return "relationship"
    return "invitation"


def maybe_locale(value: Optional[str]) -> str:
    return "en" if value == "en" else "zh-CN"


def notification_payload(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": row["id"],
        "kind": row["kind"],
        "title": row["title"],
        "body": row["body"],
        "read_at": row["read_at"],
        "created_at": row["created_at"],
    }
