#!/usr/bin/env python3
"""خواندن xlsx و ساختن CSV از هر شیت — با کتابخانه استاندارد پایتون.

چرا دستی؟ چون روی سرور ممکن است `openpyxl` نصب نباشد و نصب آن به اینترنت
وابسته است. فایل xlsx در واقع یک ZIP از چند XML است؛ همین کافی است.
اگر ورقی تاریخ داشته باشد و ستون به‌صورت عدد ذخیره شده باشد، متن هشدار
داده می‌شود تا اشتباه وارد دیتابیس نشود.

  python3 03_ops/xlsx_to_csv.py FILE.xlsx --out DIR
  python3 03_ops/xlsx_to_csv.py FILE.xlsx --summary      # فقط خلاصه
"""
from __future__ import annotations

import argparse
import csv
import re
import sys
import unicodedata
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
      "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
      "p": "http://schemas.openxmlformats.org/package/2006/relationships"}


def _col_index(ref: str) -> int:
    """A1 → 0 ، B7 → 1 ، AA3 → 26"""
    letters = re.match(r"([A-Z]+)", ref or "")
    if not letters:
        return 0
    idx = 0
    for ch in letters.group(1):
        idx = idx * 26 + (ord(ch) - 64)
    return idx - 1


def _text_of(node) -> str:
    """همه <t> های داخل یک گره (رشته‌های چندبخشی rich text)."""
    return "".join(t.text or "" for t in node.iter(f"{{{NS['m']}}}t"))


def read_workbook(path: Path):
    """→ [(sheet_name, rows)] ؛ rows = list[list[str]]"""
    with zipfile.ZipFile(path) as z:
        names = set(z.namelist())

        shared: list[str] = []
        if "xl/sharedStrings.xml" in names:
            root = ET.fromstring(z.read("xl/sharedStrings.xml"))
            shared = [_text_of(si) for si in root.findall("m:si", NS)]

        # نام شیت‌ها و مسیر فایلشان
        rels = {}
        if "xl/_rels/workbook.xml.rels" in names:
            for rel in ET.fromstring(z.read("xl/_rels/workbook.xml.rels")).findall("p:Relationship", NS):
                rels[rel.get("Id")] = rel.get("Target", "")
        wb = ET.fromstring(z.read("xl/workbook.xml"))
        sheets = []
        for sh in wb.findall("m:sheets/m:sheet", NS):
            rid = sh.get(f"{{{NS['r']}}}id")
            target = rels.get(rid, "")
            if target.startswith("/"):
                target = target.lstrip("/")
            elif not target.startswith("xl/"):
                target = "xl/" + target
            sheets.append((sh.get("name", "?"), target))

        out = []
        for sheet_name, target in sheets:
            if target not in names:
                continue
            data = ET.fromstring(z.read(target))
            rows = []
            for row in data.iter(f"{{{NS['m']}}}row"):
                cells: dict[int, str] = {}
                for c in row.findall("m:c", NS):
                    t = c.get("t")
                    if t == "inlineStr":
                        is_node = c.find("m:is", NS)
                        val = _text_of(is_node) if is_node is not None else ""
                    else:
                        v = c.find("m:v", NS)
                        val = (v.text or "") if v is not None else ""
                        if t == "s" and val.isdigit():
                            i = int(val)
                            val = shared[i] if i < len(shared) else ""
                        elif t == "b":
                            val = "TRUE" if val == "1" else "FALSE"
                    if val != "":
                        cells[_col_index(c.get("r", "A1"))] = val
                width = max(cells) + 1 if cells else 0
                rows.append([cells.get(i, "") for i in range(width)])
            # سطرهای کاملاً خالی انتهایی را بردار
            while rows and not any(x.strip() for x in rows[-1]):
                rows.pop()
            out.append((sheet_name, rows))
        return out


def clean(s: str) -> str:
    """نویسه‌های کنترلی و فاصله‌های اضافی.

    نیم‌فاصله (U+200C) عمداً **حفظ** می‌شود: «برق‌آوران» با نیم‌فاصله نوشته
    می‌شود و تبدیلش به فاصله، نام شرکت را برای جست‌وجو و تطبیق خراب می‌کند.
    """
    s = unicodedata.normalize("NFC", (s or "").replace("\xa0", " "))
    s = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", s)
    s = re.sub(r"[ \t]+", " ", s)
    return s.strip()


def safe(name: str) -> str:
    return re.sub(r"[^0-9A-Za-z\u0600-\u06FF_-]+", "-", name).strip("-")[:40] or "sheet"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("xlsx")
    ap.add_argument("--out", default="exhibitor-csv")
    ap.add_argument("--summary", action="store_true", help="فقط خلاصه، بدون نوشتن CSV")
    ap.add_argument("--sample-rows", type=int, default=3)
    args = ap.parse_args()

    path = Path(args.xlsx)
    if not path.is_file():
        print(f"❌ فایل پیدا نشد: {path}")
        return 1
    if path.suffix.lower() != ".xlsx":
        print(f"❌ پسوند «{path.suffix}» پشتیبانی نمی‌شود.")
        print("   در Excel/LibreOffice: Save As → Excel Workbook (.xlsx)")
        return 1

    sheets = read_workbook(path)
    if not sheets:
        print("❌ هیچ شیتی خوانده نشد — فایل سالم است؟")
        return 1

    out_dir = Path(args.out)
    if not args.summary:
        out_dir.mkdir(parents=True, exist_ok=True)

    print(f"📄 {path.name} · {len(sheets)} شیت\n")
    written = []
    for i, (name, rows) in enumerate(sheets, 1):
        rows = [[clean(c) for c in r] for r in rows]
        header = rows[0] if rows else []
        body = rows[1:] if rows else []
        nonempty = [r for r in body if any(r)]
        print(f"── شیت {i}: «{name}» · {len(nonempty)} ردیف × {len(header)} ستون")
        for j, col in enumerate(header[:14], 1):
            print(f"     {j:2d}. {col}")
        if len(header) > 14:
            print(f"     … و {len(header) - 14} ستون دیگر")
        for r in nonempty[:args.sample_rows]:
            cells = [c[:28] for c in r[:6]]
            print("     نمونه: " + " | ".join(cells))
        if not args.summary:
            # همیشه با UTF-8 (بدون BOM) تا ایمپورت دقیق باشد
            fname = f"sheet-{i:02d}.csv"
            with (out_dir / fname).open("w", encoding="utf-8", newline="") as f:
                w = csv.writer(f)
                w.writerow(header)
                w.writerows(body)
            written.append((fname, name, len(nonempty), len(header)))
            print(f"     → {out_dir/fname}")
        print()

    if written:
        # نگاشت نام شیت ↔ فایل، تا بعداً معلوم باشد کدام فایل از کدام شیت است
        manifest = out_dir / "sheets.txt"
        with manifest.open("w", encoding="utf-8") as f:
            for fname, name, rows, cols in written:
                f.write(f"{fname}\t{name}\t{rows}\t{cols}\n")
        print("✅ CSVها ساخته شدند (نام شیت‌ها در sheets.txt):")
        for fname, name, rows, cols in written:
            print(f"   {out_dir/fname}  ←  «{name}» ({rows} ردیف)")
        print("\nگام بعد (فقط پیش‌نمایش، بدون نوشتن در دیتابیس):")
        print(f"   python3 03_ops/import_exhibitors.py {out_dir}/sheet-01.csv --dry-run")
    return 0


if __name__ == "__main__":
    sys.exit(main())
