#!/usr/bin/env python3
"""پشتیبان روزانه با نگهداری ۷ نسخه — برای کرون.

  0 2 * * * /usr/bin/python3 ~/xennic-data/barghpa-26-iee1405/tools/backup_daily.py

پشتیبان با API خود SQLite گرفته می‌شود (نه cp) تا فایل باز سالم بماند.
پس از نوشتن، پشتیبان باز و integrity_check می‌شود؛ عدد شرکت هم گزارش می‌شود.
"""
from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

import bgdb


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(Path.home() / "xennic-data" / "barghpa-26-iee1405"
                                        / "db" / "barghpa_iee1405.sqlite"))
    ap.add_argument("--backup-dir", default=str(Path.home() / "xennic-data"
                                                / "barghpa-26-iee1405" / "backups"))
    ap.add_argument("--keep", type=int, default=7)
    args = ap.parse_args()

    db = Path(args.db).expanduser()
    bdir = Path(args.backup_dir).expanduser()
    if not db.exists():
        print(f"❌ پایگاه نیست: {db}", file=sys.stderr)
        return 1

    con = bgdb.connect(db, readonly=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
    out = bgdb.backup(con, bdir / f"daily-{stamp}.sqlite")
    ok = con.execute("PRAGMA integrity_check").fetchone()[0]
    con.close()

    chk = bgdb.connect(out, readonly=True)
    restored = chk.execute("PRAGMA integrity_check").fetchone()[0]
    n = chk.execute("SELECT count(*) FROM company").fetchone()[0]
    chk.close()

    dailies = sorted(bdir.glob("daily-*.sqlite"), key=lambda p: p.stem)
    removed = 0
    for old in (dailies[:-args.keep] if args.keep > 0 else []):
        old.unlink()
        removed += 1

    print(f"پشتیبان: {out} ({n} شرکت، integrity={restored}) · حذف‌شده: {removed} "
          f"· نگه‌داشته: {min(len(dailies), args.keep)}")
    return 0 if ok == "ok" and restored == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
