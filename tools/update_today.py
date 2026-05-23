#!/usr/bin/env python3
"""Generate today.json for iPhone Shortcuts from alarms.json.

The iPhone shortcut stays simple: it downloads today.json, reads items,
and creates system alarms. Date selection happens here, not on the iPhone.
"""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
ALARMS_PATH = ROOT / "alarms.json"
TODAY_PATH = ROOT / "today.json"
TZ = ZoneInfo("Europe/Prague")


def item_sort_key(item: dict) -> str:
    return str(item.get("alarmTime") or item.get("start") or "99:99")


def main() -> None:
    now = datetime.now(TZ)
    today = now.date().isoformat()
    current_time = now.strftime("%H:%M")

    source = json.loads(ALARMS_PATH.read_text(encoding="utf-8"))

    if isinstance(source.get("days"), dict):
        items = list(source["days"].get(today, []))
    else:
        items = [item for item in source.get("items", []) if item.get("date") == today]

    # If the file is regenerated later during the day, keep only alarms that have not passed yet.
    items = [item for item in items if str(item.get("alarmTime", "99:99")) >= current_time]
    items.sort(key=item_sort_key)

    output = {
        "schemaVersion": 1,
        "source": "lazensky-commander-today",
        "generatedAt": now.isoformat(timespec="seconds"),
        "date": today,
        "timezone": "Europe/Prague",
        "prefix": source.get("prefix", "LK:"),
        "items": items,
    }

    TODAY_PATH.write_text(
        json.dumps(output, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
