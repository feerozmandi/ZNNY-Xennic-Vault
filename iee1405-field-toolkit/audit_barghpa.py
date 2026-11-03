#!/usr/bin/env python3
"""بازبینی فهرست غرفه‌داران نمایشگاه برق ۱۴۰۵ — مرحلهٔ A سند L2-MKT-006.

فقط می‌خواند. هیچ فایلی را تغییر نمی‌دهد، جابه‌جا نمی‌کند و در Git چیزی
اضافه نمی‌کند. هدف: فهرست واقعی فایل‌ها، تطبیق هش، بازشماری اعداد گزارش با
تعریف صریح، و بررسی اینکه دادهٔ تماس در Git عمومی نرفته باشد.

  python3 audit_barghpa.py                 # گزارش خوانا
  python3 audit_barghpa.py --json -        # خلاصهٔ ماشین‌خوان روی stdout
  python3 audit_barghpa.py --json /tmp/a.json
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import unicodedata
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from xml.etree import ElementTree as ET

# ── مقادیر ثبت‌شده در گزارش و در L2-MKT-006 §۲.۲ (برای تطبیق) ──────────
RECORDED_XLSX_SHA = "41bf57eba4b88620e96ea73d57843782eea3a14168665f8630f8284aebe16ab4"
RECORDED_XLSX_SIZE = 186_741
RECORDED_CSV_SHA = {
    "شرکت‌کنندگان.csv": "94f86db6de3d6370f45a34b8ac4427f5186321b9bb1e77fe69e8a2145c65b52a",
    "فهرست_کامل_۳۰۰_رکورد.csv": "c7e6f73ff8847f156c8f9a21ecf819993c45645b2e871a10a419913226566768",
    "مخاطبین_(فقط_دارای_اطلاعات).csv": "e2ad2aa5d2bb5a9db172bb8a1ef07fa03fd6a2524d128a772cd482bd70c05a36",
    "آمار_و_دسته‌بندی.csv": "0412daa35abd4cb0fd93512ff46f46743e1e391022075f4a7273ae76af64e084",
    "راهنما.csv": "e8a19c8b0172b2903da98b18e666899cf44f1bb920c79555ecb84e04f4924196",
    "barghpa-26th-electricity-exhibition-companies.csv":
        "58b9ddc97cc67745f5b4a76f7909f300187f16682c8374c32c5e51aad7405879",
}
RECORDED_COUNTS = {  # ردیف × ستون، از گزارش §۳
    "شرکت‌کنندگان.csv": (297, 40),
    "فهرست_کامل_۳۰۰_رکورد.csv": (300, 11),
    "مخاطبین_(فقط_دارای_اطلاعات).csv": (90, 14),
    "آمار_و_دسته‌بندی.csv": (28, 11),
    "راهنما.csv": (19, 2),
}
RECORDED = {  # ادعاهای گزارش §۳ دربارهٔ پوشش (شرکت یکتا از ۲۹۷)
    "website_companies": 75, "email_companies": 70, "email_values": 110,
    "landline_companies": 48, "mobile_companies": 38, "phone_values": 141,
    "instagram": 39, "telegram": 24, "linkedin": 25, "whatsapp": 25,
    "address": 32, "tavanir": 104, "daneshbonyan": 45,
    "at_least_one": 90, "none_found": 207,
}
HALLS_RECORDED = {"38B": 68, "38": 60, "41": 48, "فضای باز": 27, "40": 26,
                  "44B": 22, "38A": 16, "44A": 15, "31A": 10, "31B": 8}

VAULT = Path.home() / "ZNNY-Xennic-Vault"
DATA_SRC = VAULT / "05_Knowledge" / "barghpa-26-iee1405"

# ── تشخیص ستون‌ها: کلیدواژه به ترتیب، روی سرستون نرمال‌شده ──────────────
ALIASES = {
    "name":     ["نام شرکت", "نام فارسی", "نام", "company", "name"],
    "name_en":  ["نام لاتین", "نام انگلیسی", "name_en", "english"],
    "slug":     ["slug", "اسلاگ", "شناسه"],
    "hall":     ["سالن", "hall", "سالن/فضا"],
    "booth":    ["غرفه", "شماره غرفه", "booth", "stand", "position"],
    "type":     ["نوع فعالیت", "فعالیت", "دسته", "type"],
    "province": ["استان", "province", "موقعیت"],
    "website":  ["وب‌سایت", "وب سایت", "سایت", "website", "url"],
    "email":    ["ایمیل", "پست الکترونیک", "email", "mail"],
    "phone":    ["تلفن ثابت", "تلفن", "phone", "tel"],
    "mobile":   ["موبایل", "همراه", "mobile", "cell"],
    "whatsapp": ["واتساپ", "whatsapp"],
    "instagram": ["اینستاگرام", "instagram"],
    "telegram": ["تلگرام", "telegram"],
    "linkedin": ["لینکدین", "linkedin"],
    "address":  ["آدرس", "نشانی", "address"],
    "status":   ["وضعیت اطلاعات", "وضعیت", "status"],
    "about":    ["درباره", "توضیح", "معرفی", "description", "about"],
    "tavanir":  ["توانیر", "tavanir"],
    "daneshbonyan": ["دانش‌بنیان", "دانش بنیان", "danesh"],
}
ID_HEADERS = ["ردیف", "#", "id", "row", "شماره ردیف"]
CONTACT_FIELDS = ["email", "phone", "mobile", "whatsapp", "instagram",
                  "telegram", "linkedin", "website", "address"]

# ── نرمال‌سازی برای تطبیق و شمارش یکتا ────────────────────────────────
AR_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")


def norm_text(s: str) -> str:
    s = unicodedata.normalize("NFC", (s or "")).translate(AR_DIGITS)
    s = s.replace("\u200c", " ").replace("\u200d", "").replace("\u200e", "").replace("\u200f", "")
    s = s.replace("\u0640", "").replace("ي", "ی").replace("ك", "ک")
    s = re.sub(r"[^\w\u0600-\u06FF]+", " ", s.lower())
    return re.sub(r"\s+", " ", s).strip()


def norm_phone(s: str) -> str:
    s = (s or "").translate(AR_DIGITS)
    s = re.sub(r"[^\d+]", "", s)
    s = re.sub(r"^(\+98|0098|98)", "0", s)
    return s


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_csv(path: Path):
    raw = path.read_bytes()
    for enc in ("utf-8-sig", "utf-8", "cp1256", "latin-1"):
        try:
            text = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    else:
        raise ValueError(f"کدگذاری خوانده نشد: {path}")
    rows = list(csv.reader(text.splitlines()))
    rows = [r for r in rows if any((c or "").strip() for c in r)]
    return (rows[0] if rows else []), (rows[1:] if rows else [])


def detect(headers):
    mapping, used = {}, set()
    for field, keys in ALIASES.items():
        for i, h in enumerate(headers):
            if i in used:
                continue
            hn = norm_text(h)
            if any(norm_text(k) == hn for k in keys):
                mapping[field] = i
                used.add(i)
                break
        else:  # تطبیق جزئی
            for i, h in enumerate(headers):
                if i in used:
                    continue
                hn = norm_text(h)
                if any(norm_text(k) in hn for k in keys if len(norm_text(k)) > 3):
                    mapping[field] = i
                    used.add(i)
                    break
    return mapping


NO_SPLIT = {"address", "about", "province", "type", "status", "name", "hall"}


def split_values(cell: str, field: str | None = None) -> list[str]:
    """سلول چندمقداری: با کاما/ویرگول/فاصلهٔ چسبیده تقسیم می‌شود.

    برای آدرس/فیلدهای متنی تقسیم انجام نمی‌شود؛ آدرس فارسی خودش کاما دارد.
    """
    if not cell:
        return []
    if field in NO_SPLIT:
        return [cell.strip()]
    parts = re.split(r"\s*[,،;؛]\s*|\s{2,}|\s/\s", cell)
    return [p.strip() for p in parts if p.strip() and p.strip() not in {"—", "-", "–"}]


def xlsx_row_counts(path: Path):
    """شمارش ردیف هر شیت مستقیماً از xlsx — برای تطبیق CSV با منبع."""
    NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
    out = {}
    try:
        with zipfile.ZipFile(path) as z:
            wb = ET.fromstring(z.read("xl/workbook.xml"))
            names = [s.get("name") for s in wb.iter(f"{NS}sheet")]
            sheets = sorted(n for n in z.namelist()
                            if re.match(r"xl/worksheets/sheet\d+\.xml$", n))
            for i, member in enumerate(sheets):
                count = 0
                with z.open(member) as fh:
                    for _, el in ET.iterparse(fh, events=("end",)):
                        if el.tag == f"{NS}row":
                            count += 1
                            el.clear()
                label = names[i] if i < len(names) else member
                out[label] = count
    except Exception as e:                      # noqa: BLE001
        return {"__error__": str(e)}
    return out


def git_state(path: Path):
    """آیا این مسیر در Git ردیابی/استیج شده؟ فقط خواندن."""
    info = {"repo": None, "tracked": [], "staged": [], "nested_git": [], "status_lines": 0}
    d = path
    while d != d.parent:
        if (d / ".git").exists():
            info["repo"] = str(d)
            break
        d = d.parent
    if not info["repo"]:
        return info
    rel = path.relative_to(info["repo"]) if str(path).startswith(info["repo"]) else path
    try:
        p = subprocess.run(["git", "-C", info["repo"], "ls-files", "--", str(rel)],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        info["tracked"] = [x for x in p.stdout.splitlines() if x.strip()]
        p = subprocess.run(["git", "-C", info["repo"], "diff", "--cached", "--name-only", "--", str(rel)],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        info["staged"] = [x for x in p.stdout.splitlines() if x.strip()]
        p = subprocess.run(["git", "-C", info["repo"], "status", "--porcelain", "--", str(rel)],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        info["status_lines"] = len([x for x in p.stdout.splitlines() if x.strip()])
        remote = subprocess.run(["git", "-C", info["repo"], "remote", "-v"],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout
        info["remote"] = remote.split()[1] if remote.split() else None
    except Exception:                            # noqa: BLE001
        pass
    for d in path.rglob(".git"):
        if d.is_dir():
            info["nested_git"].append(str(d.relative_to(path)))
    return info


def find_related(root: Path, limit=4000):
    """فایل‌های مرتبط در جاهای دیگر (خام API، اسکریپت‌ها)."""
    hits = {"raw_json": [], "scripts": [], "archives": []}
    seen = 0
    for base in (root, Path.home() / "xennic-data"):
        if not base.exists():
            continue
        for p in base.rglob("*"):
            seen += 1
            if seen > limit:
                break
            if not p.is_file() or ".git/" in str(p):
                continue
            n = p.name.lower()
            if n.endswith(".json") and ("api" in str(p).lower() or "barghpa" in n):
                hits["raw_json"].append(str(p))
            elif n.endswith(".py") and ("xlsx" in n or "barghpa" in n or "scrape" in n):
                hits["scripts"].append(str(p))
            elif n.endswith((".tar.gz", ".tgz", ".zip")):
                hits["archives"].append(str(p))
    return {k: v[:20] for k, v in hits.items()}


def audit() -> dict:
    res = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "python": sys.version.split()[0],
        "sqlite": None,
        "fts5": None,
        "source_dir": str(DATA_SRC),
        "source_exists": DATA_SRC.exists(),
        "files": [],
        "xlsx_check": {},
        "sheets": {},
        "metrics": {},
        "discrepancies": [],
        "git": {},
        "related": {},
        "blockers": [],
    }

    try:
        import sqlite3
        res["sqlite"] = sqlite3.sqlite_version
        c = sqlite3.connect(":memory:")
        try:
            c.execute("CREATE VIRTUAL TABLE t USING fts5(x)")
            res["fts5"] = True
        except sqlite3.OperationalError:
            res["fts5"] = False
        c.close()
    except Exception as e:                       # noqa: BLE001
        res["blockers"].append(f"sqlite3: {e}")

    if not DATA_SRC.exists():
        res["blockers"].append(f"مسیر داده نیست: {DATA_SRC}")
        return res

    # ── ۱) فهرست فایل‌های واقعی + هش ─────────────────────────────────
    for p in sorted(DATA_SRC.rglob("*")):
        if p.is_file():
            res["files"].append({
                "path": str(p.relative_to(DATA_SRC)),
                "size": p.stat().st_size,
                "sha256": sha256(p),
            })

    # ── ۲) تطبیق هش XLSX ────────────────────────────────────────────
    xlsx = DATA_SRC / "barghpa-26th-electricity-exhibition-companies.xlsx"
    if xlsx.exists():
        actual = sha256(xlsx)
        res["xlsx_check"] = {
            "path": str(xlsx),
            "size": xlsx.stat().st_size,
            "sha256": actual,
            "recorded_sha": RECORDED_XLSX_SHA,
            "sha_match": actual == RECORDED_XLSX_SHA,
            "size_match": xlsx.stat().st_size == RECORDED_XLSX_SIZE,
            "rows_per_sheet": xlsx_row_counts(xlsx),
        }
        if not res["xlsx_check"]["sha_match"]:
            res["discrepancies"].append("هش XLSX با مقدار ثبت‌شده یکسان نیست")
        if not res["xlsx_check"]["size_match"]:
            res["discrepancies"].append(
                f"اندازهٔ XLSX {xlsx.stat().st_size} ≠ {RECORDED_XLSX_SIZE} ثبت‌شده")
    else:
        res["blockers"].append("فایل XLSX پیدا نشد")

    # ── ۳) هش و ابعاد CSVها ─────────────────────────────────────────
    csv_dir = DATA_SRC / "csv"
    tables = {}
    for name, (rows_exp, cols_exp) in RECORDED_COUNTS.items():
        f = csv_dir / name
        if not f.exists():
            res["blockers"].append(f"CSV نیست: {name}")
            continue
        headers, body = read_csv(f)
        got = sha256(f)
        exp = RECORDED_CSV_SHA.get(name)
        table = {
            "rows": len(body), "cols": len(headers),
            "rows_expected": rows_exp, "cols_expected": cols_exp,
            "sha256": got, "sha_match": (got == exp) if exp else None,
            "headers": headers,
            "mapping": detect(headers),
        }
        if len(body) != rows_exp or len(headers) != cols_exp:
            res["discrepancies"].append(
                f"{name}: {len(body)}×{len(headers)} ولی گزارش {rows_exp}×{cols_exp}")
        if exp and got != exp:
            res["discrepancies"].append(f"{name}: هش با مقدار ثبت‌شده یکسان نیست")
        tables[name] = (headers, body, table)
        res["sheets"][name] = table

    # ── ۴) بازشماری شرکت‌ها و مشارکت‌ها ──────────────────────────────
    comp_name = "شرکت‌کنندگان.csv"
    part_name = "فهرست_کامل_۳۰۰_رکورد.csv"
    m = res["metrics"]

    if comp_name in tables:
        headers, body, table = tables[comp_name]
        mp = table["mapping"]
        names, slugs = [], []
        for row in body:
            def g(f):
                i = mp.get(f)
                return (row[i] if i is not None and i < len(row) else "").strip()
            names.append(g("name"))
            slugs.append(g("slug"))
        m["company_rows"] = len(body)
        m["company_unique_name_norm"] = len({norm_text(n) for n in names if n})
        m["company_unique_slug"] = len({s for s in slugs if s})
        m["company_empty_name"] = sum(1 for n in names if not n)
        dup = {}
        for n in names:
            k = norm_text(n)
            if k:
                dup[k] = dup.get(k, 0) + 1
        m["duplicate_names"] = {k: v for k, v in dup.items() if v > 1}
        m["booth_nonempty"] = sum(
            1 for row in body
            if (mp.get("booth") is not None and mp["booth"] < len(row) and row[mp["booth"]].strip())
        )

        # پوشش کانال‌ها: تعداد شرکت (نه تعداد مقدار)
        coverage = {}
        for field in CONTACT_FIELDS:
            i = mp.get(field)
            if i is None:
                continue
            comps, values, multi = 0, 0, 0
            for row in body:
                cell = row[i].strip() if i < len(row) else ""
                vals = split_values(cell, field)
                if cell:
                    comps += 1
                if len(vals) > 1:
                    multi += 1
                values += len(vals) if vals else (1 if cell else 0)
            coverage[field] = {"companies": comps, "values": values, "multi_value_cells": multi}
        m["contact_coverage"] = coverage

        # حداقل یک راه ارتباطی
        any_contact = 0
        for row in body:
            if any((mp.get(f) is not None and mp[f] < len(row) and row[mp[f]].strip())
                   for f in ("email", "phone", "mobile", "whatsapp", "instagram",
                             "telegram", "linkedin", "website")):
                any_contact += 1
        m["companies_with_any_contact"] = any_contact
        m["companies_without_contact"] = len(body) - any_contact

        # تلفن: مقدار در برابر شرکت (اختلاف گزارش §۳)
        if mp.get("phone") is not None:
            valid = 0
            for row in body:
                i = mp["phone"]
                for v in split_values(row[i] if i < len(row) else "", "phone"):
                    if 8 <= len(norm_phone(v)) <= 13:
                        valid += 1
            m["phone_values_valid"] = valid

        # سه تعریف رقیب برای «شماره تلفن» (اختلاف ۹۸ / ۱۴۱ / ۶۰ در اسناد)
        def valid_numbers(fields):
            out, com = 0, 0
            for row in body:
                hit = False
                for f in fields:
                    i = mp.get(f)
                    if i is None or i >= len(row):
                        continue
                    for v in split_values(row[i], "phone"):
                        if 8 <= len(norm_phone(v)) <= 13:
                            out += 1
                            hit = True
                com += 1 if hit else 0
            return {"companies": com, "values": out}

        m["phone_definitions"] = {
            "فقط تلفن ثابت (شرکت)": valid_numbers(["phone"])["companies"],
            "فقط موبایل (شرکت)": valid_numbers(["mobile"])["companies"],
            "ثابت+موبایل (شرکت یکتا)": valid_numbers(["phone", "mobile"])["companies"],
            "ثابت+موبایل+واتساپ (شرکت)": valid_numbers(["phone", "mobile", "whatsapp"])["companies"],
            "تعداد کل شماره‌های معتبر": valid_numbers(["phone", "mobile", "whatsapp"])["values"],
            "شمارهٔ خام در ستون تلفن (بدون اعتبارسنجی)": coverage.get("phone", {}).get("values", 0),
            "شمارهٔ خام در ستون موبایل (بدون اعتبارسنجی)": coverage.get("mobile", {}).get("values", 0),
        }

        # ستون‌های انجمنی
        for field in ("tavanir", "daneshbonyan"):
            i = mp.get(field)
            if i is not None:
                m[f"{field}_true"] = sum(
                    1 for row in body
                    if i < len(row) and norm_text(row[i]) in {"1", "true", "بله", "yes", "دارد"}
                )

        m["status_distribution"] = {}
        i = mp.get("status")
        if i is not None:
            for row in body:
                v = row[i].strip() if i < len(row) else ""
                if v:
                    m["status_distribution"][v] = m["status_distribution"].get(v, 0) + 1

    if part_name in tables:
        headers, body, table = tables[part_name]
        mp = table["mapping"]
        halls = {}
        i = mp.get("hall")
        for row in body:
            v = row[i].strip() if i is not None and i < len(row) else ""
            halls[v or "(خالی)"] = halls.get(v or "(خالی)", 0) + 1
        m["participation_rows"] = len(body)
        m["hall_distribution"] = dict(sorted(halls.items(), key=lambda kv: -kv[1]))
        m["hall_sum"] = sum(halls.values())
        # تطبیق با توزیع ثبت‌شده
        diff = {}
        for hall, n in HALLS_RECORDED.items():
            got = halls.get(hall, 0)
            if got != n:
                diff[hall] = {"expected": n, "actual": got}
        for hall in halls:
            if hall not in HALLS_RECORDED and hall != "(خالی)":
                diff[hall] = {"expected": 0, "actual": halls[hall]}
        m["hall_diff"] = diff if diff else "مطابق ثبت"

        # چندسالنه‌ها
        if mp.get("name") is not None:
            per = {}
            for row in body:
                k = norm_text(row[mp["name"]])
                if k:
                    per[k] = per.get(k, 0) + 1
            m["multi_hall_companies"] = {k: v for k, v in per.items() if v > 1}
            m["companies_in_participation_sheet"] = len(per)

    # ── ۵) آزمون‌های سلامت داده ─────────────────────────────────────
    if comp_name in tables and part_name in tables:
        h1, b1, t1 = tables[comp_name]
        h2, b2, t2 = tables[part_name]
        i1, i2 = t1["mapping"].get("name"), t2["mapping"].get("name")
        if i1 is not None and i2 is not None:
            s1 = {norm_text(r[i1]) for r in b1 if i1 < len(r) and r[i1].strip()}
            s2 = {norm_text(r[i2]) for r in b2 if i2 < len(r) and r[i2].strip()}
            m["in_sheet1_not_sheet2"] = sorted(s1 - s2)[:10]
            m["in_sheet2_not_sheet1"] = sorted(s2 - s1)[:10]
            if s1 - s2 or s2 - s1:
                res["discrepancies"].append(
                    f"ناسازگاری بین دو شیت: {len(s1 - s2)} شرکت فقط در شیت شرکت‌کنندگان، "
                    f"{len(s2 - s1)} فقط در شیت ۳۰۰ رکورد")

    # ── ۶) تطبیق با ادعاهای گزارش ──────────────────────────────────
    cov = res["metrics"].get("contact_coverage", {})
    claims = {
        "website_companies": cov.get("website", {}).get("companies"),
        "email_companies": cov.get("email", {}).get("companies"),
        "email_values": cov.get("email", {}).get("values"),
        "landline_companies": cov.get("phone", {}).get("companies"),
        "mobile_companies": cov.get("mobile", {}).get("companies"),
        "phone_values": cov.get("phone", {}).get("values"),
        "instagram": cov.get("instagram", {}).get("companies"),
        "telegram": cov.get("telegram", {}).get("companies"),
        "linkedin": cov.get("linkedin", {}).get("companies"),
        "whatsapp": cov.get("whatsapp", {}).get("companies"),
        "address": cov.get("address", {}).get("companies"),
        "tavanir": res["metrics"].get("tavanir_true"),
        "daneshbonyan": res["metrics"].get("daneshbonyan_true"),
        "at_least_one": res["metrics"].get("companies_with_any_contact"),
        "none_found": res["metrics"].get("companies_without_contact"),
    }
    res["claims_vs_actual"] = {
        k: {"reported": v, "actual": claims.get(k)} for k, v in RECORDED.items()
    }
    for k, v in RECORDED.items():
        a = claims.get(k)
        if a is not None and a != v:
            res["discrepancies"].append(f"{k}: گزارش {v} · بازشماری {a}")

    # ── ۷) امنیت Git ────────────────────────────────────────────────
    res["git"] = git_state(DATA_SRC)
    g = res["git"]
    if g.get("tracked"):
        res["blockers"].append(
            f"🚨 {len(g['tracked'])} فایل از این پوشه در Git ردیابی می‌شود (مخزن عمومی!)")
    if g.get("staged"):
        res["blockers"].append(f"🚨 {len(g['staged'])} فایل در staging ایندکس است")
    if g.get("nested_git"):
        res["blockers"].append(f"git تودرتو: {g['nested_git']}")

    res["related"] = find_related(VAULT)
    return res


def render(res: dict) -> str:
    L = []
    add = L.append
    add("═" * 68)
    add("بازبینی فهرست غرفه‌داران — مرحلهٔ A (L2-MKT-006)")
    add("═" * 68)
    add(f"زمان: {res['generated_at']} · پایتون {res['python']} · SQLite {res['sqlite']} · "
        f"FTS5: {'دارد' if res['fts5'] else 'ندارد'}")

    add("\n── ۱) فایل‌های واقعی ───────────────────────────────────────────")
    if not res["files"]:
        add("  (هیچ فایلی یافت نشد)")
    for f in res["files"]:
        add(f"  {f['size']:>9,} B  {f['sha256'][:16]}…  {f['path']}")

    add("\n── ۲) تطبیق هش XLSX ───────────────────────────────────────────")
    x = res.get("xlsx_check") or {}
    if x:
        add(f"  اندازه     : {x['size']:,} B  (ثبت‌شده {RECORDED_XLSX_SIZE:,}) "
            f"{'✅' if x['size_match'] else '❌'}")
        add(f"  SHA-256    : {x['sha256']}")
        add(f"  ثبت‌شده    : {RECORDED_XLSX_SHA}")
        add(f"  نتیجه      : {'✅ یکسان' if x['sha_match'] else '❌ متفاوت'}")
        rows = x.get("rows_per_sheet") or {}
        if rows and "__error__" not in rows:
            add(f"  ردیف شیت‌ها از منبع: " + " · ".join(f"{k}={v}" for k, v in rows.items()))
    else:
        add("  ❓ فایل XLSX پیدا نشد")

    add("\n── ۳) شیت‌ها: بازشماری در برابر گزارش ─────────────────────────")
    for name, t in res["sheets"].items():
        ok = (t["rows"] == t["rows_expected"] and t["cols"] == t["cols_expected"])
        sh = "✅" if t["sha_match"] is not False else "⚠️"
        add(f"  {sh} {name}")
        add(f"     {t['rows']}×{t['cols']}  (گزارش {t['rows_expected']}×{t['cols_expected']}) "
            f"{'✅' if ok else '❌'}")
        if t["sha_match"] is False:
            add("     ⚠️ هش با مقدار ثبت‌شده یکسان نیست — فایل پس از ثبت تغییر کرده")
        add(f"     ستون‌های شناسایی‌شده: " + ", ".join(sorted(t["mapping"])))
        skip = {i for i, h in enumerate(t["headers"]) if norm_text(h) in
                {norm_text(k) for k in ID_HEADERS}}
        unknown = [h for i, h in enumerate(t["headers"])
                   if i not in set(t["mapping"].values()) and i not in skip]
        if unknown:
            add(f"     بی‌نگاشت ({len(unknown)}): " + " | ".join(unknown[:12]))

    m = res["metrics"]
    add("\n── ۴) اعداد بازشماری (با تعریف) ──────────────────────────────")
    add("  تعریف: «شرکت» = ردیف شیت شرکت‌کنندگان؛ «مقدار» = یک تماس در یک سلول؛")
    add("          «شرکت دارای کانال» = دست‌کم یک سلول غیرخالی در آن ستون.")
    if "company_rows" in m:
        add(f"  ردیف شرکت        : {m['company_rows']}")
        add(f"  نام یکتا (نرمال) : {m['company_unique_name_norm']}")
        add(f"  slug یکتا        : {m['company_unique_slug']}")
        add(f"  نام تکراری       : {m['duplicate_names'] or 'هیچ'}")
        add(f"  نام خالی         : {m['company_empty_name']}")
        add(f"  غرفهٔ پرشده       : {m['booth_nonempty']}  "
            f"{'(منبع شماره غرفه ندارد — ساخته نمی‌شود)' if m['booth_nonempty'] == 0 else ''}")
    if "participation_rows" in m:
        add(f"  مشارکت‌ها         : {m['participation_rows']} (جمع سالن‌ها {m['hall_sum']})")
        add("  توزیع سالن       : " + " · ".join(f"{k}={v}" for k, v in m["hall_distribution"].items()))
        add(f"  اختلاف با ثبت    : {m['hall_diff']}")
        if m.get("multi_hall_companies"):
            add(f"  چندسالنه         : {m['multi_hall_companies']}")
        add(f"  شرکت یکتا در شیت مشارکت: {m.get('companies_in_participation_sheet')}")
    if m.get("contact_coverage"):
        add("\n  کانال        شرکت   مقدار  چندمقداری")
        for k, v in m["contact_coverage"].items():
            add(f"  {k:12s} {v['companies']:>5}  {v['values']:>6}  {v['multi_value_cells']:>8}")
        add(f"  حداقل یک راه ارتباطی: {m.get('companies_with_any_contact')} · "
            f"بدون تماس: {m.get('companies_without_contact')}")
        if "phone_values_valid" in m:
            add(f"  شماره‌های معتبر (پس از نرمال‌سازی): {m['phone_values_valid']}")
        if m.get("phone_definitions"):
            add("\n  تعریف‌های «شمارهٔ تلفن» — علت اختلاف ۹۸/۱۴۱/۶۰:")
            for k, v in m["phone_definitions"].items():
                add(f"     {k:38s} {v}")
    if m.get("status_distribution"):
        add("  وضعیت اطلاعات    : " + " · ".join(f"{k}={v}" for k, v in m["status_distribution"].items()))

    add("\n── ۵) ادعای گزارش در برابر بازشماری ──────────────────────────")
    for k, v in (res.get("claims_vs_actual") or {}).items():
        a = v["actual"]
        mark = "✅" if a == v["reported"] else ("➖" if a is None else "❌")
        add(f"  {mark} {k:22s} گزارش {v['reported']:>4} · بازشماری {a if a is not None else '—':>4}")

    add("\n── ۶) امنیت Git ───────────────────────────────────────────────")
    g = res.get("git") or {}
    add(f"  مخزن      : {g.get('repo') or '—'}")
    add(f"  remote    : {g.get('remote') or '—'}")
    add(f"  ردیابی‌شده : {len(g.get('tracked') or [])} فایل")
    add(f"  در staging: {len(g.get('staged') or [])} فایل")
    add(f"  git تودرتو: {g.get('nested_git') or 'ندارد'}")
    if g.get("tracked"):
        add("  🚨 این فایل‌ها در Git هستند و مخزن عمومی است:")
        for t in (g["tracked"])[:10]:
            add(f"     {t}")

    add("\n── ۷) فایل‌های مرتبط جای دیگر ────────────────────────────────")
    rel = res.get("related") or {}
    for k, label in (("raw_json", "JSON خام"), ("scripts", "اسکریپت"), ("archives", "آرشیو")):
        add(f"  {label}: {len(rel.get(k) or [])}")
        for p in (rel.get(k) or [])[:5]:
            add(f"     {p}")

    add("\n── ۸) اختلاف‌ها و موانع ───────────────────────────────────────")
    if not res["discrepancies"] and not res["blockers"]:
        add("  ✅ هیچ اختلافی با گزارش و هیچ مانعی نیست")
    for d in res["discrepancies"]:
        add(f"  ⚠️  {d}")
    for b in res["blockers"]:
        add(f"  ❌ {b}")

    add("\n" + "═" * 68)
    return "\n".join(L)


def main() -> int:
    global DATA_SRC
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", metavar="PATH", help="نوشتن خلاصهٔ ماشین‌خوان ('-' برای stdout)")
    ap.add_argument("--src", default=None, help="مسیر پوشهٔ داده")
    args = ap.parse_args()

    if args.src:
        DATA_SRC = Path(args.src).expanduser()

    res = audit()
    print(render(res))

    if args.json:
        blob = json.dumps(res, ensure_ascii=False, indent=1)
        if args.json == "-":
            print("\n-----BEGIN-AUDIT-JSON-----")
            print(blob)
            print("-----END-AUDIT-JSON-----")
        else:
            out = Path(args.json).expanduser()
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(blob, encoding="utf-8")
            print(f"\nخلاصهٔ ماشین‌خوان: {out}")

    hard = [b for b in res["blockers"] if b.startswith("🚨")]
    return 2 if hard else 0


if __name__ == "__main__":
    sys.exit(main())
