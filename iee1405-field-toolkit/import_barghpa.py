#!/usr/bin/env python3
"""ورود فهرست غرفه‌داران به SQLite — تکرارپذیر، با شاهد برای هر مقدار.

  python3 import_barghpa.py --db ../db/barghpa_iee1405.sqlite --dry-run
  python3 import_barghpa.py --db ../db/barghpa_iee1405.sqlite --write

تضمین‌ها:
  * اجرای دوباره ردیف تکراری نمی‌سازد (کلید یکتا روی name_norm و value_norm).
  * یادداشت دستی (`company.notes`) و مقادیر دستی بازنویسی نمی‌شوند.
  * هر مقدار تماس یک ردیف contact_evidence با منبع و تاریخ دارد.
  * شمارهٔ غرفه ساخته نمی‌شود؛ منبع چنین ستونی ندارد.
  * پیش از نوشتن، پشتیبان با API خود SQLite گرفته می‌شود.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import re
import sys
from datetime import date, datetime, timezone
from pathlib import Path

import bgdb

CHANNEL_ORDER = ["email", "phone", "mobile", "whatsapp", "instagram",
                 "telegram", "linkedin", "website", "address"]
# کدام ستون‌ها به contact می‌روند (website/address هم یک کانال‌اند)
CONTACT_COLS = ["email", "phone", "mobile", "whatsapp", "instagram",
                "telegram", "linkedin", "website", "address"]
SPLITTABLE = {"email", "phone", "mobile", "whatsapp", "instagram", "telegram", "linkedin"}
MAIN_SHEET = "شرکت‌کنندگان.csv"
PART_SHEET = "فهرست_کامل_۳۰۰_رکورد.csv"

ALIASES = {
    "name": ["نام شرکت", "نام فارسی", "نام", "company", "name"],
    "name_en": ["نام لاتین", "نام انگلیسی", "english", "name_en"],
    "slug": ["slug", "اسلاگ"],
    "hall": ["سالن", "hall"],
    "booth": ["غرفه", "شماره غرفه", "booth", "stand"],
    "type": ["نوع فعالیت", "فعالیت", "دسته"],
    "province": ["استان", "province"],
    "website": ["وب‌سایت", "وب سایت", "سایت", "website", "url"],
    "email": ["ایمیل", "پست الکترونیک", "email"],
    "phone": ["تلفن ثابت", "تلفن", "phone", "tel"],
    "mobile": ["موبایل", "همراه", "mobile"],
    "whatsapp": ["واتساپ", "whatsapp"],
    "instagram": ["اینستاگرام", "instagram"],
    "telegram": ["تلگرام", "telegram"],
    "linkedin": ["لینکدین", "linkedin"],
    "address": ["آدرس", "نشانی", "address"],
    "status": ["وضعیت اطلاعات", "وضعیت"],
    "about": ["درباره", "توضیح", "معرفی", "about"],
    "tavanir": ["در فهرست توانیر", "توانیر"],
    "daneshbonyan": ["دانش‌بنیان", "دانش بنیان"],
}


def detect(headers: list[str]) -> dict[str, int]:
    mp, used = {}, set()
    for field, keys in ALIASES.items():
        for i, h in enumerate(headers):
            if i in used:
                continue
            if bgdb.norm_text(h) in {bgdb.norm_text(k) for k in keys}:
                mp[field] = i
                used.add(i)
                break
        else:
            for i, h in enumerate(headers):
                if i in used:
                    continue
                hn = bgdb.norm_text(h)
                if any(bgdb.norm_text(k) in hn for k in keys if len(bgdb.norm_text(k)) >= 4):
                    mp[field] = i
                    used.add(i)
                    break
    return mp


def read_csv(path: Path) -> tuple[list[str], list[list[str]]]:
    text = path.read_bytes().decode("utf-8-sig")
    rows = [r for r in csv.reader(text.splitlines()) if any((c or "").strip() for c in r)]
    return (rows[0] if rows else []), (rows[1:] if rows else [])


def split_cell(cell: str, field: str) -> list[str]:
    cell = (cell or "").strip()
    if not cell or cell in {"—", "-", "–"}:
        return []
    if field not in SPLITTABLE:
        return [cell]
    parts = re.split(r"\s*[,،;؛]\s*|\s{2,}|\s*/\s*", cell)
    return [p.strip() for p in parts if p.strip() and p.strip() not in {"—", "-", "–"}]


def clean_value(field: str, raw: str) -> str:
    v = (raw or "").strip()
    if field == "email":
        return bgdb.norm_email(v)
    if field == "website":
        v = re.sub(r"^//", "", v)
        return v if re.match(r"^(https?://|www\.)", v, re.I) else (
            f"https://{v}" if "." in v else v)
    return v


def value_norm(field: str, v: str) -> str:
    if field in {"phone", "mobile", "whatsapp"}:
        return bgdb.norm_phone(v)
    if field == "email":
        return bgdb.norm_email(v)
    if field == "website":
        return bgdb.norm_url(v)
    if field in {"instagram", "telegram"}:
        return bgdb.norm_text(v).lstrip("@")
    if field == "linkedin":
        return bgdb.norm_url(v)
    return bgdb.norm_text(v)


def trueish(v: str) -> bool:
    return bgdb.norm_text(v) in {"1", "true", "بله", "دارد", "yes", "y"}


def score(ch: dict[str, int], flags: dict[str, bool]) -> tuple[int, str]:
    """اولویت پیشنهادی با دلیل صریح — هیچ عاملی از غرفه ساخته نمی‌شود."""
    p, why = 0, []
    if ch.get("email") or ch.get("phone") or ch.get("mobile"):
        p += 30
        why.append("راه ارتباطی مستقیم دارد (+30)")
    if flags.get("tavanir_vendor"):
        p += 20
        why.append("در فهرست تأمین‌کنندگان توانیر (+20)")
    if flags.get("daneshbonyan"):
        p += 15
        why.append("دانش‌بنیان (+15)")
    if ch.get("website"):
        p += 10
        why.append("وب‌سایت رسمی (+10)")
    if ch.get("whatsapp") or ch.get("instagram") or ch.get("telegram") or ch.get("linkedin"):
        p += 5
        why.append("شبکهٔ اجتماعی (+5)")
    if not why:
        why.append("هیچ دادهٔ تماسی در منبع نبود — نیازمند تکمیل (+0)")
    return min(p, 100), "؛ ".join(why)


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def find_sheet(src: Path) -> Path:
    for cand in (src / "csv" / MAIN_SHEET, src / MAIN_SHEET,
                 src / "barghpa-26th-electricity-exhibition-companies.csv"):
        if cand.exists():
            return cand
    raise SystemExit(f"شیت اصلی پیدا نشد در {src}")


def run(src: Path, db: Path, *, write: bool, captured_on: str,
        exhibition_code: str, backup_dir: Path | None) -> dict:
    sheet = find_sheet(src)
    headers, body = read_csv(sheet)
    mp = detect(headers)
    if "name" not in mp:
        raise SystemExit(f"ستون نام شناسایی نشد؛ سرستون‌ها: {headers}")

    part_sheet = src / "csv" / PART_SHEET if (src / "csv" / PART_SHEET).exists() else None
    halls_by_company: dict[str, list[str]] = {}
    if part_sheet:
        ph, pb = read_csv(part_sheet)
        pmp = detect(ph)
        if "name" in pmp and "hall" in pmp:
            for r in pb:
                nm = bgdb.norm_text(r[pmp["name"]] if pmp["name"] < len(r) else "")
                hl = (r[pmp["hall"]] if pmp["hall"] < len(r) else "").strip()
                if nm and hl:
                    halls_by_company.setdefault(nm, [])
                    if hl not in halls_by_company[nm]:
                        halls_by_company[nm].append(hl)

    stats = {"rows": 0, "companies_new": 0, "companies_existing": 0,
             "contacts_new": 0, "contacts_existing": 0, "flags": 0,
             "participations_new": 0, "participations_existing": 0,
             "skipped_empty_name": 0, "booth_found": 0, "halls": set()}

    con = bgdb.connect(db) if write else None
    if con:
        bgdb.migrate(con)
        if backup_dir:
            stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
            bgdb.backup(con, backup_dir / f"barghpa_iee1405.{stamp}.pre-import.sqlite")
        ex_id = bgdb.get_or_create(
            con, "exhibition", {"code": exhibition_code},
            {"title_fa": "بیست‌وششمین نمایشگاه بین‌المللی صنعت برق ایران",
             "starts_on": "2026-11-07", "ends_on": "2026-11-10",
             "venue": None,
             "source_url": "https://barghpa.com/exhibition/26th-iran-international-electricity-exhibition"})
        src_id = bgdb.get_or_create(
            con, "source", {"kind": "csv", "path": str(sheet), "sha256": sha256_file(sheet)},
            {"captured_on": captured_on,
             "note": f"ساخته‌شده با xlsx2csv_stdlib.py · {len(body)} ردیف"})
    else:
        ex_id = src_id = None

    seen_companies = set()
    for idx, row in enumerate(body, start=2):
        def cell(f):
            i = mp.get(f)
            return (row[i] if i is not None and i < len(row) else "").strip()

        name = cell("name")
        if not name:
            stats["skipped_empty_name"] += 1
            continue
        stats["rows"] += 1
        nm = bgdb.norm_text(name)
        if nm in seen_companies:
            stats["companies_existing"] += 1
        else:
            seen_companies.add(nm)

        chans = {}
        for f in CONTACT_COLS:
            i = mp.get(f)
            if i is None:
                continue
            vals = []
            for raw in split_cell(row[i] if i < len(row) else "", f):
                v = clean_value(f, raw)
                vn = value_norm(f, v)
                if v and vn:
                    vals.append((v, vn))
            if vals:
                chans[f] = vals
        flags = {k: trueish(cell(k)) for k in ("tavanir", "daneshbonyan")}
        flag_names = {"tavanir_vendor": flags["tavanir"], "daneshbonyan": flags["daneshbonyan"]}
        prio, why = score({k: 1 for k in chans}, flag_names)
        if cell("booth"):
            stats["booth_found"] += 1

        halls = halls_by_company.get(nm) or ([cell("hall")] if cell("hall") else [])
        stats["halls"].update(halls)

        if not write:
            continue

        # ── شرکت ────────────────────────────────────────────────────
        row_ex = con.execute("SELECT id FROM company WHERE name_norm=?", (nm,)).fetchone()
        if row_ex:
            cid = row_ex["id"]
            stats["companies_existing"] += 0
            con.execute("""UPDATE company SET
                             name_en=COALESCE(NULLIF(name_en,''),?),
                             slug=COALESCE(NULLIF(slug,''),?),
                             website=COALESCE(NULLIF(website,''),?),
                             about_fa=COALESCE(NULLIF(about_fa,''),?),
                             province_label=COALESCE(NULLIF(province_label,''),?),
                             updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
                           WHERE id=?""",
                        (cell("name_en"), cell("slug"), (chans.get("website") or [("",)])[0][0],
                         cell("about"), cell("province"), cid))
        else:
            cid = con.execute("""INSERT INTO company
                (name_fa, name_norm, name_en, slug, website, about_fa,
                 province_label, source_id, source_row)
                VALUES (?,?,?,?,?,?,?,?,?)""",
                (name, nm, cell("name_en") or None, cell("slug") or None,
                 (chans.get("website") or [(None,)])[0][0], cell("about") or None,
                 cell("province") or None, src_id, idx)).lastrowid
            stats["companies_new"] += 1

        con.execute("INSERT OR IGNORE INTO company_alias(company_id, alias_norm) VALUES (?,?)",
                    (cid, nm))

        # ── تماس + شاهد ─────────────────────────────────────────────
        for field, vals in chans.items():
            for v, vn in vals:
                ex = con.execute("""SELECT id FROM contact
                                    WHERE company_id=? AND channel=? AND value_norm=?""",
                                 (cid, field, vn)).fetchone()
                if ex:
                    ct_id = ex["id"]
                    stats["contacts_existing"] += 1
                else:
                    ct_id = con.execute("""INSERT INTO contact
                        (company_id, channel, value, value_norm, is_primary, source_id)
                        VALUES (?,?,?,?,0,?)""",
                        (cid, field, v, vn, src_id)).lastrowid
                    stats["contacts_new"] += 1
                con.execute("""INSERT INTO contact_evidence
                    (contact_id, source_id, observed_on, method, value_seen)
                    SELECT ?,?,?,?,? WHERE NOT EXISTS (
                      SELECT 1 FROM contact_evidence
                       WHERE contact_id=? AND source_id IS ? AND method='import')""",
                    (ct_id, src_id, captured_on, "import", v, ct_id, src_id))

        # ── پرچم‌ها ─────────────────────────────────────────────────
        for fname, on in flag_names.items():
            if cell("tavanir") or cell("daneshbonyan"):
                con.execute("""INSERT INTO company_flag(company_id, flag, value, source_id)
                               VALUES (?,?,?,?)
                               ON CONFLICT(company_id, flag) DO NOTHING""",
                            (cid, fname, "بله" if on else "خیر", src_id))
                stats["flags"] += 1

        # ── مشارکت (یک ردیف برای هر سالن) ───────────────────────────
        for hcode in halls:
            hid = bgdb.get_or_create(con, "hall",
                                     {"exhibition_id": ex_id, "code": hcode},
                                     {"label_fa": f"سالن {hcode}"})
            ex = con.execute("""SELECT id FROM participation
                                WHERE exhibition_id=? AND company_id=? AND hall_id=?""",
                             (ex_id, cid, hid)).fetchone()
            if ex:
                con.execute("""UPDATE participation SET priority=?, priority_reason=?
                                WHERE id=?""", (prio, why, ex["id"]))
                stats["participations_existing"] += 1
            else:
                con.execute("""INSERT INTO participation
                    (exhibition_id, company_id, hall_id, booth, priority, priority_reason)
                    VALUES (?,?,?,NULL,?,?)""", (ex_id, cid, hid, prio, why))
                stats["participations_new"] += 1

        bgdb.refresh_search(con, cid)

    if con:
        con.commit()
        con.close()
    return stats


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=str(Path.home() / "xennic-data" / "barghpa-26-iee1405" / "raw"))
    ap.add_argument("--db", default=str(Path.home() / "xennic-data" / "barghpa-26-iee1405"
                                        / "db" / "barghpa_iee1405.sqlite"))
    ap.add_argument("--backup-dir", default=str(Path.home() / "xennic-data"
                                                / "barghpa-26-iee1405" / "backups"))
    ap.add_argument("--exhibition", default="iee1405")
    ap.add_argument("--captured-on", default=date.today().isoformat())
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    if args.write and args.dry_run:
        raise SystemExit("--write و --dry-run با هم معنا ندارد")
    write = args.write

    src = Path(args.src).expanduser()
    if not src.exists():
        raise SystemExit(f"پوشهٔ داده نیست: {src}")
    print(f"منبع : {src}")
    print(f"حالت : {'نوشتن' if write else 'آزمایشی (هیچ نوشتنی انجام نمی‌شود)'}")
    stats = run(src, Path(args.db).expanduser(), write=write,
                captured_on=args.captured_on, exhibition_code=args.exhibition,
                backup_dir=Path(args.backup_dir).expanduser() if write else None)
    print("\n── نتیجه ──")
    for k in ("rows", "companies_new", "companies_existing", "contacts_new",
              "contacts_existing", "participations_new", "participations_existing",
              "flags", "skipped_empty_name"):
        print(f"  {k:24s} {stats[k]}")
    print(f"  {'halls':24s} {len(stats['halls'])} → {' · '.join(sorted(stats['halls']))}")
    if stats["booth_found"]:
        print(f"  ⚠️ {stats['booth_found']} ردیف ستون غرفه داشت — بررسی دستی لازم است")
    else:
        print("  غرفه: هیچ ستون غرفه‌ای در منبع نبود → NULL ماند (ساخته نشد)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
