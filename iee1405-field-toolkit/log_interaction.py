#!/usr/bin/env python3
"""ثبت و ادغام تعامل‌های میدانی — محلی، بدون همگام‌سازی چنددستگاهی.

  python3 log_interaction.py --db … --company "شرکت نمونه" --kind visit \\
      --outcome interested --next "ارسال کاتالوگ" --due 2026-11-12
  python3 log_interaction.py --db … --import ~/Downloads/interactions-*.json
  python3 log_interaction.py --db … --export ../exports/interactions.csv
  python3 log_interaction.py --db … --due          # اقدام‌های سررسیده

ادغام: کلید uid، پس وارد کردن دوبارهٔ همان فایل ردیف تکراری نمی‌سازد.
نام شرکت با name_norm یا company_alias تطبیق داده می‌شود؛ اگر پیدا نشد،
ردیف در «نامشخص» گزارش می‌شود و نوشته نمی‌شود (هیچ شرکتی حدس زده نمی‌شود).
"""
from __future__ import annotations

import argparse
import csv
import json
import sqlite3
import sys
from datetime import date, datetime, timezone
from pathlib import Path

import bgdb


def find_company(con: sqlite3.Connection, ref: str, name: str | None = None):
    if ref and ref.isdigit():
        r = con.execute("SELECT id, name_fa FROM company WHERE id=?", (int(ref),)).fetchone()
        if r:
            return r
    for cand in filter(None, [name, ref]):
        nm = bgdb.norm_text(cand)
        if not nm:
            continue
        r = con.execute("SELECT id, name_fa FROM company WHERE name_norm=?", (nm,)).fetchone()
        if r:
            return r
        r = con.execute("""SELECT c.id, c.name_fa FROM company_alias a
                             JOIN company c ON c.id=a.company_id
                            WHERE a.alias_norm=?""", (nm,)).fetchone()
        if r:
            return r
    return None


def insert(con: sqlite3.Connection, company_id: int, kind: str, outcome: str | None,
           next_action: str | None, next_due: str | None, note: str | None,
           at_utc: str | None, device: str | None, uid: str | None) -> bool:
    at_utc = at_utc or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    uid = uid or f"local-{company_id}-{at_utc}"
    try:
        con.execute("""INSERT INTO visit_interaction
            (company_id, at_utc, kind, outcome, next_action, next_due_on, note, device, uid)
            VALUES (?,?,?,?,?,?,?,?,?)""",
            (company_id, at_utc, kind, outcome, next_action, next_due, note, device, uid))
        return True
    except sqlite3.IntegrityError:
        return False


def import_file(con: sqlite3.Connection, path: Path) -> dict:
    """پذیرش JSON (خروجی HTML) یا CSV."""
    text = path.read_text(encoding="utf-8-sig").strip()
    recs = []
    if text.startswith("["):
        recs = json.loads(text)
    elif text.startswith("{"):
        recs = [json.loads(l) for l in text.splitlines() if l.strip()]
    else:
        recs = list(csv.DictReader(text.splitlines()))

    stats = {"total": len(recs), "inserted": 0, "duplicate": 0, "unmatched": []}
    for r in recs:
        c = find_company(con, str(r.get("company") or r.get("company_id") or ""),
                         r.get("company_name"))
        if not c:
            stats["unmatched"].append(r.get("company_name") or r.get("company"))
            continue
        ok = insert(con, c["id"], (r.get("kind") or "note").strip(),
                    r.get("outcome"), r.get("next_action"), r.get("next_due"),
                    r.get("note"), r.get("at_utc"), r.get("device"), r.get("uid"))
        stats["inserted" if ok else "duplicate"] += 1
    con.commit()
    return stats


def export_csv(con: sqlite3.Connection, path: Path) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = con.execute("""SELECT vi.uid, c.name_fa, vi.at_utc, vi.kind, vi.outcome,
                                 vi.next_action, vi.next_due_on, vi.note
                            FROM visit_interaction vi JOIN company c ON c.id=vi.company_id
                           ORDER BY vi.at_utc""").fetchall()
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["uid", "company", "at_utc", "kind", "outcome",
                    "next_action", "next_due", "note"])
        for r in rows:
            w.writerow([r["uid"], r["name_fa"], r["at_utc"], r["kind"], r["outcome"],
                        r["next_action"], r["next_due_on"], r["note"]])
    return len(rows)


def due_list(con: sqlite3.Connection, on: str | None = None):
    on = on or date.today().isoformat()
    return con.execute("""SELECT c.name_fa, v.halls, vi.next_action, vi.next_due_on
                            FROM visit_interaction vi JOIN company c ON c.id=vi.company_id
                            LEFT JOIN v_company_card v ON v.company_id=c.id
                           WHERE vi.next_due_on IS NOT NULL AND vi.next_due_on <= ?
                             AND vi.id IN (SELECT max(id) FROM visit_interaction
                                            GROUP BY company_id)
                           ORDER BY vi.next_due_on""", (on,)).fetchall()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(Path.home() / "xennic-data" / "barghpa-26-iee1405"
                                        / "db" / "barghpa_iee1405.sqlite"))
    ap.add_argument("--company")
    ap.add_argument("--kind", default="visit")
    ap.add_argument("--outcome")
    ap.add_argument("--next")
    ap.add_argument("--due")
    ap.add_argument("--note")
    ap.add_argument("--import", dest="import_path")
    ap.add_argument("--export")
    ap.add_argument("--due-list", action="store_true")
    ap.add_argument("--due-on", help="تاریخ مرجع فهرست سررسید (پیش‌فرض: امروز)")
    args = ap.parse_args()

    con = bgdb.connect(Path(args.db).expanduser())
    bgdb.migrate(con)

    if args.import_path:
        st = import_file(con, Path(args.import_path).expanduser())
        print(f"وارد شد: {st['inserted']} جدید · {st['duplicate']} تکراری · "
              f"{len(st['unmatched'])} نامشخص از {st['total']}")
        for u in st["unmatched"][:10]:
            print(f"  ❓ تطبیق نشد: {u}")
        return 0
    if args.export:
        n = export_csv(con, Path(args.export).expanduser())
        print(f"{n} تعامل در {args.export}")
        return 0
    if args.due_list:
        rows = due_list(con, args.due_on)
        print(f"اقدام‌های سررسیده: {len(rows)}")
        for r in rows:
            print(f"  {r['next_due_on']} · {r['name_fa']} · {r['halls'] or '—'} · {r['next_action']}")
        return 0
    if not args.company:
        ap.error("یکی از --company / --import / --export / --due-list لازم است")

    c = find_company(con, args.company)
    if not c:
        print(f"❌ شرکت پیدا نشد: {args.company}", file=sys.stderr)
        return 1
    ok = insert(con, c["id"], args.kind, args.outcome, args.next, args.due,
                args.note, None, "cli", None)
    con.commit()
    print(("✅ ثبت شد" if ok else "ℹ️ تکراری بود") + f": {c['name_fa']} · {args.kind}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
