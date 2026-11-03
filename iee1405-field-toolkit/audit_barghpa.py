#!/usr/bin/env python3
"""بازبینی فهرست غرفه‌داران نمایشگاه برق ۱۴۰۵ — مرحلهٔ A سند L2-MKT-006.

فقط می‌خواند. هیچ فایلی را تغییر نمی‌دهد، جابه‌جا نمی‌کند و در Git چیزی
اضافه نمی‌کند.

  python3 audit_barghpa.py                    # گزارش خوانا
  python3 audit_barghpa.py --samples 8        # نمونهٔ مقادیر هر ستون کلیدی
  python3 audit_barghpa.py --json /tmp/a.json # خلاصهٔ ماشین‌خوان

نسخهٔ ۰.۲ — دو اصلاحی که از اجرای واقعی روی داده بیرون آمد:
  ۱) جای‌نگهدارها («-»، «ندارد»، «یافت نشد»، …) دیگر «داده» شمرده نمی‌شوند.
     پیش‌تر هر کانال «۲۹۷ شرکت» نشان می‌داد چون سلول خالی با «-» پر شده بود.
  ۲) کانال‌های آپارات/ایتا/بله/توییتر، «سایر شماره‌ها»، «موقعیت غرفه» و
     «انجمن‌ها» شناسایی می‌شوند — این‌ها در شیت دوم واقعاً وجود دارند.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
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
RECORDED_COUNTS = {
    "شرکت‌کنندگان.csv": (297, 40),
    "فهرست_کامل_۳۰۰_رکورد.csv": (300, 11),
    "مخاطبین_(فقط_دارای_اطلاعات).csv": (90, 14),
    "آمار_و_دسته‌بندی.csv": (28, 11),
    "راهنما.csv": (19, 2),
}
RECORDED = {
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

# ── جای‌نگهدارها: «خالی» با این نشانه‌ها نوشته شده، نه با سلول تهی ──────
PLACEHOLDER_TOKENS = {
    "-", "—", "–", "−", "_", ".", "...", "…", "?", "؟", "0",
    "ندارد", "نداریم", "ندارد.", "یافت نشد", "یافت‌نشد", "پیدا نشد",
    "نامشخص", "نامعلوم", "خالی", "بدون", "هیچ", "هیچکدام", "هیچ کدام",
    "n/a", "na", "none", "null", "nil", "nan", "false", "no", "unknown",
    "❌", "×", "✗", "✘", "×", "بدون اطلاعات", "اطلاعاتی نیست",
    "ثبت نشده", "در دسترس نیست", "موجود نیست",
}
_PH_NORM = {re.sub(r"\s+", " ", unicodedata.normalize("NFC", p).strip().lower())
            for p in PLACEHOLDER_TOKENS}


def _plain(s: str) -> str:
    s = unicodedata.normalize("NFC", str(s or "")).strip().lower()
    return re.sub(r"\s+", " ", s)


def is_real_cell(cell: str) -> bool:
    """آیا این سلول واقعاً داده دارد؟ «-» و «ندارد» و «یافت نشد» = خالی."""
    v = _plain(cell)
    if not v:
        return False
    if v in _PH_NORM:
        return False
    if set(v) <= set("-–—_ .\u200c"):
        return False
    return True


# ── تشخیص ستون‌ها ────────────────────────────────────────────────────
ALIASES = {
    "name":     ["نام شرکت", "نام فارسی", "نام", "company", "name"],
    "name_en":  ["نام لاتین", "نام انگلیسی", "name_en", "english"],
    "slug":     ["slug", "اسلاگ", "شناسه"],
    "hall":     ["سالن", "hall", "سالن/فضا"],
    "hall_count": ["تعداد سالن"],
    "booth":    ["موقعیت غرفه", "شماره غرفه", "غرفه", "booth", "stand"],
    "type":     ["نوع شرکت", "نوع فعالیت", "فعالیت", "دسته", "type"],
    "province": ["استان", "province", "موقعیت"],
    "company_page": ["صفحه شرکت در برق‌پا", "برق‌پا", "barghpa"],
    "website":  ["وب‌سایت", "وب سایت", "سایت", "website", "url"],
    "email":    ["ایمیل", "پست الکترونیک", "email", "mail"],
    "phone":    ["تلفن ثابت", "تلفن", "phone", "tel"],
    "other_phones": ["سایر شماره‌ها", "سایر شماره ها", "شماره‌های دیگر"],
    "mobile":   ["موبایل", "همراه", "mobile", "cell"],
    "whatsapp": ["واتساپ", "whatsapp"],
    "instagram": ["اینستاگرام", "instagram"],
    "telegram": ["تلگرام", "telegram"],
    "linkedin": ["لینکدین", "linkedin"],
    "twitter":  ["توییتر / X", "توییتر", "twitter", "x"],
    "aparat":   ["آپارات", "aparat"],
    "eita":     ["ایتا", "eita"],
    "bale":     ["بله", "bale"],
    "address":  ["آدرس", "نشانی", "address"],
    "status":   ["وضعیت اطلاعات", "وضعیت", "status"],
    "about":    ["درباره", "توضیح", "معرفی", "description", "about"],
    "tavanir":  ["در فهرست توانیر", "توانیر", "tavanir"],
    "daneshbonyan": ["دانش‌بنیان", "دانش بنیان", "danesh"],
    # منشأ و تأییدیه‌ها — پیش از «assoc» عمومی تا ستون تخصصی‌تر برنده شود
    "provenance_source": ["منبع تکمیل اطلاعات", "منبع اطلاعات"],
    "provenance_urls": ["منابع (URL)", "منابع url"],
    "google_search": ["لینک جستجوی گوگل (برای تکمیل دستی)", "لینک جستجوی گوگل"],
    "logo": ["لوگو", "logo"],
    "assoc_sindicat": ["سندیکای صنعت برق"],
    "assoc_cable": ["انجمن سیم و کابل"],
    "assoc_satka": ["ساتکا"],
    "assoc_satba": ["ساتبا"],
    "assoc_senfi": ["انجمن صنفی"],
    "assoc_avl": ["لیست بلند نفت (AVL)", "لیست بلند نفت"],
    "assoc_other": ["سایر انجمن‌ها", "سایر انجمن ها"],
    "tavanir_products": ["تأییدیه‌های توانیر (محصولات)", "تأییدیه‌های توانیر"],
    "tavanir_vendor_items": ["اقلام مورد تأیید در وندور لیست توزیع"],
    "tavanir_provinces": ["تعداد استان‌های دارای تأییدیه توزیع"],
    "assoc":    ["انجمن‌ها", "انجمن ها", "انجمن"],
}
CONTACT_FIELDS = ["email", "phone", "other_phones", "mobile", "whatsapp",
                  "instagram", "telegram", "linkedin", "twitter", "aparat",
                  "eita", "bale", "website", "address"]
# کانال‌هایی که «حضور» را برای شمارش حداقل یک راه ارتباطی معنا می‌دهند
REACH_FIELDS = ["email", "phone", "other_phones", "mobile", "whatsapp",
                "instagram", "telegram", "linkedin", "twitter", "aparat",
                "eita", "bale", "website"]

AR_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")


def norm_text(s: str) -> str:
    s = unicodedata.normalize("NFC", (s or "")).translate(AR_DIGITS)
    for z in ("\u200c", "\u200d", "\u200e", "\u200f"):
        s = s.replace(z, " ")
    s = s.replace("\u0640", "").replace("ي", "ی").replace("ك", "ک")
    s = re.sub(r"[^\w\u0600-\u06FF]+", " ", s.lower())
    return re.sub(r"\s+", " ", s).strip()


def norm_phone(s: str) -> str:
    s = (s or "").translate(AR_DIGITS)
    s = re.sub(r"[^\d+]", "", s)
    return re.sub(r"^(\+98|0098|98)(?=\d)", "0", s)


def valid_phone(v: str) -> bool:
    n = norm_phone(v)
    if not n:
        return False
    return (n.startswith("0") and 8 <= len(n) <= 13) or (n.startswith("+") and 10 <= len(n) <= 15)


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
    """نگاشت ستون: اولویت با ترتیب نام‌های جای‌گزین است، نه ترتیب ستون‌ها.

    درس اجرای واقعی: شیت دوم هم «شماره غرفه» داشت (تماماً «—») و هم
    «موقعیت غرفه» (پر). چون حلقه روی ستون‌ها می‌گشت، ستون خالی برنده می‌شد
    و کل دادهٔ غرفه صفر گزارش می‌شد.
    """
    mapping, used = {}, set()
    hn = [norm_text(h) for h in headers]
    for field, keys in ALIASES.items():
        kn = [norm_text(k) for k in keys]
        for key in kn:
            hit = next((i for i, h in enumerate(hn) if h == key and i not in used), None)
            if hit is not None:
                mapping[field] = hit
                used.add(hit)
                break
        else:
            for key in kn:
                if len(key) <= 3:
                    continue
                hit = next((i for i, h in enumerate(hn)
                            if key in h and i not in used), None)
                if hit is not None:
                    mapping[field] = hit
                    used.add(hit)
                    break
    return mapping


NO_SPLIT = {"address", "about", "province", "type", "status", "name", "hall",
            "booth", "company_page", "assoc", "hall_count", "name_en", "slug"}
SPLIT_RE = re.compile(r"\s*[,،;؛]\s*|\s{2,}|\s+/\s+|\s*\|\s*")


def split_values(cell: str, field: str | None = None) -> list[str]:
    """مقدارهای واقعی یک سلول؛ جای‌نگهدار حذف می‌شود."""
    if not is_real_cell(cell):
        return []
    if field in NO_SPLIT:
        return [cell.strip()]
    out = [p.strip() for p in SPLIT_RE.split(cell) if is_real_cell(p)]
    return out or [cell.strip()]


def xlsx_row_counts(path: Path):
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
                out[names[i] if i < len(names) else member] = count
    except Exception as e:                      # noqa: BLE001
        return {"__error__": str(e)}
    return out


def git_state(path: Path):
    info = {"repo": None, "tracked": [], "staged": [], "nested_git": [],
            "status_lines": 0, "remote": None}
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
        for args, key in ((["ls-files"], "tracked"),
                          (["diff", "--cached", "--name-only"], "staged")):
            p = subprocess.run(["git", "-C", info["repo"], *args, "--", str(rel)],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            info[key] = [x for x in p.stdout.splitlines() if x.strip()]
        p = subprocess.run(["git", "-C", info["repo"], "status", "--porcelain", "--", str(rel)],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        info["status_lines"] = len([x for x in p.stdout.splitlines() if x.strip()])
        remote = subprocess.run(["git", "-C", info["repo"], "remote", "-v"],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout
        info["remote"] = remote.split()[1] if remote.split() else None
    except Exception:                            # noqa: BLE001
        pass
    for g in path.rglob(".git"):
        if g.is_dir():
            info["nested_git"].append(str(g.relative_to(path)))
    return info


def find_related(root: Path, limit=4000):
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


def census(headers, body, mapping) -> dict:
    """برای هر ستون: چند سلول پر، چند سلول واقعی، و پرتکرارترین نشانه‌ها.

    ستون‌های بی‌نگاشت هم شمرده می‌شوند، چون اغلب همان‌جاست که داده پنهان است.
    """
    out = {}
    for i, h in enumerate(headers):
        field = next((f for f, idx in mapping.items() if idx == i), None)
        n_filled = n_real = 0
        tokens: dict[str, int] = {}
        for r in body:
            c = r[i].strip() if i < len(r) else ""
            if not c:
                continue
            n_filled += 1
            if is_real_cell(c):
                n_real += 1
            else:
                k = _plain(c)[:24]
                tokens[k] = tokens.get(k, 0) + 1
        out[h] = {
            "field": field, "filled": n_filled, "real": n_real,
            "placeholders": dict(sorted(tokens.items(), key=lambda kv: -kv[1])[:4]),
        }
    return out


def samples(headers, body, mapping, fields, n=5) -> dict:
    out = {}
    for f in fields:
        i = mapping.get(f)
        if i is None:
            continue
        vals, seen = [], set()
        for r in body:
            c = r[i].strip() if i < len(r) else ""
            for v in split_values(c, f):
                if v not in seen:
                    seen.add(v)
                    vals.append(v)
                    if len(vals) >= n:
                        break
            if len(vals) >= n:
                break
        out[f] = {"column": headers[i], "samples": vals}
    return out


def audit(show_samples: int = 0) -> dict:
    res = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "tool_version": "0.2",
        "python": sys.version.split()[0],
        "sqlite": None, "fts5": None,
        "source_dir": str(DATA_SRC), "source_exists": DATA_SRC.exists(),
        "files": [], "xlsx_check": {}, "sheets": {}, "metrics": {},
        "discrepancies": [], "blockers": [], "git": {}, "related": {},
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
    except Exception as e:                        # noqa: BLE001
        res["blockers"].append(f"sqlite3: {e}")

    if not DATA_SRC.exists():
        res["blockers"].append(f"مسیر داده نیست: {DATA_SRC}")
        return res

    for p in sorted(DATA_SRC.rglob("*")):
        if p.is_file():
            res["files"].append({"path": str(p.relative_to(DATA_SRC)),
                                 "size": p.stat().st_size, "sha256": sha256(p)})

    xlsx = DATA_SRC / "barghpa-26th-electricity-exhibition-companies.xlsx"
    if xlsx.exists():
        actual = sha256(xlsx)
        res["xlsx_check"] = {
            "path": str(xlsx), "size": xlsx.stat().st_size, "sha256": actual,
            "recorded_sha": RECORDED_XLSX_SHA, "sha_match": actual == RECORDED_XLSX_SHA,
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

    # ── هش/ابعاد/سرشماری شیت‌ها ─────────────────────────────────────
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
        mp = detect(headers)
        t = {
            "rows": len(body), "cols": len(headers),
            "rows_expected": rows_exp, "cols_expected": cols_exp,
            "sha256": got, "sha_match": (got == exp) if exp else None,
            "headers": headers, "mapping": mp,
            "census": census(headers, body, mp),
        }
        if len(body) != rows_exp or len(headers) != cols_exp:
            res["discrepancies"].append(
                f"{name}: {len(body)}×{len(headers)} ولی گزارش {rows_exp}×{cols_exp}")
        if exp and got != exp:
            res["discrepancies"].append(f"{name}: هش با مقدار ثبت‌شده یکسان نیست")
        # نگهبان: ستون داده‌دارِ بی‌نگاشت، در حالی که هم‌نام خالی‌اش نگاشت شده
        empty_fields = {v["field"] for v in t["census"].values()
                        if v["field"] and v["real"] == 0}
        for col, info in t["census"].items():
            if info["field"] is not None or info["real"] == 0:
                continue
            toks = set(norm_text(col).split())
            for fld in empty_fields:
                mapped_col = next((c for c, v in t["census"].items() if v["field"] == fld), "")
                if toks & set(norm_text(mapped_col).split()):
                    res["discrepancies"].append(
                        f"{name}: ستون «{col}» داده دارد ({info['real']} سلول) ولی "
                        f"«{mapped_col}» خالی است و به {fld} نگاشت شده — نگاشت را بررسی کنید")

        if show_samples:
            t["samples"] = samples(headers, body, mp,
                                   ["name", "hall", "booth", "website", "email",
                                    "phone", "other_phones", "mobile", "status",
                                    "company_page", "assoc", "type"], show_samples)
        tables[name] = (headers, body, t)
        res["sheets"][name] = t

    m = res["metrics"]
    comp_name, part_name = "شرکت‌کنندگان.csv", "فهرست_کامل_۳۰۰_رکورد.csv"

    # ── شیت اصلی ────────────────────────────────────────────────────
    if comp_name in tables:
        headers, body, t = tables[comp_name]
        mp = t["mapping"]

        def g(row, f):
            i = mp.get(f)
            return (row[i] if i is not None and i < len(row) else "").strip()

        names = [g(r, "name") for r in body]
        m["company_rows"] = len(body)
        m["company_unique_name_norm"] = len({norm_text(n) for n in names if n})
        m["company_unique_slug"] = len({g(r, "slug") for r in body if g(r, "slug")})
        m["company_empty_name"] = sum(1 for n in names if not n)
        dup: dict[str, int] = {}
        for n in names:
            k = norm_text(n)
            if k:
                dup[k] = dup.get(k, 0) + 1
        m["duplicate_names"] = {k: v for k, v in dup.items() if v > 1}
        m["booth_filled_in_main_sheet"] = sum(1 for r in body if is_real_cell(g(r, "booth")))

        coverage = {}
        for field in CONTACT_FIELDS:
            i = mp.get(field)
            if i is None:
                continue
            comps = values = multi = 0
            for r in body:
                vals = split_values(r[i] if i < len(r) else "", field)
                if vals:
                    comps += 1
                    values += len(vals)
                    if len(vals) > 1:
                        multi += 1
            coverage[field] = {"companies": comps, "values": values,
                               "multi_value_cells": multi}
        m["contact_coverage"] = coverage

        m["companies_with_any_contact"] = sum(
            1 for r in body
            if any(split_values(r[mp[f]] if mp[f] < len(r) else "", f)
                   for f in REACH_FIELDS if f in mp))

        # چند تعریف «شمارهٔ معتبر»
        def valid_companies(fields):
            c = 0
            for r in body:
                hit = False
                for f in fields:
                    i = mp.get(f)
                    if i is None or i >= len(r):
                        continue
                    if any(valid_phone(v) for v in split_values(r[i], f)):
                        hit = True
                c += 1 if hit else 0
            return c

        m["phone_definitions"] = {
            "فقط تلفن ثابت (شرکت)": valid_companies(["phone"]),
            "فقط موبایل (شرکت)": valid_companies(["mobile"]),
            "فقط «سایر شماره‌ها» (شرکت)": valid_companies(["other_phones"]),
            "ثابت+موبایل (شرکت یکتا)": valid_companies(["phone", "mobile"]),
            "هر سه ستون شماره (شرکت یکتا)": valid_companies(["phone", "mobile", "other_phones"]),
            "کل شماره‌های معتبر (مقدار، نه شرکت)": sum(
                len([v for v in split_values(r[i], f) if valid_phone(v)])
                for r in body for f, i in
                [(f, mp[f]) for f in ("phone", "mobile", "other_phones") if f in mp]),
        }

        for field in ("tavanir", "daneshbonyan"):
            i = mp.get(field)
            if i is not None:
                m[f"{field}_true"] = sum(
                    1 for r in body
                    if norm_text(r[i] if i < len(r) else "") in
                    {"1", "true", "بله", "دارد", "yes"})

        i = mp.get("status")
        if i is not None:
            dist: dict[str, int] = {}
            for r in body:
                v = r[i].strip() if i < len(r) else ""
                if is_real_cell(v):
                    dist[v] = dist.get(v, 0) + 1
            m["status_distribution"] = dict(sorted(dist.items(), key=lambda kv: -kv[1]))

        i = mp.get("assoc")
        if i is not None:
            m["assoc_examples"] = [r[i] for r in body[:3]
                                   if is_real_cell(r[i] if i < len(r) else "")][:3]

        # ── منشأ: «منبع تکمیل اطلاعات» و «منابع (URL)» ──────────────
        pi = mp.get("provenance_source")
        ui = mp.get("provenance_urls")
        if pi is not None:
            dist: dict[str, int] = {}
            for r in body:
                v = r[pi].strip() if pi < len(r) else ""
                if is_real_cell(v):
                    dist[v] = dist.get(v, 0) + 1
            m["provenance_distribution"] = dict(sorted(dist.items(), key=lambda kv: -kv[1]))
            cls = {"سایت رسمی/شرکت": 0, "جست‌وجوی وب": 0, "منبع دیگر": 0}
            for v, n in dist.items():
                vn = norm_text(v)
                if "سایت" in vn or "رسمی" in vn:
                    cls["سایت رسمی/شرکت"] += n
                elif "جستجو" in vn or "گوگل" in vn or "وب" in vn or "اینترنت" in vn:
                    cls["جست‌وجوی وب"] += n
                else:
                    cls["منبع دیگر"] += n
            m["provenance_class"] = cls
        if ui is not None:
            with_url = multi = 0
            for r in body:
                v = r[ui].strip() if ui < len(r) else ""
                if not is_real_cell(v):
                    continue
                with_url += 1
                if re.search(r"[\s,،;؛]+https?://|\|", v) or v.count("http") > 1:
                    multi += 1
            m["provenance_urls_companies"] = with_url
            m["provenance_urls_multi"] = multi

    # ── شیت مشارکت‌ها ──────────────────────────────────────────────
    if part_name in tables:
        headers, body, t = tables[part_name]
        mp = t["mapping"]
        halls: dict[str, int] = {}
        i = mp.get("hall")
        for r in body:
            v = (r[i].strip() if i is not None and i < len(r) else "") or "(خالی)"
            halls[v] = halls.get(v, 0) + 1
        m["participation_rows"] = len(body)
        m["hall_distribution"] = dict(sorted(halls.items(), key=lambda kv: -kv[1]))
        m["hall_sum"] = sum(halls.values())
        diff = {}
        for hall, n in HALLS_RECORDED.items():
            if halls.get(hall, 0) != n:
                diff[hall] = {"expected": n, "actual": halls.get(hall, 0)}
        for hall, n in halls.items():
            if hall not in HALLS_RECORDED and hall != "(خالی)":
                diff[hall] = {"expected": 0, "actual": n}
        m["hall_diff"] = diff if diff else "مطابق ثبت"

        # غرفه: آیا واقعاً داده دارد؟
        bi = mp.get("booth")
        if bi is not None:
            vals = [r[bi].strip() if bi < len(r) else "" for r in body]
            real = [v for v in vals if is_real_cell(v)]
            dist: dict[str, int] = {}
            for v in real:
                dist[v] = dist.get(v, 0) + 1
            m["booth_column"] = headers[bi]
            m["booth_real_rows"] = len(real)
            m["booth_distinct"] = len(dist)
            m["booth_top"] = sorted(dist.items(), key=lambda kv: -kv[1])[:12]
            shape = {"ارقام تنها": 0, "سالن-شماره": 0, "دیگر": 0}
            for v in real:
                nv = v.translate(AR_DIGITS).strip()
                if re.fullmatch(r"\d{1,4}", nv):
                    shape["ارقام تنها"] += 1
                elif re.fullmatch(r"[\w\u0600-\u06FF]{1,4}\s*[-–]\s*\d{1,4}", nv):
                    shape["سالن-شماره"] += 1
                else:
                    shape["دیگر"] += 1
            m["booth_shapes"] = shape

        if mp.get("name") is not None:
            per: dict[str, int] = {}
            for r in body:
                k = norm_text(r[mp["name"]])
                if k:
                    per[k] = per.get(k, 0) + 1
            m["multi_hall_companies"] = {k: v for k, v in per.items() if v > 1}
            m["companies_in_participation_sheet"] = len(per)

    # ── سازگاری دو شیت ─────────────────────────────────────────────
    if comp_name in tables and part_name in tables:
        _, b1, t1 = tables[comp_name]
        _, b2, t2 = tables[part_name]
        i1, i2 = t1["mapping"].get("name"), t2["mapping"].get("name")
        if i1 is not None and i2 is not None:
            s1 = {norm_text(r[i1]) for r in b1 if i1 < len(r) and r[i1].strip()}
            s2 = {norm_text(r[i2]) for r in b2 if i2 < len(r) and r[i2].strip()}
            m["in_sheet1_not_sheet2"] = sorted(s1 - s2)[:10]
            m["in_sheet2_not_sheet1"] = sorted(s2 - s1)[:10]
            if s1 - s2 or s2 - s1:
                res["discrepancies"].append(
                    f"ناسازگاری بین دو شیت: {len(s1 - s2)} فقط در شیت شرکت‌کنندگان، "
                    f"{len(s2 - s1)} فقط در شیت ۳۰۰ رکورد")

    # ── ادعاها ────────────────────────────────────────────────────
    cov = m.get("contact_coverage", {})

    def c(f):
        return cov.get(f, {}).get("companies")

    claims = {
        "website_companies": c("website"), "email_companies": c("email"),
        "email_values": cov.get("email", {}).get("values"),
        "landline_companies": c("phone"), "mobile_companies": c("mobile"),
        "phone_values": sum(cov.get(f, {}).get("values") or 0
                            for f in ("phone", "mobile", "other_phones")),
        "instagram": c("instagram"), "telegram": c("telegram"),
        "linkedin": c("linkedin"), "whatsapp": c("whatsapp"),
        "address": c("address"),
        "tavanir": m.get("tavanir_true"), "daneshbonyan": m.get("daneshbonyan_true"),
        "at_least_one": m.get("companies_with_any_contact"),
        "none_found": (len(tables[comp_name][1]) - m["companies_with_any_contact"]
                       if comp_name in tables else None),
    }
    res["claims_vs_actual"] = {k: {"reported": v, "actual": claims.get(k)}
                               for k, v in RECORDED.items()}
    for k, v in RECORDED.items():
        a = claims.get(k)
        if a is not None and a != v:
            res["discrepancies"].append(f"{k}: گزارش {v} · بازشماری {a}")

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
    L: list[str] = []
    add = L.append
    add("═" * 68)
    add("بازبینی فهرست غرفه‌داران — مرحلهٔ A (L2-MKT-006) · ابزار v" + res["tool_version"])
    add("═" * 68)
    add(f"زمان: {res['generated_at']} · پایتون {res['python']} · SQLite {res['sqlite']} · "
        f"FTS5: {'دارد' if res['fts5'] else 'ندارد'}")
    add("قاعده: «-»، «ندارد»، «یافت نشد» و مانند آن‌ها خالی شمرده می‌شوند، نه داده.")

    add("\n── ۱) فایل‌های واقعی ───────────────────────────────────────────")
    for f in res["files"] or []:
        add(f"  {f['size']:>9,} B  {f['sha256'][:16]}…  {f['path']}")
    if not res["files"]:
        add("  (هیچ فایلی یافت نشد)")

    add("\n── ۲) تطبیق هش XLSX ───────────────────────────────────────────")
    x = res.get("xlsx_check") or {}
    if x:
        add(f"  اندازه  : {x['size']:,} B  (ثبت‌شده {RECORDED_XLSX_SIZE:,}) "
            f"{'✅' if x['size_match'] else '❌'}")
        add(f"  SHA-256 : {x['sha256']}")
        add(f"  نتیجه   : {'✅ یکسان با مقدار ثبت‌شده' if x['sha_match'] else '❌ متفاوت'}")
        rows = x.get("rows_per_sheet") or {}
        if rows and "__error__" not in rows:
            add("  ردیف شیت‌ها از منبع: " + " · ".join(f"{k}={v}" for k, v in rows.items()))
    else:
        add("  ❓ فایل XLSX پیدا نشد")

    add("\n── ۳) شیت‌ها و سرشماری سلول‌ها ───────────────────────────────")
    for name, t in res["sheets"].items():
        ok = t["rows"] == t["rows_expected"] and t["cols"] == t["cols_expected"]
        add(f"  {'✅' if ok and t['sha_match'] is not False else '⚠️'} {name}")
        add(f"     {t['rows']}×{t['cols']} (گزارش {t['rows_expected']}×{t['cols_expected']})"
            + ("" if ok else " ❌")
            + (" · هش مطابق ثبت" if t["sha_match"] else
               (" · هش متفاوت با ثبت" if t["sha_match"] is False else "")))
        filled = sum(v["filled"] for v in t["census"].values())
        real = sum(v["real"] for v in t["census"].values())
        add(f"     سلول پر: {filled:,} · سلول واقعی: {real:,} · جای‌نگهدار: {filled - real:,}"
            f" ({(filled - real) * 100 // max(filled, 1)}%)")
        masked = {v["field"]: v["placeholders"] for v in t["census"].values()
                  if v["field"] and v["placeholders"]}
        if masked:
            add("     ستون‌های پرشده با جای‌نگهدار (نمونه):")
            for fld, toks in list(masked.items())[:6]:
                add(f"       {fld:14s} " + " · ".join(f"{k}×{n}" for k, n in toks.items()))
        unmapped = [h for h, v in t["census"].items() if v["field"] is None
                    and norm_text(h) not in {"ردیف", "id", "#"}]
        if unmapped:
            add(f"     بی‌نگاشت ({len(unmapped)}): " + " | ".join(unmapped[:14]))
        for fld, smp in (t.get("samples") or {}).items():
            add(f"     نمونهٔ {fld} [{smp['column']}]: "
                + " · ".join(str(s)[:28] for s in smp["samples"]))

    m = res["metrics"]
    add("\n── ۴) بازشماری (جای‌نگهدار = خالی) ──────────────────────────")
    if "company_rows" in m:
        add(f"  ردیف شرکت        : {m['company_rows']}")
        add(f"  نام یکتا (نرمال) : {m['company_unique_name_norm']}")
        add(f"  نام تکراری       : {m['duplicate_names'] or 'هیچ'}")
        add(f"  غرفه در شیت اصلی : {m.get('booth_filled_in_main_sheet', 0)} سلول واقعی")
    if "participation_rows" in m:
        add(f"  مشارکت‌ها         : {m['participation_rows']} (جمع سالن‌ها {m['hall_sum']})")
        add("  توزیع سالن       : " + " · ".join(
            f"{k}={v}" for k, v in m["hall_distribution"].items()))
        add(f"  اختلاف با ثبت    : {m['hall_diff']}")
        if m.get("multi_hall_companies"):
            add(f"  چندسالنه         : {m['multi_hall_companies']}")
        if "booth_column" in m:
            add(f"  ستون غرفه        : «{m['booth_column']}» — {m['booth_real_rows']} ردیف واقعی، "
                f"{m['booth_distinct']} مقدار یکتا")
            add(f"     شکل مقادیر    : {m['booth_shapes']}")
            add("     پرتکرار       : " + " · ".join(
                f"{k}={v}" for k, v in m["booth_top"][:8]))
    if m.get("contact_coverage"):
        add("\n  کانال        شرکت(واقعی)  مقدار  چندمقداری")
        for k, v in m["contact_coverage"].items():
            add(f"  {k:14s} {v['companies']:>10}  {v['values']:>6}  {v['multi_value_cells']:>8}")
        add(f"  حداقل یک راه ارتباطی: {m.get('companies_with_any_contact')} · "
            f"بدون هیچ تماس: {m['company_rows'] - m.get('companies_with_any_contact', 0)}")
    if m.get("phone_definitions"):
        add("\n  تعریف‌های «شمارهٔ معتبر» — علت اختلاف ۹۸/۱۴۱/۶۰:")
        for k, v in m["phone_definitions"].items():
            add(f"     {k:38s} {v}")
    if m.get("status_distribution"):
        add("\n  وضعیت اطلاعات (ستون منبع): " + " · ".join(
            f"{k}={v}" for k, v in m["status_distribution"].items()))
    if m.get("provenance_distribution"):
        add("\n  منبع تکمیل اطلاعات (ادعای خودِ فایل):")
        for k, v in m["provenance_distribution"].items():
            add(f"     {k:44s} {v}")
        add("     دسته‌بندی: " + " · ".join(
            f"{k}={v}" for k, v in m.get("provenance_class", {}).items()))
        if "provenance_urls_companies" in m:
            add(f"     شرکت‌های دارای URL منبع: {m['provenance_urls_companies']} "
                f"(چند URL: {m['provenance_urls_multi']})")

    add("\n── ۵) ادعای گزارش در برابر بازشماری ──────────────────────────")
    for k, v in (res.get("claims_vs_actual") or {}).items():
        a = v["actual"]
        mark = "✅" if a == v["reported"] else ("➖" if a is None else "❌")
        add(f"  {mark} {k:22s} گزارش {v['reported']:>4} · بازشماری "
            f"{a if a is not None else '—':>4}")

    add("\n── ۶) امنیت Git ───────────────────────────────────────────────")
    g = res.get("git") or {}
    add(f"  مخزن      : {g.get('repo') or '—'}")
    add(f"  remote    : {g.get('remote') or '—'}")
    add(f"  ردیابی‌شده : {len(g.get('tracked') or [])} فایل "
        + ("✅ داده در Git نیست" if not g.get("tracked") else "🚨 باید رفع شود"))
    add(f"  git تودرتو: {g.get('nested_git') or 'ندارد'}")

    add("\n── ۷) فایل‌های مرتبط ────────────────────────────────────────")
    rel = res.get("related") or {}
    for k, label in (("raw_json", "JSON خام"), ("scripts", "اسکریپت")):
        v = rel.get(k) or []
        add(f"  {label}: {len(v)}" + ("" if not v else " → " + " · ".join(v[:3])))

    add("\n── ۸) اختلاف‌ها و موانع ───────────────────────────────────────")
    if not res["discrepancies"] and not res["blockers"]:
        add("  ✅ اختلافی با گزارش و مانعی نیست")
    for d in res["discrepancies"]:
        add(f"  ⚠️  {d}")
    for b in res["blockers"]:
        add(f"  ❌ {b}")
    add("\n" + "═" * 68)
    return "\n".join(L)


def main() -> int:
    global DATA_SRC
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", metavar="PATH", help="خلاصهٔ ماشین‌خوان ('-' برای stdout)")
    ap.add_argument("--src", default=None, help="مسیر پوشهٔ داده")
    ap.add_argument("--samples", type=int, default=0,
                    help="نمونهٔ مقادیر هر ستون کلیدی (برای بازبینی چشمی)")
    args = ap.parse_args()
    if args.src:
        DATA_SRC = Path(args.src).expanduser()

    res = audit(show_samples=args.samples)
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

    return 2 if any(b.startswith("🚨") for b in res["blockers"]) else 0


if __name__ == "__main__":
    sys.exit(main())
