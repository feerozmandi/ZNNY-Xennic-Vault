#!/usr/bin/env python3
"""ساخت دادهٔ نمونه با ساختار گزارش (۵ شیت) برای آزمون audit_barghpa.py.

این داده ساختگی است تا منطق بازبینی پیش از اجرا روی دادهٔ واقعی آزموده شود.
هیچ نام/تلفن/ایمیلی از دادهٔ واقعی در این فایل نیست؛ همه ساختگی‌اند.
"""
from __future__ import annotations

import csv
import random
import sys
import zipfile
from pathlib import Path

PAGE_COL = "صفحه شرکت در برق\u200cپا\u200f"  # نویسهٔ نامرئی عمدی
CO_HEADERS = [
    "ردیف", "نام شرکت", "نام لاتین", "slug", "سالن", "نوع فعالیت", "استان",
    "وب‌سایت", "ایمیل", "تلفن ثابت", "موبایل", "واتساپ", "اینستاگرام",
    "تلگرام", "لینکدین", "آدرس", "وضعیت اطلاعات", "درباره", "در فهرست توانیر",
    "دانش‌بنیان", "سایر شماره‌ها", "آپارات", "ایتا", "بله", "توییتر / X",
    "لینک جستجوی گوگل (برای تکمیل دستی)",
    PAGE_COL, "منبع تکمیل اطلاعات", "منابع (URL)", "لوگو",
    "سندیکای صنعت برق", "ساتکا", "ساتبا", "لیست بلند نفت (AVL)",
]
HALLS = ["38B", "38", "41", "فضای باز", "40", "44B", "38A", "44A", "31A", "31B"]
HALL_COUNTS = [68, 60, 48, 27, 26, 22, 16, 15, 10, 8]
MULTI = {"شرکت نمونه مپنا", "شرکت نمونه ایران‌ترانسفو", "شرکت نمونه آرمان بنیان"}


def build(root: Path) -> None:
    rnd = random.Random(7)
    root.mkdir(parents=True, exist_ok=True)
    (root / "csv").mkdir(exist_ok=True)

    singles = [f"شرکت نمونه شماره {i:03d}" for i in range(1, 295)]
    companies = singles + sorted(MULTI)
    hall_seq = []
    for hall, n in zip(HALLS, HALL_COUNTS):
        hall_seq += [hall] * n
    rnd.shuffle(hall_seq)

    rows = []
    for i, name in enumerate(companies):
        halls = [hall_seq[i]]
        rows.append({
            "ردیف": str(i + 1),
            "نام شرکت": name,
            "نام لاتین": name.replace("شرکت نمونه", "Sample Co"),
            "slug": f"sample-{i+1:03d}",
            "سالن": halls[0],
            "نوع فعالیت": rnd.choice(["تولید", "بازرگانی", "خدمات"]),
            "استان": rnd.choice(["تهران", "اصفهان", "چین", "خراسان رضوی"]),
            "وب‌سایت": f"https://sample{i+1}.example" if i % 4 == 0 else "",
            "ایمیل": (f"info@sample{i+1}.example" if i % 4 == 1 else
                      (f"a@sample{i+1}.example، b@sample{i+1}.example" if i % 4 == 2 else "")),
            "تلفن ثابت": f"۰۲۱-{rnd.randint(10000000, 99999999)}" if i % 2 == 0 else "",
            "موبایل": f"۰۹۱۲{rnd.randint(1000000, 9999999)}" if i % 3 == 0 else "",
            "واتساپ": "بله" if i % 12 == 0 else "",
            "اینستاگرام": f"@sample{i+1}" if i % 8 == 0 else "",
            "تلگرام": f"@sample{i+1}ch" if i % 12 == 1 else "",
            "لینکدین": f"https://linkedin.com/company/sample{i+1}" if i % 12 == 2 else "",
            "آدرس": ("تهران، خیابان نمونه" if i % 9 == 0 else ""),
            "وضعیت اطلاعات": "تأییدشده" if i % 5 == 0 else "ناقص",
            "درباره": "شرکت نمونه برای آزمون.",
            "در فهرست توانیر": "بله" if i < 104 else "خیر",
            "دانش‌بنیان": "بله" if i < 45 else "خیر",
            "سایر شماره‌ها": f"۰۲۱-{rnd.randint(10000000, 99999999)}" if i % 30 == 0 else "-",
            "آپارات": f"aparat.com/sample{i+1}" if i % 40 == 0 else "-",
            "ایتا": f"@sample{i+1}" if i % 50 == 0 else "-",
            "بله": f"@sample{i+1}" if i % 60 == 0 else "-",
            "توییتر / X": f"@sample{i+1}" if i % 70 == 0 else "-",
            PAGE_COL: (f"https://barghpa.com/company/{i+1}" if i % 3 == 0 else "-"),
            "لینک جستجوی گوگل (برای تکمیل دستی)": f"https://www.google.com/search?q=شرکت+نمونه+{i+1}",
            "منبع تکمیل اطلاعات": ("سایت رسمی شرکت" if i % 4 == 0 else
                                    ("حدس دامنه" if i % 4 == 1 else
                                     ("جستجوی وب (گوگل)" if i % 4 == 2 else
                                      "فقط از پورتال‌ها (بدون سایت رسمی تأییدشده)"))),
            "منابع (URL)": (f"https://sample{i+1}.example · https://barghpa.com/c/{i+1}"
                            if i % 4 == 0 else
                            (f"https://www.google.com/search?q=sample{i+1}" if i % 4 == 1 else "-")),
            "لوگو": (f"https://sample{i+1}.example/logo.png" if i % 6 == 0 else "-"),
            "سندیکای صنعت برق": "عضو" if i % 9 == 0 else "-",
            "ساتکا": "عضو" if i % 11 == 0 else "-",
            "ساتبا": "عضو" if i % 13 == 0 else "-",
            "لیست بلند نفت (AVL)": "دارد" if i % 17 == 0 else "-",
        })

    # سلول‌های خالی مثل فایل واقعی با جای‌نگهدار پر می‌شوند
    PLACEHOLDER_FILL = True
    if PLACEHOLDER_FILL:
        for r in rows:
            for k, v in list(r.items()):
                if not v and k not in ("ردیف",):
                    r[k] = "-"

    def write_csv(path, headers, data):
        with path.open("w", encoding="utf-8-sig", newline="") as f:
            w = csv.DictWriter(f, fieldnames=headers, extrasaction="ignore")
            w.writeheader()
            w.writerows(data)

    write_csv(root / "csv" / "شرکت‌کنندگان.csv", CO_HEADERS, rows)
    write_csv(root / "barghpa-26th-electricity-exhibition-companies.csv", CO_HEADERS, rows)

    part = []
    for i, name in enumerate(singles):
        part.append({"نام شرکت": name, "سالن": hall_seq[i],
                     "نوع فعالیت": "تولید", "استان": "تهران"})
    # ۳ شرکت چندسالنه: هر کدام در دو سالن، مجموع ۳۰۰ مشارکت
    slots = hall_seq[len(singles):]
    for m in sorted(MULTI):
        part.append({"نام شرکت": m, "سالن": slots[0], "نوع فعالیت": "تولید", "استان": "تهران"})
        part.append({"نام شرکت": m, "سالن": "41", "نوع فعالیت": "تولید", "استان": "تهران"})
        slots = slots[1:]
    for i, r in enumerate(part):
        r["ردیف"] = str(i + 1)
    part_headers = ["ردیف", "نام شرکت", "سالن", "نوع فعالیت", "استان",
                    "شماره غرفه", "موقعیت غرفه", PAGE_COL]
    for i, r in enumerate(part):
        n = i + 1
        if n % 5 == 0:
            r["موقعیت غرفه"] = f"{r['سالن']}-{n % 40 + 1}"
        elif n % 7 == 0:
            r["موقعیت غرفه"] = f"سالن {r['سالن']}، کنار ورودی"
        else:
            r["موقعیت غرفه"] = "-"
        r[PAGE_COL] = f"https://barghpa.com/company/{n}"
        r["شماره غرفه"] = "—"   # ستون خالی؛ نباید بر «موقعیت غرفه» مقدم شود
    write_csv(root / "csv" / "فهرست_کامل_۳۰۰_رکورد.csv", part_headers, part)

    contacts = [r for r in rows if r["ایمیل"] or r["موبایل"]][:90]
    write_csv(root / "csv" / "مخاطبین_(فقط_دارای_اطلاعات).csv",
              ["نام شرکت", "ایمیل", "تلفن ثابت", "موبایل"], contacts)
    write_csv(root / "csv" / "آمار_و_دسته‌بندی.csv", ["شاخص", "مقدار"],
              [{"شاخص": "کل شرکت‌ها", "مقدار": "297"}])
    write_csv(root / "csv" / "راهنما.csv", ["ستون", "توضیح"],
              [{"ستون": "نام شرکت", "توضیح": "نام فارسی"}])

    # xlsx کمینه با ۵ شیت و ردیف‌شماری واقعی (بدون کتابخانهٔ خارجی)
    sheet_sizes = [(297, 2), (300, 5), (90, 8), (28, 5), (19, 2)]
    with zipfile.ZipFile(root / "barghpa-26th-electricity-exhibition-companies.xlsx", "w") as z:
        z.writestr("[Content_Types].xml",
                   '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                   '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                   '<Default Extension="xml" ContentType="application/xml"/>'
                   '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
                   + "".join(f'<Override PartName="/xl/worksheets/sheet{i+1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
                             for i in range(len(sheet_sizes))) + '</Types>')
        z.writestr("_rels/.rels",
                   '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
        s = "".join(f'<sheet name="Sheet{i+1}" sheetId="{i+1}" r:id="rId{i+1}"/>'
                    for i in range(len(sheet_sizes)))
        z.writestr("xl/workbook.xml",
                   '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                   'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
                   f'<sheets>{s}</sheets></workbook>')
        for i, (nrows, ncols) in enumerate(sheet_sizes):
            body = "".join(
                f'<row r="{r}">' + "".join(
                    f'<c r="{chr(65+c)}{r}" t="inlineStr"><is><t>x{r}{c}</t></is></c>'
                    for c in range(ncols)) + '</row>'
                for r in range(1, nrows + 1))
            z.writestr(f"xl/worksheets/sheet{i+1}.xml",
                       '<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
                       f'<sheetData>{body}</sheetData></worksheet>')

    print(f"نمونه ساخته شد: {root}")


if __name__ == "__main__":
    build(Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/barghpa-fixture"))
