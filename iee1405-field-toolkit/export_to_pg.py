#!/usr/bin/env python3
"""صدور پایگاه SQLite به SQL قابل اجرا روی PostgreSQL — تا ربات بله شرکت‌ها را بخواند.

  python3 export_to_pg.py --out ../exports/barghpa_load.sql
  python3 export_to_pg.py --out /tmp/x.sql --limit 20     # نمونهٔ کوچک برای آزمون
  python3 export_to_pg.py --out /tmp/x.sql --prune        # ردیف‌های حذف‌شده هم پاک شوند

چرا SQL و نه اتصال مستقیم: نصب `psycopg2` روی سرور لازم نیست و اجرا با همان
`psql` داخل کانتینر انجام می‌شود. خروجی یک فایل متن است، پس قابل بازبینی،
قابل diff و قابل نگه‌داشتن در پشتیبان.

قاعده‌ها (همه صریح):
  • شناسهٔ شرکت همان `id` پایگاه SQLite است تا ارجاع پایدار بماند.
  • هر INSERT با `ON CONFLICT … DO UPDATE` است: اجرای دوباره ردیف تکراری نمی‌سازد.
  • `verified` هرگز ساخته نمی‌شود؛ فقط همان مقدار پایگاه مبدأ منتقل می‌شود.
  • سطح اطمینان (`provenance_class` / `confidence`) عیناً منتقل می‌شود؛
    چیزی «تأییدشده» نمی‌شود مگر در مبدأ تأیید شده باشد.
  • ستون‌های متنی از `'` و نویسه‌های کنترلی پاک می‌شوند؛ نیم‌فاصله (U+200C)
    دست‌نخورده می‌ماند چون بخشی از نام شرکت است.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
import sys
from pathlib import Path

TOOL_VERSION = "v0.9"
CHUNK = 200                      # چند ردیف در هر INSERT (سرعت و خوانایی فایل)


# ── ابزار متن ────────────────────────────────────────────────────────────
def esc(v) -> str:
    """مقدار پایتون → لیترال امن PostgreSQL.

    `standard_conforming_strings` پیش‌فرض روشن است، پس بک‌اسلش نویسهٔ معمولی
    است و تنها کاری که لازم است، تکرار `'` است.
    """
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    s = str(v)
    # اول خط تازه و تب به فاصله تبدیل می‌شوند، بعد نویسه‌های کنترلی حذف.
    # ترتیب مهم است: اگر اول حذف شوند، «گیومه» و واژهٔ بعدی به هم می‌چسبند و
    # متنِ منبع بی‌صدا تغییر می‌کند — همان دسته اشتباهی که نیم‌فاصله را خراب می‌کرد.
    s = s.replace("\r\n", "\n").replace("\r", "\n").replace("\n", " ")
    s = s.replace("\t", " ")
    # نویسه‌های کنترلی (به‌جز نیم‌فاصله که بخشی از نام است) حذف می‌شوند
    s = "".join(ch for ch in s if ch == "\u200c" or (ord(ch) >= 32 and ch != "\x7f"))
    s = s.replace("'", "''")
    return "'" + s + "'"


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def rows_of(con: sqlite3.Connection, sql: str, params=()):
    con.row_factory = sqlite3.Row
    return con.execute(sql, params).fetchall()


# ── بخش‌های خروجی ────────────────────────────────────────────────────────
def q_company(rows, prune: bool) -> list[str]:
    out = []
    for i in range(0, len(rows), CHUNK):
        part = rows[i:i + CHUNK]
        out.append(
            "INSERT INTO barghpa.company\n"
            "  (id, name_fa, name_norm, name_en, slug, website, about_fa, province_label,\n"
            "   provenance_class, official_site, google_search, verified, source_row)\n"
            "VALUES\n" + ",\n".join(
                "  (" + ", ".join([
                    esc(r["id"]), esc(r["name_fa"]),
                    # ستون‌های NOT NULL نباید NULL بمانند، وگرنه کل تراکنش برمی‌گردد
                    esc(r["name_norm"] or r["name_fa"]), esc(r["name_en"]),
                    esc(r["slug"]), esc(r["website"]), esc(r["about_fa"]),
                    esc(r["province_label"]), esc(r["provenance_class"] or "unknown"),
                    esc(r["official_site"]), esc(r["google_search"]),
                    esc(int(r["verified"] or 0) == 1), esc(r["source_row"]),
                ]) + ")" for r in part) +
            "\nON CONFLICT (id) DO UPDATE SET\n"
            "  name_fa = EXCLUDED.name_fa, name_norm = EXCLUDED.name_norm,\n"
            "  name_en = EXCLUDED.name_en, slug = EXCLUDED.slug, website = EXCLUDED.website,\n"
            "  about_fa = EXCLUDED.about_fa, province_label = EXCLUDED.province_label,\n"
            "  provenance_class = EXCLUDED.provenance_class,\n"
            "  official_site = EXCLUDED.official_site, google_search = EXCLUDED.google_search,\n"
            "  verified = EXCLUDED.verified OR barghpa.company.verified,\n"
            "  source_row = EXCLUDED.source_row;")
    if prune:
        # فرزندان با ON DELETE CASCADE می‌روند؛ اینجا فقط ریشه پاک می‌شود
        kids = ",".join(str(int(r["id"])) for r in rows) or "NULL"
        out.append(f"DELETE FROM barghpa.company WHERE id NOT IN ({kids});")
    return out


def q_participation(rows) -> list[str]:
    out = []
    for i in range(0, len(rows), CHUNK):
        part = rows[i:i + CHUNK]
        out.append(
            "INSERT INTO barghpa.participation\n"
            "  (company_id, hall, booth, booth_raw, priority, priority_reason)\n"
            "VALUES\n" + ",\n".join(
                "  (" + ", ".join([
                    esc(r["company_id"]), esc(r["hall"]), esc(r["booth"]),
                    esc(r["booth_raw"]), esc(r["priority"]), esc(r["priority_reason"]),
                ]) + ")" for r in part) +
            "\nON CONFLICT (company_id, hall) DO UPDATE SET\n"
            "  booth = EXCLUDED.booth, booth_raw = EXCLUDED.booth_raw,\n"
            "  priority = EXCLUDED.priority, priority_reason = EXCLUDED.priority_reason;")
    return out


def q_contact(rows) -> list[str]:
    out = []
    for i in range(0, len(rows), CHUNK):
        part = rows[i:i + CHUNK]
        out.append(
            "INSERT INTO barghpa.contact\n"
            "  (company_id, channel, value, value_norm, confidence, is_primary, verified)\n"
            "VALUES\n" + ",\n".join(
                "  (" + ", ".join([
                    esc(r["company_id"]), esc(r["channel"]), esc(r["value"]),
                    esc(r["value_norm"]), esc(r["confidence"] or "unknown"),
                    esc(int(r["is_primary"] or 0) == 1),
                    esc(int(r["verified"] or 0) == 1),
                ]) + ")" for r in part) +
            "\nON CONFLICT (company_id, channel, value_norm) DO UPDATE SET\n"
            "  value = EXCLUDED.value, confidence = EXCLUDED.confidence,\n"
            "  is_primary = EXCLUDED.is_primary,\n"
            "  verified = EXCLUDED.verified OR barghpa.contact.verified;")
    return out


def q_flag(rows) -> list[str]:
    out = []
    for i in range(0, len(rows), CHUNK):
        part = rows[i:i + CHUNK]
        out.append(
            "INSERT INTO barghpa.company_flag (company_id, flag, value)\nVALUES\n" +
            ",\n".join("  (" + ", ".join([
                esc(r["company_id"]), esc(r["flag"]), esc(r["value"])]) + ")"
                for r in part) +
            "\nON CONFLICT (company_id, flag) DO UPDATE SET value = EXCLUDED.value;")
    return out


def q_pilot(rows) -> list[str]:
    out = ["DELETE FROM barghpa.pilot;"]
    if rows:
        out.append(
            "INSERT INTO barghpa.pilot\n"
            "  (rank, company_id, reason, first_check, approved, approved_by, approved_at)\n"
            "VALUES\n" + ",\n".join(
                "  (" + ", ".join([
                    esc(r["rank"]), esc(r["company_id"]), esc(r["reason"]),
                    esc(r["first_check"]), esc(int(r["approved"] or 0) == 1),
                    esc(r["approved_by"]), esc(r["approved_at"]),
                ]) + ")" for r in rows) +
            "\nON CONFLICT (rank) DO UPDATE SET\n"
            "  company_id = EXCLUDED.company_id, reason = EXCLUDED.reason,\n"
            "  first_check = EXCLUDED.first_check, approved = EXCLUDED.approved,\n"
            "  approved_by = EXCLUDED.approved_by, approved_at = EXCLUDED.approved_at;")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(Path.home() / "xennic-data" / "barghpa-26-iee1405"
                                        / "db" / "barghpa_iee1405.sqlite"))
    ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int, default=0, help="فقط N شرکت اول (برای آزمون)")
    ap.add_argument("--prune", action="store_true",
                    help="ردیف‌هایی که در مبدأ نیستند هم در مقصد پاک شوند")
    ap.add_argument("--manifest", help="نوشتن خلاصه در فایل JSON")
    args = ap.parse_args()

    db = Path(args.db).expanduser()
    if not db.exists():
        print(f"❌ پایگاه پیدا نشد: {db}", file=sys.stderr)
        return 1

    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    lim = f" LIMIT {int(args.limit)}" if args.limit else ""

    companies = rows_of(con, f"""
        SELECT c.id, c.name_fa, c.name_norm, c.name_en, c.slug, c.website, c.about_fa,
               c.province_label, c.verified, c.source_row,
               c.provenance_class, c.official_site, c.google_search
          FROM company c ORDER BY c.id{lim}""")
    ids = {r["id"] for r in companies}
    ph = ",".join("?" * len(ids)) or "NULL"

    participations = rows_of(con, f"""
        SELECT p.company_id, coalesce(h.code, '—') AS hall, p.booth, p.booth_raw,
               p.priority, p.priority_reason
          FROM participation p LEFT JOIN hall h ON h.id = p.hall_id
         WHERE p.company_id IN ({ph})
         ORDER BY p.company_id, hall""", tuple(ids))
    contacts = rows_of(con, f"""
        SELECT company_id, channel, value, value_norm, confidence, is_primary, verified
          FROM contact WHERE company_id IN ({ph})
         ORDER BY company_id, channel, value_norm""", tuple(ids))
    flags = rows_of(con, f"""
        SELECT company_id, flag, value FROM company_flag
         WHERE company_id IN ({ph}) ORDER BY company_id, flag""", tuple(ids))
    if args.limit:
        pilot = rows_of(con, f"""
            SELECT rank, company_id, reason, first_check, approved, approved_by, approved_at
              FROM visit_pilot WHERE company_id IN ({ph}) ORDER BY rank""", tuple(ids))
    else:
        pilot = rows_of(con, """
            SELECT rank, company_id, reason, first_check, approved, approved_by, approved_at
              FROM visit_pilot ORDER BY rank""")
    con.close()

    src_sha = sha256_file(db)
    head = [
        "-- barghpa → PostgreSQL: آینهٔ فهرست نمایشگاه",
        f"-- تولیدشده با export_to_pg.py {TOOL_VERSION} از {db.name}",
        f"-- SHA-256 پایگاه مبدأ: {src_sha}",
        f"-- {len(companies)} شرکت · {len(contacts)} تماس · "
        f"{len(participations)} مشارکت · {len(flags)} پرچم · {len(pilot)} نامزد پایلوت",
        "-- این فایل چیزی را «تأییدشده» نمی‌کند؛ سطح اطمینان مبدأ را منتقل می‌کند.",
        "BEGIN;",
        "SET LOCAL statement_timeout = '180s';",
        "INSERT INTO barghpa.load_batch\n"
        "  (source_file, source_sha256, companies, contacts, participations, flags,\n"
        "   pilot_rows, tool_version)\n"
        f"VALUES ({esc(db.name)}, {esc(src_sha)}, {len(companies)}, {len(contacts)},\n"
        f"        {len(participations)}, {len(flags)}, {len(pilot)}, {esc(TOOL_VERSION)});",
    ]
    body = (q_company(companies, args.prune) + q_participation(participations)
            + q_contact(contacts) + q_flag(flags) + q_pilot(pilot))
    text = "\n".join(head) + "\n\n" + "\n\n".join(body) + "\n\nCOMMIT;\n"

    out = Path(args.out).expanduser()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8")

    manifest = {
        "source": str(db), "source_sha256": src_sha, "out": str(out),
        "out_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        "companies": len(companies), "contacts": len(contacts),
        "participations": len(participations), "flags": len(flags),
        "pilot": len(pilot), "prune": args.prune, "tool": TOOL_VERSION,
        "verified_companies": sum(1 for r in companies if int(r["verified"] or 0) == 1),
        "verified_contacts": sum(1 for r in contacts if int(r["verified"] or 0) == 1),
        "statements": len(body), "bytes": len(text.encode("utf-8")),
    }
    if args.manifest:
        mp = Path(args.manifest).expanduser()
        mp.parent.mkdir(parents=True, exist_ok=True)
        mp.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"✅ ساخته شد: {out}")
    print(f"   {len(companies)} شرکت · {len(contacts)} تماس · "
          f"{len(participations)} مشارکت · {len(flags)} پرچم · {len(pilot)} پایلوت")
    print(f"   {len(body)} دستور · {manifest['bytes']:,} بایت")
    already = sum(1 for r in companies if int(r["verified"] or 0) == 1)
    print(f"   verified در مبدأ: {already} از {len(companies)} "
          f"(باقی تأییدنشده می‌مانند؛ این فایل چیزی را تأیید نمی‌کند)")
    if already:
        print("   ⚠️ ردیف verified=1 هست: مطمئن شوید شاهدش در `contact_evidence` است.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
