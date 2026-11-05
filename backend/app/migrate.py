"""Create/upgrade the SQLite database: python -m app.migrate"""
from __future__ import annotations

from .config import Settings
from .db import Database


def main() -> None:
    settings = Settings.from_env()
    database = Database(settings.db_path)
    applied = database.migrate()
    print(f"database: {settings.db_path}")
    print("applied: " + ", ".join(applied))


if __name__ == "__main__":
    main()
