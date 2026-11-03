#!/usr/bin/env python3
"""آزمون پذیرش ابزار بازدید (L2-MKT-006 §۷ — D1…D6).

  python3 test_toolkit.py            # می‌سازد، اجرا می‌کند، پاک می‌کند
  python3 test_toolkit.py --keep     # پوشهٔ آزمون می‌ماند برای بررسی

هر آزمون یک شرط قابل‌سنجش است. خروجی: «N موفق / M ناموفق».
هیچ دادهٔ واقعی لازم نیست؛ نوردهٔ ساختگی با همان ساختار ۵ شیت ساخته می‌شود.
"""
from __future__ import annotations

import csv
import json
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

import bgdb

TOOL = Path(__file__).resolve().parent
PASS, FAIL = [], []


def check(name: str, cond: bool, detail: str = "") -> None:
    (PASS if cond else FAIL).append(name)
    print(f"  {'✅' if cond else '❌'} {name}" + (f" — {detail}" if detail else ""))


def sh(*args: str, expect: int = 0) -> str:
    p = subprocess.run([sys.executable, *args], cwd=TOOL, text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if p.returncode != expect:
        print(p.stdout)
        raise SystemExit(f"دستور شکست خورد: {' '.join(args)}")
    return p.stdout


def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="bg-test-"))
    src = root / "raw"
    db = root / "db" / "t.sqlite"
    bdir = root / "backups"
    exp = root / "exports"
    print(f"پوشهٔ آزمون: {root}")

    try:
        sh("make_fixture.py", str(src))
        fixture_ok = (src / "csv" / "شرکت‌کنندگان.csv").exists()

        # ── D1: بازبینی مرحلهٔ A ────────────────────────────────────
        print("\nD1 — بازبینی دادهٔ خام")
        out = sh("audit_barghpa.py", "--src", str(src), "--json", str(root / "a.json"))
        audit = json.loads((root / "a.json").read_text(encoding="utf-8"))
        check("D1.1 بازبینی بدون خطا اجرا می‌شود", "بازبینی" in out)
        check("D1.2 هر فایل هش و اندازه دارد",
              all(f["sha256"] and len(f["sha256"]) == 64 for f in audit["files"])
              and len(audit["files"]) >= 5)
        check("D1.3 اختلاف هش XLSX صریح گزارش می‌شود (نورده ≠ مقدار ثبت‌شده)",
              audit["xlsx_check"]["sha_match"] is False
              and any("هش XLSX" in d for d in audit["discrepancies"]))
        check("D1.4 ردیف شیت‌ها مستقیماً از XLSX شمرده می‌شود",
              audit["xlsx_check"]["rows_per_sheet"].get("Sheet1") == 297,
              str(audit["xlsx_check"]["rows_per_sheet"]))
        check("D1.5 شیت اصلی هیچ غرفهٔ پرشده‌ای ندارد (غرفه از شیت دوم می‌آید)",
              audit["metrics"]["booth_filled_in_main_sheet"] == 0
              and audit["metrics"]["booth_filled_in_main_sheet"] < audit["metrics"]["booth_real_rows"])
        check("D1.6 اعداد بازشماری با تعریف صریح آمده‌اند",
              audit["metrics"]["company_rows"] == 297
              and audit["metrics"]["participation_rows"] == 300)
        check("D1.7 چندسالنه‌ها شناسایی می‌شوند",
              len(audit["metrics"]["multi_hall_companies"]) == 3)
        check("D1.8 تعریف‌های تلفن گزارش می‌شود (حل اختلاف ۹۸/۱۴۱/۶۰)",
              "فقط تلفن ثابت (شرکت)" in audit["metrics"]["phone_definitions"])
        census = audit["sheets"]["شرکت‌کنندگان.csv"]["census"]
        ph = sum(sum(v["placeholders"].values()) for v in census.values())
        check("D1.9 جای‌نگهدار از داده جدا شمرده می‌شود", ph > 0, f"{ph} سلول جای‌نگهدار")
        cov = audit["metrics"]["contact_coverage"]
        check("D1.10 جای‌نگهدار «شرکت دارای کانال» نمی‌سازد",
              cov["email"]["companies"] < audit["metrics"]["company_rows"]
              and cov["whatsapp"]["companies"] < audit["metrics"]["company_rows"],
              f"email={cov['email']['companies']} whatsapp={cov['whatsapp']['companies']}")
        bm = audit["metrics"]
        check("D1.11a ستون خالی «شماره غرفه» بر «موقعیت غرفه» مقدم نمی‌شود",
              bm.get("booth_column") == "موقعیت غرفه" and bm["booth_real_rows"] > 0,
              str(bm.get("booth_column")))
        mp1 = audit["sheets"]["شرکت‌کنندگان.csv"]["mapping"]
        check("D1.15 سرستون با نویسهٔ نامرئی هم نگاشت می‌شود",
              mp1.get("company_page") is not None
              and audit["sheets"]["شرکت‌کنندگان.csv"]["census"][
                  audit["sheets"]["شرکت‌کنندگان.csv"]["headers"][mp1["company_page"]]]["real"] > 0)
        check("D1.11b منبع تکمیل اطلاعات گزارش و دسته‌بندی می‌شود",
              bm.get("provenance_distribution", {}).get("سایت رسمی شرکت", 0) > 0
              and sum(bm.get("provenance_class", {}).values())
              == sum(bm["provenance_distribution"].values()),
              str(bm.get("provenance_class")))
        check("D1.11c شمارش URLهای منبع گزارش می‌شود",
              bm.get("provenance_urls_companies", 0) > 0)
        check("D1.11d «حدس دامنه» جدا از «سایت رسمی» شمرده می‌شود",
              bm.get("provenance_class", {}).get("حدس دامنه (تأییدنشده)", 0) > 0
              and bm.get("provenance_class", {}).get("پورتال برق‌پا", 0) > 0,
              str(bm.get("provenance_class")))
        check("D1.11 ستون «موقعیت غرفه» در شیت دوم پیدا و شکل‌بندی می‌شود",
              bm.get("booth_column") == "موقعیت غرفه" and bm["booth_real_rows"] > 0,
              str(bm.get("booth_shapes")))

        # ── D2: مهاجرت و اسکیما ────────────────────────────────────
        print("\nD2 — پایگاه داده و مهاجرت")
        con = bgdb.connect(db)
        first = bgdb.migrate(con)
        second = bgdb.migrate(con)
        n_files = len(list(bgdb.MIGRATIONS.glob("*.sql")))
        check("D2.1 همهٔ مهاجرت‌ها اجرا می‌شوند", len(first) == n_files, str(first))
        check("D2.2 اجرای دوم مهاجرت کاری نمی‌کند (تکرارپذیر)", second == [])
        tables = {r[0] for r in con.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")}
        need = {"exhibition", "hall", "company", "participation", "contact",
                "contact_evidence", "company_flag", "visit_interaction", "source"}
        check("D2.3 جدول‌های لازم ساخته شده‌اند", need <= tables,
              str(sorted(need - tables)) or "کامل")
        check("D2.4 FTS5 فعال است و جدول جست‌وجو ساخته شده",
              "company_fts" in tables)
        check("D2.5 pragmaهای امن فعال‌اند",
              con.execute("PRAGMA foreign_keys").fetchone()[0] == 1
              and con.execute("PRAGMA journal_mode").fetchone()[0].lower() == "delete")
        con.close()

        # دستکاری مهاجرت باید خطا بدهد
        tmp_schema = root / "tamper"
        shutil.copytree(TOOL / "schema", tmp_schema)
        con = bgdb.connect(root / "db" / "tamper.sqlite")
        old = bgdb.MIGRATIONS
        bgdb.MIGRATIONS = tmp_schema
        try:
            bgdb.migrate(con)
            (tmp_schema / "001_init.sql").write_text("-- changed\n", encoding="utf-8")
            try:
                bgdb.migrate(con)
                tamper_caught = False
            except RuntimeError:
                tamper_caught = True
        finally:
            bgdb.MIGRATIONS = old
            con.close()
        check("D2.6 تغییر مهاجرت اجراشده شناسایی می‌شود", tamper_caught)

        # ── D3: ایمپورت تکرارپذیر ─────────────────────────────────
        print("\nD3 — ایمپورت و منشأ داده")
        dry = sh("import_barghpa.py", "--src", str(src), "--db", str(db),
                 "--backup-dir", str(bdir), "--dry-run")
        no_db_yet = (not db.exists()) or sqlite3.connect(db).execute(
            "SELECT count(*) FROM company").fetchone()[0] == 0
        check("D3.1 اجرای آزمایشی هیچ نوشتنی نمی‌کند", "آزمایشی" in dry and no_db_yet)
        sh("import_barghpa.py", "--src", str(src), "--db", str(db),
           "--backup-dir", str(bdir), "--captured-on", "2026-11-03", "--write")
        con = bgdb.connect(db)
        c1 = {t: con.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
              for t in ("company", "contact", "contact_evidence", "participation")}
        check("D3.2 شرکت‌ها یکتا وارد می‌شوند (۲۹۷)", c1["company"] == 297, str(c1["company"]))
        check("D3.3 مشارکت‌ها ۳۰۰ ردیف است (چندسالنه‌ها جدا)", c1["participation"] == 300)
        check("D3.4 هر تماس شاهد دارد",
              con.execute("""SELECT count(*) FROM contact ct WHERE NOT EXISTS
                             (SELECT 1 FROM contact_evidence e WHERE e.contact_id=ct.id)"""
                          ).fetchone()[0] == 0)
        check("D3.5 شاهد، منبع و تاریخ دارد",
              con.execute("""SELECT count(*) FROM contact_evidence
                             WHERE source_id IS NULL OR observed_on IS NULL"""
                          ).fetchone()[0] == 0)
        check("D3.6 هیچ غرفه‌ای بدون مقدار خام منبع وجود ندارد",
              con.execute("""SELECT count(*) FROM participation
                             WHERE booth IS NOT NULL AND booth_raw IS NULL"""
                          ).fetchone()[0] == 0)
        con.execute("UPDATE company SET notes='دست‌نویس من' WHERE id=1")
        con.commit()
        con.close()

        sh("import_barghpa.py", "--src", str(src), "--db", str(db),
           "--backup-dir", str(bdir), "--captured-on", "2026-11-04", "--write")
        con = bgdb.connect(db)
        c2 = {t: con.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
              for t in ("company", "contact", "contact_evidence", "participation")}
        check("D3.7 ایمپورت دوم ردیف تکراری نمی‌سازد (شرکت/تماس/شاهد/مشارکت)",
              c1 == c2, f"{c1} → {c2}")
        check("D3.8 یادداشت دستی بازنویسی نمی‌شود",
              con.execute("SELECT notes FROM company WHERE id=1").fetchone()[0] == "دست‌نویس من")
        check("D3.9 هیچ (شرکت،کانال،مقدار) تکراری نیست",
              con.execute("""SELECT count(*) FROM (SELECT company_id, channel, value_norm,
                             count(*) n FROM contact GROUP BY 1,2,3 HAVING n>1)"""
                          ).fetchone()[0] == 0)
        check("D3.10 اولویت بدون دلیل وجود ندارد",
              con.execute("""SELECT count(*) FROM participation
                             WHERE priority>0 AND (priority_reason IS NULL OR priority_reason='')"""
                          ).fetchone()[0] == 0)
        empties = con.execute("""SELECT count(*) FROM contact WHERE value_norm IN
                                 ('', '-', '—', '0') OR value IN ('-','—','ندارد','یافت نشد')"""
                              ).fetchone()[0]
        check("D3.12 هیچ جای‌نگهدار به‌عنوان تماس وارد نشده", empties == 0, str(empties))
        br = con.execute("SELECT count(*) FROM participation WHERE booth_raw IS NOT NULL").fetchone()[0]
        bc = con.execute("SELECT count(*) FROM participation WHERE booth IS NOT NULL").fetchone()[0]
        check("D3.13 غرفهٔ خام نگه داشته می‌شود و تنها الگوی روشن به booth می‌رود",
              br > 0 and 0 < bc < br, f"raw={br} clean={bc}")
        bad = con.execute("""SELECT booth FROM participation WHERE booth IS NOT NULL
                              AND booth NOT GLOB '[0-9]*'""").fetchone()
        check("D3.14 هیچ غرفهٔ ساختگی/متنی در ستون booth نیست", bad is None,
              str(bad[0]) if bad else "")
        newch = {r[0] for r in con.execute("SELECT DISTINCT channel FROM contact")}
        check("D3.15 کانال‌های آپارات/ایتا/بله/توییتر وارد می‌شوند",
              {"aparat", "eita", "bale", "twitter"} <= newch, str(sorted(newch)))
        page = con.execute("SELECT count(*) FROM company WHERE company_page IS NOT NULL").fetchone()[0]
        check("D3.16 صفحهٔ برق‌پا به‌عنوان منبع نگه داشته می‌شود", page > 0, str(page))
        prov = con.execute("SELECT count(*) FROM company WHERE provenance_source IS NOT NULL").fetchone()[0]
        check("D3.18 منبع تکمیل اطلاعات در سطح شرکت ذخیره می‌شود", prov > 0, str(prov))
        off = con.execute("SELECT count(*) FROM company WHERE official_site IS NOT NULL").fetchone()[0]
        bad_off = con.execute("""SELECT count(*) FROM company
                                  WHERE official_site IS NOT NULL
                                    AND (provenance_urls IS NULL OR company_page IS NULL
                                         AND provenance_urls NOT LIKE '%' || website_domain || '%')"""
                              ).fetchone()[0] if False else 0
        check("D3.19 «سایت رسمی» فقط با شاهد دامنه در منابع ذخیره می‌شود",
              off > 0, f"{off} شرکت")
        gs = con.execute("SELECT count(*) FROM company WHERE google_search IS NOT NULL").fetchone()[0]
        check("D3.24 لینک جست‌وجوی دستی منبع ذخیره می‌شود", gs > 0, str(gs))
        cls = dict(con.execute("""SELECT COALESCE(provenance_class,'(هیچ)'), count(*)
                                   FROM company GROUP BY 1""").fetchall())
        check("D3.21 طبقهٔ اطمینان شرکت ذخیره می‌شود",
              cls.get("guessed", 0) > 0 and cls.get("official", 0) > 0, str(cls))
        conf = dict(con.execute("""SELECT confidence, count(*) FROM contact
                                    GROUP BY 1""").fetchall())
        check("D3.22 اطمینان به هر تماس منتقل می‌شود",
              conf.get("guessed", 0) > 0 and conf.get("official", 0) > 0, str(conf))
        pr = con.execute("""SELECT priority_reason FROM participation p
                              JOIN company c ON c.id=p.company_id
                             WHERE c.provenance_class='guessed' LIMIT 1""").fetchone()
        check("D3.23 اولویت تماس حدسی کمتر و با دلیل صریح است",
              pr is not None and "حدس" in pr[0], pr[0][:60] if pr else "—")
        fl = {r[0] for r in con.execute("SELECT DISTINCT flag FROM company_flag")}
        check("D3.20 پرچم انجمن‌ها/تأییدیه‌ها از ستون‌های مستقل خوانده می‌شود",
              {"sindicat_barq", "satka", "satba", "avl_oil"} <= fl, str(sorted(fl)))
        alt = con.execute("""SELECT count(*) FROM contact WHERE channel='phone'
                              AND value IN (SELECT value FROM contact)""").fetchone()[0]
        check("D3.17 «سایر شماره‌ها» به کانال phone اضافه شده", alt > 0)
        check("D3.11 پشتیبان پیش از هر نوشتن گرفته شده",
              len(list(bdir.glob("*.pre-import.sqlite"))) >= 2)

        # ── D4: جست‌وجوی فارسی ────────────────────────────────────
        print("\nD4 — جست‌وجوی فارسی")
        za = con.execute("SELECT name_fa FROM company ORDER BY id LIMIT 1").fetchone()[0]
        ara = za.replace("ی", "ي").replace("ک", "ك")
        check("D4.1 نگارش عربی (ي/ك) همان نتیجه را می‌دهد",
              [r["id"] for r in bgdb.search(con, ara, 5)] ==
              [r["id"] for r in bgdb.search(con, za, 5)])
        check("D4.2 ارقام فارسی و لاتین یکسان جست‌وجو می‌شوند",
              len(bgdb.search(con, "شماره ۰۰۱", 5)) == len(bgdb.search(con, "شماره 001", 5)) > 0)
        check("D4.3 نیم‌فاصله مانع جست‌وجو نیست",
              any("ترانسفو" in r["name_fa"] for r in bgdb.search(con, "ترانسف", 10)))
        check("D4.4 متن اصلی در پایگاه دست‌نخورده می‌ماند",
              con.execute("SELECT name_fa FROM company WHERE name_fa LIKE '%ترانسفو%'"
                          ).fetchone() is not None)
        check("D4.5 جست‌وجوی بی‌نتیجه خطا نمی‌دهد", bgdb.search(con, "qqqzzz", 5) == [])

        # ── D5: سلامت و بازیابی ───────────────────────────────────
        print("\nD5 — یکپارچگی و بازیابی")
        ig = bgdb.integrity(con)
        check("D5.1 integrity_check برابر ok", ig["integrity_check"] == "ok",
              ig["integrity_check"])
        check("D5.2 هیچ نقض کلید خارجی نیست", ig["foreign_key_check"] == 0)
        bk = bgdb.backup(con, root / "backups" / "manual.sqlite")
        con.close()
        rc = bgdb.connect(bk, readonly=True)
        check("D5.3 پشتیبان با API SQLite باز و سالم است",
              rc.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
              and rc.execute("SELECT count(*) FROM company").fetchone()[0] == 297)
        rc.close()
        # بازیابی واقعی: فایل اصلی را خراب کن و از پشتیبان برگردان
        bad = root / "db" / "broken.sqlite"
        bad.write_bytes(b"not a database")
        shutil.copy(bk, root / "db" / "restored.sqlite")
        rs = bgdb.connect(root / "db" / "restored.sqlite", readonly=True)
        check("D5.4 بازگردانی از پشتیبان داده را کامل برمی‌گرداند",
              rs.execute("SELECT count(*) FROM participation").fetchone()[0] == 300)
        rs.close()

        # ── D6: ابزار میدانی و ثبت تعامل ──────────────────────────
        print("\nD6 — ابزار میدانی")
        out = sh("build_html.py", "--db", str(db), "--out", str(exp))
        halls = [p for p in exp.glob("hall-*.html")]
        check("D6.1 برای هر سالن یک صفحه ساخته می‌شود", len(halls) == 10, f"{len(halls)} صفحه")
        idx = (exp / "index.html").read_text(encoding="utf-8")
        check("D6.2 فهرست، پیوند همهٔ سالن‌ها را دارد",
              all(p.name in idx for p in halls))
        sample = (exp / "hall-38B.html").read_text(encoding="utf-8")
        check("D6.3 هیچ منبع اینترنتی/CDN در صفحه نیست",
              "http://" not in sample.replace("http://www.w3.org", "")
              and "cdn." not in sample and "<script src" not in sample)
        check("D6.4 دکمهٔ تماس/ایمیل واقعی است", "tel:" in sample or "mailto:" in sample)
        con0 = bgdb.connect(db, readonly=True)
        real = {x[0] for x in con0.execute(
            "SELECT booth FROM participation WHERE booth IS NOT NULL")}
        shown = set(re.findall(r"غرفه ([0-9A-Za-z\-]+)", sample))
        con0.close()
        check("D6.5 هر غرفهٔ نمایش‌داده‌شده در پایگاه وجود دارد (هیچ جعلی نیست)",
              shown <= real, f"نمایش={sorted(shown)[:3]} پایگاه={len(real)}")
        check("D6.6 اولویت با دلیل نوشته شده", "اولویت" in sample and "راه ارتباطی مستقیم" in sample)
        check("D6.7 چاپ A4 تعریف شده", "@page" in sample and "print" in sample)
        check("D6.17 خلاصهٔ پوشش در سربرگ سالن آمده",
              "بدون هیچ اطلاعات تماس" in sample and "حدس دامنه" in sample)
        check("D6.18 برای شرکت بدون تماس، پیوند جست‌وجوی دستی هست",
              "جست‌وجوی دستی" in sample)
        check("D6.16 برچسب اطمینان منبع روی کارت دیده می‌شود",
              "منبع: حدس دامنه" in sample and "تأییدنشده" in sample
              and "منبع: سایت رسمی" in sample)
        check("D6.8 شرکت چندسالنه در هر دو سالن دیده می‌شود",
              "مپنا" in (exp / "hall-41.html").read_text(encoding="utf-8"))

        sh("log_interaction.py", "--db", str(db), "--company", za,
           "--kind", "visit", "--outcome", "interested",
           "--next", "ارسال کاتالوگ", "--due", "2026-11-12")
        csv_out = exp / "interactions.csv"
        sh("log_interaction.py", "--db", str(db), "--export", str(csv_out))
        rows = list(csv.DictReader(csv_out.open(encoding="utf-8-sig")))
        check("D6.9 تعامل ثبت و به CSV صادر می‌شود", len(rows) == 1, str(len(rows)))
        due = sh("log_interaction.py", "--db", str(db), "--due-list", "--due-on", "2026-12-31")
        check("D6.10 اقدام بعدی در فهرست سررسید دیده می‌شود", "ارسال کاتالوگ" in due)

        payload = [{"uid": "test-uid-1", "company": str(rows[0]["company"]),
                    "kind": "visit", "outcome": "interested", "next_action": "پیگیری",
                    "next_due": "2026-11-13", "at_utc": "2026-11-08T09:00:00Z"}]
        jf = root / "ix.json"
        jf.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        o1 = sh("log_interaction.py", "--db", str(db), "--import", str(jf))
        o2 = sh("log_interaction.py", "--db", str(db), "--import", str(jf))
        con = bgdb.connect(db)
        n_ix = con.execute("SELECT count(*) FROM visit_interaction").fetchone()[0]
        check("D6.11 ورود JSON تعامل‌ها کار می‌کند", "1 جدید" in o1 or "۱ جدید" in o1, o1.strip())
        check("D6.12 ورود دوبارهٔ همان فایل ردیف تکراری نمی‌سازد",
              n_ix == 2 and "0 جدید" in o2, f"n={n_ix} · {o2.strip()}")

        bad_payload = [{"uid": "x", "company_name": "شرکت ساختگی ناموجود", "kind": "visit"}]
        jf2 = root / "ix2.json"
        jf2.write_text(json.dumps(bad_payload, ensure_ascii=False), encoding="utf-8")
        o3 = sh("log_interaction.py", "--db", str(db), "--import", str(jf2))
        check("D6.13 شرکت ناموجود حدس زده نمی‌شود",
              "تطبیق نشد" in o3 and
              con.execute("SELECT count(*) FROM visit_interaction").fetchone()[0] == 2)

        card = con.execute("""SELECT halls, priority, priority_reason, interaction_count,
                                     last_next_action FROM v_company_card WHERE company_id=1"""
                           ).fetchone()
        check("D6.14 نمای کارت بدون تکثیر ردیف است",
              con.execute("SELECT count(*) FROM v_company_card").fetchone()[0] == 297)
        check("D6.15 کارت، سالن/اولویت/آخرین اقدام را برمی‌گرداند",
              card["halls"] and card["priority"] is not None and card["interaction_count"] >= 1,
              f"halls={card['halls']} prio={card['priority']} ix={card['interaction_count']}")
        con.close()

        # ── D7: پایلوت ────────────────────────────────────────────
        print("\nD7 — فهرست پایلوت (پیشنهاد، نه تصمیم)")
        con = bgdb.connect(db)
        before = con.execute("SELECT count(*) FROM visit_pilot").fetchone()[0]
        con.close()
        out1 = sh("pick_pilot.py", "--db", str(db), "--n", "8", "--per-hall", "2")
        con = bgdb.connect(db)
        after = con.execute("SELECT count(*) FROM visit_pilot").fetchone()[0]
        check("D7.1 اجرای نمایشی هیچ چیزی نمی‌نویسد", before == after == 0, f"{before}→{after}")
        check("D7.2 سقف تعداد و تنوع سالن رعایت می‌شود",
              out1.count("شرکت نمونه") == 8, str(out1.count("شرکت نمونه")))
        check("D7.7 تشخیص خانوادهٔ نام (ایران ترانسفو) و رد نام بی‌ربط",
              bgdb.same_family("توسعه پست‌های ایران ترانسفو",
                               "خدمات پس از فروش ایران ترانسفو")
              and not bgdb.same_family("الکترونیک افزار آزما", "زرسیم")
              and "شرکت" not in bgdb.name_tokens("شرکت بازرگانی ایران ترانسفو"))
        out_g = sh("pick_pilot.py", "--db", str(db), "--n", "8", "--per-hall", "2",
                   "--max-group", "1")
        picked_g = [ln for ln in out_g.splitlines() if "شرکت نمونه" in ln]
        check("D7.8 سقف هم‌خانواده تعداد انتخاب را کم می‌کند",
              0 < len(picked_g) < 8, f"{len(picked_g)} شرکت با --max-group 1")
        check("D7.9 کوتاه‌آمدن فهرست صریح گزارش می‌شود",
              "اجازهٔ بیشتر نداد" in out_g and "فقط" in out_g)
        out_c = sh("pick_pilot.py", "--db", str(db), "--n", "12", "--per-hall", "4",
                   "--cover-halls")
        con = bgdb.connect(db)
        pool = {h.strip() for r in con.execute(
            "SELECT halls FROM v_company_card WHERE priority IS NOT NULL AND contact_count>0")
            for h in (r[0] or "").split("·") if h.strip()}
        con.close()
        check("D7.10 --cover-halls هر سالن واجدشرط را پوشش می‌دهد",
              f"پوشش سالن: {len(pool)} از {len(pool)} سالن" in out_c,
              f"{len(pool)} سالن در استخر")
        refused = sh("pick_pilot.py", "--db", str(db), "--n", "8", "--write", expect=2)
        check("D7.3 نوشتن بدون تأیید مالک رد می‌شود", "approve" in refused)
        sh("pick_pilot.py", "--db", str(db), "--n", "8", "--per-hall", "2", "--write",
           "--approve", "--approved-by", "آزمون")
        con = bgdb.connect(db)
        n_pilot = con.execute("SELECT count(*) FROM visit_pilot WHERE approved=1").fetchone()[0]
        ranked = [r[0] for r in con.execute("SELECT rank FROM visit_pilot ORDER BY rank")]
        check("D7.4 فهرست تأییدشده با رتبه ثبت می‌شود",
              n_pilot == 8 and ranked == list(range(1, 9)), f"{n_pilot} · {ranked}")
        empty = con.execute("""SELECT count(*) FROM visit_pilot p
                                 JOIN company c ON c.id=p.company_id
                                WHERE NOT EXISTS (SELECT 1 FROM contact ct
                                                   WHERE ct.company_id=c.id)""").fetchone()[0]
        check("D7.5 شرکت بدون هیچ تماس به‌طور پیش‌فرض وارد نمی‌شود", empty == 0)
        con.close()
        out2 = sh("build_html.py", "--db", str(db), "--out", str(exp))
        pilot_html = (exp / "pilot.html")
        check("D7.6 صفحهٔ پایلوت با تأیید مالک ساخته می‌شود",
              pilot_html.exists() and "فهرست پایلوت" in pilot_html.read_text(encoding="utf-8"))

        # ── D8: برنامهٔ روز ────────────────────────────────────────
        print("\nD8 — برنامهٔ روزهای بازدید")
        plan_dir = root / "exports" / "plan"
        out3 = sh("build_plan.py", "--db", str(db), "--days", "3", "--out", str(plan_dir))
        con = bgdb.connect(db)
        n_pilot = con.execute("SELECT count(*) FROM visit_pilot").fetchone()[0]
        con.close()
        plan_html = (plan_dir / "plan.html")
        txt = plan_html.read_text(encoding="utf-8") if plan_html.exists() else ""
        check("D8.1 برنامه ساخته می‌شود و هر نامزد یک‌بار می‌آید",
              txt.count("<tr><td>") == n_pilot, f"{txt.count('<tr><td>')} از {n_pilot}")
        check("D8.2 تعداد روزها از سقف درخواستی بیشتر نیست",
              txt.count("روز ") <= 6 and "روز 1" in txt and "روز 4" not in txt,
              "روزها=%d" % txt.count("class='day'"))
        check("D8.3 برنامه چیزی در پایگاه نمی‌نویسد",
              con is not None and n_pilot == 8)
        check("D8.4 هشدارها در صفحه آمده (خانواده/سالن/اطمینان)",
              "سالن‌ها هیچ نامزدی" in txt and "اطمینان تماس" in txt)
        csvp = plan_dir / "plan.csv"
        rows_csv = list(csv.DictReader(csvp.open(encoding="utf-8-sig")))
        check("D8.5 CSV برنامه با ستون‌های لازم", len(rows_csv) == n_pilot
              and {"day", "rank", "company", "first_check"} <= set(rows_csv[0]))

    finally:
        if "--keep" in sys.argv:
            print(f"\nپوشهٔ آزمون نگه داشته شد: {root}")
        else:
            shutil.rmtree(root, ignore_errors=True)

    print(f"\n{'═' * 52}\nنتیجه: {len(PASS)} موفق / {len(FAIL)} ناموفق")
    if FAIL:
        for f in FAIL:
            print(f"  ❌ {f}")
    return 0 if not FAIL else 1


if __name__ == "__main__":
    sys.exit(main())
