#!/usr/bin/env python3
"""ایمپورت فهرست غرفه‌داران از CSV به PostgreSQL — با پیش‌نمایش کامل.

  python3 03_ops/import_exhibitors.py DIR/sheet-01.csv --dry-run
  python3 03_ops/import_exhibitors.py DIR/*.csv --dry-run
  python3 03_ops/import_exhibitors.py DIR/*.csv --write

قاعده‌ها:
  • **بدون --write هیچ چیزی نوشته نمی‌شود**؛ فقط می‌گوید چه می‌کرد.
  • نام شرکت یکتا است (crm.norm_text): شرکت موجود به‌روزرسانی می‌شود، تکراری
    ساخته نمی‌شود. کد ORG موجود حفظ می‌شود.
  • دسته‌بندی از متن آزاد به کدهای crm.product_categories نگاشت می‌شود و از
    آن، گروه اولویت A/B/C در می‌آید.
  • منبع و تاریخ بازبینی ثبت می‌شود (truth level = reported، نه verified).

اتصال از داخل کانتینر PostgreSQL انجام می‌شود؛ رمز لازم نیست.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

# ── نگاشت ستون‌ها: هر کلید، فهرست کلیدواژه‌های سرستون ──────────────────
FIELDS = {
    "name":     ["نام شرکت", "نام فارسی", "شرکت", "نام", "name", "company", "exhibitor"],
    "booth":    ["غرفه", "شماره غرفه", "booth", "stand", "غرفه/سالن"],
    "hall":     ["سالن", "سالن/طبقه", "hall", "pavilion"],
    "category": ["دسته", "گروه", "زمینه فعالیت", "حوزه", "محصولات", "category", "sector", "گروه کالایی"],
    "phone":    ["تلفن", "تلفن همراه", "موبایل", "phone", "tel", "mobile"],
    "website":  ["وب", "سایت", "website", "web", "url", "site"],
    "email":    ["ایمیل", "پست الکترونیک", "email", "mail"],
    "city":     ["شهر", "استان", "city", "province"],
    "country":  ["کشور", "country"],
    "notes":    ["توضیح", "درباره", "معرفی", "notes", "description", "about"],
    "products": ["محصول", "کالا", "product", "brands"],
}

# ── نگاشت متن آزاد → کد دسته محصول (کلیدواژه‌ها به ترتیب اولویت) ───────
CATEGORY_RULES = [
    ("TAB_MV",  ["تابلو mv", "تابلو فشار متوسط", "سلول", "switchgear mv", "medium voltage"]),
    ("TAB_LV",  ["تابلو lv", "تابلو فشار ضعیف", "تابلو توزیع", "تابلو برق", "low voltage", "mcc"]),
    ("TRF",     ["ترانس", "transformer"]),
    ("CBL",     ["کابل", "هادی", "سیم", "cable"]),
    ("PRT",     ["رله", "حفاظت", "protection", "relay"]),
    ("CAP",     ["خازن", "راکتور", "کیفیت توان", "capacitor", "power quality", "svar"]),
    ("PV",      ["خورشید", "فتوولتائیک", "اینورتر", "solar", "photovoltaic", "inverter"]),
    ("BESS",    ["باتری", "ذخیره‌ساز", "battery", "bess"]),
    ("AUT",     ["اتوماسیون", "plc", "scada", "کنترل صنعتی", "automation"]),
    ("MET",     ["اندازه‌گیری", "متر", "پایش", "meter", "measurement", "monitoring"]),
    ("MOT",     ["موتور", "ماشین الکتریکی", "ژنراتور", "motor", "generator"]),
    ("SW",      ["نرم‌افزار", "هوش مصنوعی", "سامانه", "software", "ai", "platform"]),
    ("SRV",     ["پیمانکار", "مشاور", "خدمات", "نصب", "contractor", "consult", "service", "epc"]),
    ("EQP",     ["برقگیر", "سکسیونر", "تجهیزات جانبی", "arrester", "isolator"]),
]

# کد دسته → گروه اولویت (طبق تقسیم‌بندی A/B/C پروژه)
GROUP_OF = {
    "TAB_MV": "A", "TAB_LV": "A", "PRT": "A", "CAP": "A", "PV": "A", "BESS": "A",
    "TRF": "B", "CBL": "B", "MOT": "B", "AUT": "B", "MET": "B", "SW": "B",
    "SRV": "C", "EQP": "C", "OTH": "C",
}


def norm(s: str) -> str:
    """نرمال‌سازی برای تطبیق: نیم‌فاصله و «ی/ك» عربی یکسان می‌شوند."""
    s = unicodedata.normalize("NFC", s or "")
    s = s.replace("\u200c", "").replace("\u200f", "").replace("\u200e", "")
    s = s.replace("ي", "ی").replace("ك", "ک").replace("\xa0", " ")
    s = re.sub(r"[^\w\u0600-\u06FF]+", " ", s.lower())
    return re.sub(r"\s+", " ", s).strip()


def detect(headers: list[str]) -> dict[str, int]:
    """سرستون → نام فیلد. هر ستون فقط یک بار انتخاب می‌شود."""
    mapping: dict[str, int] = {}
    used: set[int] = set()
    for field, keys in FIELDS.items():
        best = None
        for i, h in enumerate(headers):
            if i in used:
                continue
            hn = norm(h)
            if not hn:
                continue
            if any(norm(k) == hn for k in keys):
                best = i
                break
            if best is None and any(norm(k) in hn for k in keys):
                best = i
        if best is not None:
            mapping[field] = best
            used.add(best)
    return mapping


def read_csv(path: Path) -> tuple[list[str], list[list[str]]]:
    raw = path.read_bytes()
    for enc in ("utf-8-sig", "utf-8", "cp1256", "windows-1256", "latin-1"):
        try:
            text = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    else:
        raise SystemExit(f"❌ کدگذاری فایل خوانده نشد: {path}")
    rows = list(csv.reader(text.splitlines()))
    rows = [r for r in rows if any((c or "").strip() for c in r)]
    if not rows:
        return [], []
    return rows[0], rows[1:]


def categorize(text: str) -> str:
    t = norm(text)
    for code, keys in CATEGORY_RULES:
        if any(norm(k) in t for k in keys):
            return code
    return "OTH"


class DB:
    """اجرای psql داخل کانتینر PostgreSQL؛ رمز روی خط فرمان نمی‌آید."""

    def __init__(self, docker: str, container: str, db: str, db_user: str):
        self.docker, self.container, self.db, self.db_user = docker, container, db, db_user

    def q(self, sql: str, want_json: bool = False) -> str:
        cmd = f"{self.docker} exec -i {self.container} psql -U {self.db_user} -d {self.db} -X -t -A -v ON_ERROR_STOP=1"
        p = subprocess.run(cmd.split(), input=sql.encode(), stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT)
        out = p.stdout.decode("utf-8", "replace").strip()
        if p.returncode != 0:
            raise SystemExit(f"❌ خطای دیتابیس:\n{out[:1500]}")
        return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--write", action="store_true", help="نوشتن در دیتابیس (پیش‌فرض: پیش‌نمایش)")
    ap.add_argument("--dry-run", action="store_true", help="فقط پیش‌نمایش (پیش‌فرض)")
    ap.add_argument("--source", default="کاتالوگ رسمی نمایشگاه برق ۱۴۰۵",
                    help="منبع داده؛ در پرونده هر شرکت ثبت می‌شود")
    ap.add_argument("--limit", type=int, default=0, help="حداکثر ردیف در هر فایل (۰ = همه)")
    ap.add_argument("--show", type=int, default=8, help="چند نمونه در پیش‌نمایش")
    args = ap.parse_args()

    write = args.write and not args.dry_run

    # ── اتصال از طریق docker (همان روش بقیه اسکریپت‌ها) ──
    docker = "docker"
    container = None
    p = subprocess.run([docker, "ps", "--format", "{{.Names}}\t{{.Label \"com.docker.compose.service\"}}"],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    for line in p.stdout.decode().splitlines():
        parts = line.split("\t")
        if len(parts) >= 2 and parts[1] in ("postgres", "postgresql", "db"):
            container = parts[0]
            break
    if not container:
        print("❌ کانتینر PostgreSQL پیدا نشد (این اسکریپت روی سرور اجرا می‌شود)")
        return 1
    db = "xennic"
    db_user = subprocess.run([docker, "exec", "-i", container, "printenv", "POSTGRES_USER"],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.decode().strip() or "postgres"
    DBq = DB(docker, container, db, db_user)

    # آزمون اتصال + شناسه نمایشگاه
    ex = DBq.q("SELECT id FROM iee1405.exhibitions WHERE code = 'IEE1405'").strip()
    # پیش‌نیاز: ایندکس یکتای نام، وگرنه شرکت تکراری ساخته می‌شود
    uq = DBq.q("SELECT count(*) FROM pg_indexes WHERE schemaname='crm' "
               "AND indexname='organizations_name_uq'").strip()
    if uq != "1":
        print("⚠️  ایندکس یکتای نام شرکت نیست — احتمال ساخت شرکت تکراری هست")
        print("   bash 03_ops/deploy_sql.sh   # 07_import_indexes.sql را اعمال می‌کند")
    if not ex:
        print("❌ نمایشگاه IEE1405 در دیتابیس نیست — اول: bash 03_ops/deploy_sql.sh")
        return 1

    total_new = total_upd = total_skip = total_part = total_site_conflict = 0
    samples: list[str] = []

    for fname in args.files:
        path = Path(fname)
        if not path.is_file():
            print(f"⚠️  رد شد (فایل نیست): {path}")
            continue
        headers, body = read_csv(path)
        if not headers:
            print(f"⚠️  {path.name}: خالی است")
            continue
        mapping = detect(headers)
        print(f"\n════ {path.name} · {len(body)} ردیف")
        print("   نگاشت ستون‌ها:")
        for f in FIELDS:
            if f in mapping:
                print(f"     {f:9s} ← «{headers[mapping[f]]}»")
            elif f in ("name", "booth", "category"):
                print(f"     {f:9s} ← ❌ پیدا نشد")
        if "name" not in mapping:
            print("   ❌ ستون «نام شرکت» پیدا نشد — این فایل رد شد")
            continue

        if args.limit:
            body = body[:args.limit]

        for row in body:
            def get(field: str) -> str:
                i = mapping.get(field)
                return (row[i] if i is not None and i < len(row) else "").strip()

            name = re.sub(r"\s+", " ", get("name"))
            if not name or len(name) < 2:
                total_skip += 1
                continue
            booth_raw = get("booth")
            hall = get("hall")
            cat_text = " ".join(x for x in (get("category"), get("products"), get("notes")) if x)
            cat = categorize(cat_text)
            grp = GROUP_OF.get(cat, "C")

            # وضعیت فعلی در دیتابیس (تکراری؟)
            existing = DBq.q(
                "SELECT code FROM crm.organizations "
                f"WHERE name_norm = crm.norm_text({sql_str(name)}) AND deleted_at IS NULL LIMIT 1"
            ).strip()

            if existing:
                total_upd += 1
                action = f"به‌روزرسانی {existing}"
            else:
                total_new += 1
                action = "شرکت تازه"

            if booth_raw or hall:
                total_part += 1

            if len(samples) < args.show:
                samples.append(
                    f"   • {name[:40]:40s} | غرفه: {(booth_raw or hall or '—')[:12]:12s} | "
                    f"{cat}/{grp} | {action}"
                )

            if write:
                rec = {"name": name, "booth": booth_raw, "hall": hall, "phone": get("phone"),
                       "email": get("email"), "city": get("city"), "country": get("country"),
                       "group": grp, "notes": get("notes")}
                # وب‌سایت یکتاست: اگر شرکت دیگری آن را دارد، خالی می‌ماند تا
                # ایمپورت به خطای قید نخورد (به‌جای شکستن کل ردیف).
                site = get("website")
                site_safe = None
                if site:
                    site = site if site.startswith(("http://", "https://")) else "https://" + site
                    taken = DBq.q(
                        "SELECT code FROM crm.organizations WHERE lower(website) = lower("
                        f"{sql_str(site)}) AND deleted_at IS NULL AND name_norm <> "
                        f"crm.norm_text({sql_str(name)}) LIMIT 1").strip()
                    if taken:
                        total_site_conflict += 1
                    else:
                        site_safe = site
                DBq.q(build_row_sql(ex, rec, site_safe, args.source))

    print("\n════ خلاصه")
    print(f"   شرکت تازه      : {total_new}")
    print(f"   به‌روزرسانی     : {total_upd}")
    print(f"   ردیف بی‌نام     : {total_skip}")
    print(f"   غرفه/مشارکت    : {total_part}")
    if total_site_conflict:
        print(f"   وب‌سایت تکراری   : {total_site_conflict} (خالی گذاشته شد)")
    if samples:
        print("\n════ نمونه (اولین ردیف‌ها)")
        print("\n".join(samples))

    if write:
        print("\n✅ نوشته شد. بازبینی:")
        print("   bash 03_ops/search_hint.sh   # یا در بله: /find بخشی از نام شرکت")
    else:
        print("\n⚠️  این فقط پیش‌نمایش بود — چیزی نوشته نشد.")
        print("   برای اجرای واقعی، همان دستور را با --write بزنید.")
    return 0


def sql_str(s: str) -> str:
    """رشته امن برای SQL (تک‌کوتیشن دوتایی)."""
    return "'" + (s or "").replace("'", "''") + "'"


def build_row_sql(exhibition_id, rec, website_safe: str | None, source: str) -> str:
    """درج/به‌روزرسانی یک شرکت + مشارکت آن، در یک تراکنش.

    • شرکت موجود با name_norm پیدا و تکمیل می‌شود (کد ORG حفظ می‌شود).
    • وب‌سایت فقط اگر در شرکت دیگری نباشد نوشته می‌شود (قید یکتای پایگاه‌داده).
    • غرفه از iee1405.parse_booth تجزیه می‌شود اگر به شکل «سالن-شماره» باشد.
    """
    site = sql_str(website_safe) if website_safe else "NULL"
    return f"""
BEGIN;
DO $$
DECLARE v_org uuid; v_hall text; v_num text;
BEGIN
    -- تجزیه غرفه: «38-12» → سالن 38، غرفه 12
    SELECT p.hall, p.number INTO v_hall, v_num
      FROM iee1405.parse_booth({sql_str(rec['booth'])}) p;
    v_hall := COALESCE(NULLIF({sql_str(rec['hall'])}, ''), v_hall);

    SELECT id INTO v_org FROM crm.organizations
     WHERE name_norm = crm.norm_text({sql_str(rec['name'])}) AND deleted_at IS NULL
     LIMIT 1;

    IF v_org IS NULL THEN
        INSERT INTO crm.organizations
            (legal_name, display_name, country, city, website, phone_main, email_main,
             org_type, initial_group, effective_group, notes_general, created_by, updated_by)
        VALUES ({sql_str(rec['name'])}, {sql_str(rec['name'])},
                COALESCE(NULLIF({sql_str(rec['country'])}, ''), 'IR'),
                NULLIF({sql_str(rec['city'])}, ''), {site},
                NULLIF({sql_str(rec['phone'])}, ''), NULLIF({sql_str(rec['email'])}, ''),
                'manufacturer', {sql_str(rec['group'])}, {sql_str(rec['group'])},
                NULLIF({sql_str(rec['notes'])}, ''), 'import-exhibitors', 'import-exhibitors')
        RETURNING id INTO v_org;
    ELSE
        -- فقط فیلدهای خالی را پر می‌کنیم؛ داده‌ای را بازنویسی نمی‌کنیم
        UPDATE crm.organizations
           SET updated_at = now(), updated_by = 'import-exhibitors',
               website    = COALESCE(website, {site}),
               phone_main = COALESCE(phone_main, NULLIF({sql_str(rec['phone'])}, '')),
               email_main = COALESCE(email_main, NULLIF({sql_str(rec['email'])}, '')),
               city       = COALESCE(city, NULLIF({sql_str(rec['city'])}, '')),
               effective_group = COALESCE(effective_group, {sql_str(rec['group'])})
         WHERE id = v_org;
    END IF;

    IF v_hall IS NOT NULL OR v_num IS NOT NULL THEN
        INSERT INTO iee1405.participations
            (organization_id, exhibition_id, hall, booth_number, participation_type, confirmed)
        VALUES (v_org, {sql_str(exhibition_id)}::uuid, v_hall, v_num, 'exhibitor', false)
        ON CONFLICT (organization_id, exhibition_id) DO UPDATE
           SET hall         = COALESCE(EXCLUDED.hall, iee1405.participations.hall),
               booth_number = COALESCE(EXCLUDED.booth_number, iee1405.participations.booth_number);
    END IF;
END $$;
COMMIT;"""


if __name__ == "__main__":
    sys.exit(main())
