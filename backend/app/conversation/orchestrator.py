"""Turn pipeline, cancellation and session lifecycle (SPEC §6.3).

Order matters and is fixed: state check -> consent check -> transcription ->
deterministic command routing -> model reply -> persistence. Nothing is written
before the model answers, so a stop during generation leaves no late turn behind.
"""

from __future__ import annotations

import base64
import binascii
import json
import uuid
from typing import Any, Optional

from .. import audit
from ..activities.engine import ActivityEngine
from ..clock import Clock, in_window, iso_utc, local_date_str
from ..consent import ConsentService
from ..db import Database
from ..digests.language_guard import is_clean
from ..errors import AppError, validation_error
from ..memory import MemoryService
from ..preferences import PreferencesService
from . import commands
from .prompt import build_system_prompt

HISTORY_TURNS = 6
EVIDENCE_LIMIT = 140

TEXT = {
    "zh-CN": {
        "greeting": "早上好。今天想聊点什么？",
        "repeat_empty": "我刚才没说话呀。",
        "play": "好，我们玩：{title}。",
        "call_empty": "还没有保存联系人。",
        "call_choose": "想给谁打电话？{options}",
        "call_confirm": "要给{label}打电话吗？",
        "safe_reply": "我听着呢。能再多说说吗？",
        "activity_observation": "完成了活动：{title}（{duration}秒）",
    },
    "en": {
        "greeting": "Good morning. What would you like to talk about today?",
        "repeat_empty": "I haven't said anything yet.",
        "play": "Okay, let's play: {title}.",
        "call_empty": "There are no saved contacts yet.",
        "call_choose": "Who would you like to call? {options}",
        "call_confirm": "Would you like to call {label}?",
        "safe_reply": "I'm listening. Could you tell me a little more?",
        "activity_observation": "Completed activity: {title} ({duration}s)",
    },
}


class ConversationOrchestrator:
    def __init__(
        self,
        db: Database,
        clock: Clock,
        providers: dict[str, Any],
        consent: Optional[ConsentService] = None,
        preferences: Optional[PreferencesService] = None,
        memories: Optional[MemoryService] = None,
        activities: Optional[ActivityEngine] = None,
    ) -> None:
        self.db = db
        self.clock = clock
        self.providers = providers
        self.consent = consent or ConsentService(db, clock)
        self.preferences = preferences or PreferencesService(db, clock)
        self.memories = memories or MemoryService(db, clock, self.consent)
        self.activities = activities or ActivityEngine(db, clock, self.consent, self.preferences)

    # -- helpers ----------------------------------------------------------
    def _locale(self, senior: dict[str, Any]) -> str:
        return "en" if senior["locale"] == "en" else "zh-CN"

    def _texts(self, senior: dict[str, Any]) -> dict[str, str]:
        return TEXT[self._locale(senior)]

    def _now_local(self, senior: dict[str, Any]) -> Any:
        from zoneinfo import ZoneInfo

        return self.clock.now().astimezone(ZoneInfo(senior["timezone"]))

    def _session(self, session_id: str, senior_id: int) -> dict[str, Any]:
        row = self.db.query_one("SELECT * FROM sessions WHERE id = ?", (session_id,))
        if row is None or int(row["senior_id"]) != int(senior_id):
            raise AppError("not_found", "Conversation not found.")
        return row

    def _write_turn(self, session_id: str, role: str, text: str) -> int:
        return self.db.insert(
            "INSERT INTO turns(session_id, role, text, created_at) VALUES (?,?,?,?)",
            (session_id, role, text, iso_utc(self.clock.now())),
        )

    def captions(self, session_id: str) -> list[dict[str, Any]]:
        rows = self.db.query(
            "SELECT role, text, created_at FROM turns WHERE session_id = ? ORDER BY id",
            (session_id,),
        )
        return [
            {"role": row["role"], "text": row["text"], "at": row["created_at"]} for row in rows
        ]

    def _active_session(self, senior_id: int) -> Optional[dict[str, Any]]:
        return self.db.query_one(
            "SELECT * FROM sessions WHERE senior_id = ? AND state = 'active' "
            "ORDER BY started_at DESC LIMIT 1",
            (senior_id,),
        )

    # -- sessions ---------------------------------------------------------
    def open_session(
        self, senior: dict[str, Any], origin: str, device_id: Optional[str] = None
    ) -> dict[str, Any]:
        if origin not in ("voluntary", "proactive"):
            raise validation_error("origin must be voluntary or proactive")
        senior_id = int(senior["id"])
        self.consent.require(senior_id, "cloud_processing")
        existing = self._active_session(senior_id)
        if existing is not None:
            raise AppError(
                "conflict",
                "A conversation is already open.",
                session_id=existing["id"],
            )
        session_id = str(uuid.uuid4())
        now = iso_utc(self.clock.now())
        self.db.execute(
            "INSERT INTO sessions(id, senior_id, origin, state, cancellation_token, started_at) "
            "VALUES (?,?,?,?,?,?)",
            (session_id, senior_id, origin, "active", str(uuid.uuid4()), now),
        )
        greeting: Optional[str] = None
        prefs = self.preferences.get_or_create(senior_id)
        if origin == "proactive" and in_window(
            self._now_local(senior), prefs["greeting_start"], prefs["greeting_end"]
        ):
            greeting = self._texts(senior)["greeting"]
            self._write_turn(session_id, "anchor", greeting)
        payload = {
            "session_id": session_id,
            "state": "active",
            "mic_on": True,
            "started_at": now,
        }
        if greeting:
            payload["greeting_text"] = greeting
        return payload

    def session_view(self, session_id: str, senior_id: int) -> dict[str, Any]:
        row = self._session(session_id, senior_id)
        return {
            "session_id": row["id"],
            "state": row["state"],
            "started_at": row["started_at"],
            "ended_at": row["ended_at"],
            "captions": self.captions(session_id),
            "mic_on": row["state"] == "active",
        }

    def stop(self, session_id: str, senior_id: int) -> dict[str, Any]:
        row = self._session(session_id, senior_id)
        if row["state"] != "stopped":
            with self.db.tx() as conn:
                conn.execute(
                    "UPDATE sessions SET state = 'stopped', ended_at = ? WHERE id = ?",
                    (iso_utc(self.clock.now()), session_id),
                )
                conn.execute("DELETE FROM turns WHERE session_id = ?", (session_id,))
        return {"state": "stopped"}

    # -- turns ------------------------------------------------------------
    def _cancelled(self, session_id: str) -> bool:
        row = self.db.query_one("SELECT state FROM sessions WHERE id = ?", (session_id,))
        return row is None or row["state"] != "active"

    def turn(
        self,
        senior: dict[str, Any],
        session_id: str,
        text: Optional[str] = None,
        audio_b64: Optional[str] = None,
        audio_mime: Optional[str] = None,
    ) -> dict[str, Any]:
        senior_id = int(senior["id"])
        session = self._session(session_id, senior_id)
        if session["state"] != "active":
            raise AppError("session_stopped", "This conversation has stopped.")
        self.consent.require(senior_id, "cloud_processing")

        if audio_b64 is not None:
            try:
                audio = base64.b64decode(audio_b64, validate=True)
            except (binascii.Error, ValueError) as exc:
                raise validation_error("audio_b64 is not valid base64") from exc
            if not audio:
                raise validation_error("audio_b64 is empty")
            utterance = self.providers["asr"].transcribe(audio, audio_mime or "audio/wav")
            # Audio is never persisted, only transcribed in memory.
        elif isinstance(text, str):
            utterance = text
        else:
            raise validation_error("Provide text or audio_b64")
        utterance = utterance.strip()
        if not utterance:
            raise validation_error("Say something first.")

        command = commands.route(utterance)
        if command is not None:
            return self._run_command(senior, session_id, utterance, command)
        return self._chat_turn(senior, session_id, utterance)

    # -- commands ---------------------------------------------------------
    def _run_command(
        self,
        senior: dict[str, Any],
        session_id: str,
        utterance: str,
        command: dict[str, Any],
    ) -> dict[str, Any]:
        senior_id = int(senior["id"])
        texts = self._texts(senior)
        kind = command["type"]

        if kind == "stop":
            self.stop(session_id, senior_id)
            return {
                "turn_id": None,
                "transcript": utterance,
                "reply_text": "",
                "intent": "stop",
                "action": {"type": "stop"},
                "ask": None,
                "captions": [],
                "stopped": True,
            }

        if kind == "repeat":
            last = self.db.query_one(
                "SELECT text FROM turns WHERE session_id = ? AND role = 'anchor' "
                "ORDER BY id DESC LIMIT 1",
                (session_id,),
            )
            reply = last["text"] if last else texts["repeat_empty"]
            self._write_turn(session_id, "senior", utterance)
            anchor_turn = self._write_turn(session_id, "anchor", reply)
            return {
                "turn_id": anchor_turn,
                "transcript": utterance,
                "reply_text": reply,
                "intent": "repeat",
                "action": None,
                "ask": None,
                "captions": self.captions(session_id),
                "stopped": False,
            }

        if kind == "play":
            locale = self._locale(senior)
            item = self.activities.next_activity(senior_id)
            localised = self.activities.localise(item, locale)
            reply = texts["play"].format(title=localised["title"])
            self._write_turn(session_id, "senior", utterance)
            anchor_turn = self._write_turn(session_id, "anchor", reply)
            action = {
                "type": "activity",
                "activity_id": localised["id"],
                "activity": localised,
            }
            self._record_observation(senior, utterance, session_id)
            return {
                "turn_id": anchor_turn,
                "transcript": utterance,
                "reply_text": reply,
                "intent": "play",
                "action": action,
                "ask": None,
                "captions": self.captions(session_id),
                "stopped": False,
            }

        # kind == "call"
        contacts = self.db.query(
            "SELECT * FROM contacts WHERE senior_id = ? ORDER BY id", (senior_id,)
        )
        contact = commands.match_contact(contacts, command.get("target"))
        if contact is None:
            labels = [str(row["label"]) for row in contacts]
            reply = (
                texts["call_choose"].format(options=" / ".join(labels))
                if labels
                else texts["call_empty"]
            )
            self._write_turn(session_id, "senior", utterance)
            anchor_turn = self._write_turn(session_id, "anchor", reply)
            ask = {"kind": "clarify", "options": labels} if labels else None
            return {
                "turn_id": anchor_turn,
                "transcript": utterance,
                "reply_text": reply,
                "intent": "call",
                "action": None,
                "ask": ask,
                "captions": self.captions(session_id),
                "stopped": False,
            }
        now = iso_utc(self.clock.now())
        contact_action_id = self.db.insert(
            "INSERT INTO contact_actions(senior_id, actor_user_id, contact_id, phone, initiated_at) "
            "VALUES (?,?,?,?,?)",
            (senior_id, senior_id, int(contact["id"]), str(contact["phone"]), now),
        )
        audit.write(
            self.db,
            self.clock,
            senior_id,
            "call_initiated",
            "contact_action",
            contact_action_id,
        )
        reply = texts["call_confirm"].format(label=contact["label"])
        self._write_turn(session_id, "senior", utterance)
        anchor_turn = self._write_turn(session_id, "anchor", reply)
        action = {
            "type": "dial",
            "contact_action_id": contact_action_id,
            "contact_id": int(contact["id"]),
            "label": str(contact["label"]),
            "phone": str(contact["phone"]),
            "requires_confirmation": True,
        }
        return {
            "turn_id": anchor_turn,
            "transcript": utterance,
            "reply_text": reply,
            "intent": "call",
            "action": action,
            "ask": None,
            "captions": self.captions(session_id),
            "stopped": False,
        }

    # -- chat -------------------------------------------------------------
    def _chat_turn(self, senior: dict[str, Any], session_id: str, utterance: str) -> dict[str, Any]:
        senior_id = int(senior["id"])
        prefs = self.preferences.get_or_create(senior_id)
        locale = self._locale(senior)
        remembered = self.memories.retrieve(
            senior_id, utterance, json.loads(prefs["interests"] or "[]")
        )
        system = build_system_prompt(senior, prefs, remembered, locale=locale)
        history = self._history(session_id, utterance)
        max_words = 20 if prefs["short_replies"] else 40
        reply = self.providers["llm"].reply(system, history, max_words=max_words)
        if not is_clean(reply):
            reply = TEXT[locale]["safe_reply"]

        if self._cancelled(session_id):
            # A stop arrived while the model was thinking: discard late output.
            return {
                "turn_id": None,
                "transcript": utterance,
                "reply_text": "",
                "intent": "chat",
                "action": None,
                "ask": None,
                "captions": [],
                "stopped": True,
            }

        self._write_turn(session_id, "senior", utterance)
        anchor_turn = self._write_turn(session_id, "anchor", reply)
        self._record_observation(senior, utterance, session_id)
        return {
            "turn_id": anchor_turn,
            "transcript": utterance,
            "reply_text": reply,
            "intent": "chat",
            "action": None,
            "ask": None,
            "captions": self.captions(session_id),
            "stopped": False,
        }

    def _history(self, session_id: str, utterance: str) -> list[dict[str, str]]:
        rows = self.db.query(
            "SELECT role, text FROM turns WHERE session_id = ? ORDER BY id DESC LIMIT ?",
            (session_id, HISTORY_TURNS),
        )
        history = [
            {"role": "user" if row["role"] == "senior" else "assistant", "content": row["text"]}
            for row in reversed(rows)
        ]
        history.append({"role": "user", "content": utterance})
        return history

    # -- observations -----------------------------------------------------
    def _record_observation(self, senior: dict[str, Any], text: str, source_ref: str) -> bool:
        senior_id = int(senior["id"])
        if not self.consent.is_allowed(senior_id, "record_observations"):
            return False
        prefs = self.preferences.get_or_create(senior_id)
        topics = json.loads(prefs["observation_topics"] or "[]")
        topic = infer_topic(text)
        if topic not in topics:
            return False
        self.db.execute(
            "INSERT INTO observations(senior_id, topic, event_date, evidence, source_ref, "
            "consent_version, created_at) VALUES (?,?,?,?,?,?,?)",
            (
                senior_id,
                topic,
                local_date_str(self.clock, senior["timezone"]),
                text[:EVIDENCE_LIMIT],
                source_ref,
                self.consent.version(senior_id),
                iso_utc(self.clock.now()),
            ),
        )
        return True


TOPIC_KEYWORDS = (
    ("meals", ("吃", "饭", "菜", "喝", "meal", "food", "eat", "breakfast", "lunch", "dinner")),
    ("mood", ("心情", "高兴", "开心", "累", "难过", "烦", "mood", "happy", "sad", "tired")),
    ("activities", ("玩", "游戏", "下棋", "唱", "散步", "play", "game", "walk", "sing")),
)


def infer_topic(text: str) -> str:
    lowered = text.lower()
    for topic, keywords in TOPIC_KEYWORDS:
        if any(keyword in text or keyword in lowered for keyword in keywords):
            return topic
    return "participation"
