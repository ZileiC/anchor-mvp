"""SQLite access: one connection per process, serialized writes, migration runner."""
from __future__ import annotations

import contextlib
import sqlite3
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Iterator, Optional, Union

from .paths import migrations_dir

# Kept for callers that import it, but the runner resolves at call time so a
# frozen bundle reads <sys._MEIPASS>/migrations (see app/paths.py).
MIGRATIONS_DIR = migrations_dir()

Params = Union[Iterable[Any], dict[str, Any]]


class Database:
    def __init__(self, path: str | Path) -> None:
        self.path = str(path)
        if self.path != ":memory:":
            Path(self.path).expanduser().parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(self.path, check_same_thread=False, isolation_level=None)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA foreign_keys = ON")
        if self.path != ":memory:":
            self.conn.execute("PRAGMA journal_mode = WAL")
        self._lock = threading.RLock()

    # -- schema ---------------------------------------------------------
    def migrate(self) -> list[str]:
        """Apply pending migrations; returns the names applied this call."""
        applied_now: list[str] = []
        with self._lock:
            self.conn.execute(
                "CREATE TABLE IF NOT EXISTS schema_migrations ("
                "name TEXT PRIMARY KEY, applied_at TEXT NOT NULL)"
            )
            done = {
                row["name"]
                for row in self.conn.execute("SELECT name FROM schema_migrations").fetchall()
            }
            for sql_file in sorted(migrations_dir().glob("*.sql")):
                if sql_file.name in done:
                    continue
                self.conn.executescript(sql_file.read_text(encoding="utf-8"))
                self.conn.execute(
                    "INSERT INTO schema_migrations(name, applied_at) VALUES (?, ?)",
                    (sql_file.name, datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")),
                )
                applied_now.append(sql_file.name)
        return applied_now

    # -- queries --------------------------------------------------------
    def execute(self, sql: str, params: Params = ()) -> sqlite3.Cursor:
        with self._lock:
            return self.conn.execute(sql, params)

    def insert(self, sql: str, params: Params = ()) -> int:
        with self._lock:
            cursor = self.conn.execute(sql, params)
            return int(cursor.lastrowid or 0)

    def executemany(self, sql: str, rows: Iterable[Iterable[Any]]) -> None:
        with self._lock:
            self.conn.executemany(sql, [tuple(row) for row in rows])

    def query(self, sql: str, params: Params = ()) -> list[dict[str, Any]]:
        with self._lock:
            rows = self.conn.execute(sql, params).fetchall()
        return [dict(row) for row in rows]

    # Alias kept for readability in newer modules.
    query_all = query

    def query_one(self, sql: str, params: Params = ()) -> Optional[dict[str, Any]]:
        with self._lock:
            row = self.conn.execute(sql, params).fetchone()
        return dict(row) if row is not None else None

    def scalar(self, sql: str, params: Params = (), default: Any = None) -> Any:
        row = self.query_one(sql, params)
        if not row:
            return default
        return next(iter(row.values()))

    @contextlib.contextmanager
    def tx(self) -> Iterator[sqlite3.Connection]:
        with self._lock:
            self.conn.execute("BEGIN IMMEDIATE")
            try:
                yield self.conn
            except BaseException:
                self.conn.execute("ROLLBACK")
                raise
            else:
                self.conn.execute("COMMIT")

    def close(self) -> None:
        with self._lock:
            self.conn.close()


def open_database(path: str | Path) -> Database:
    db = Database(path)
    db.migrate()
    return db
