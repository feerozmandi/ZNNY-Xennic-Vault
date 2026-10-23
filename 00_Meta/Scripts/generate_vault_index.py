#!/usr/bin/env python3
"""
اسکریپت تولید/به‌روزرسانی خودکار «فهرست درختی نودها».

طبق قاعده ۱۸ سند META-CONV-001 — قواعد توسعه پروژه، این اسکریپت باید پس
از هر ساخت، حذف، جابه‌جایی یا تغییر نام نود اجرا شود تا فایل
00_Meta/VAULT-INDEX.md با وضعیت واقعی Vault همگام بماند.

نحوه اجرا (از ریشه ریپازیتوری):
    python3 00_Meta/Scripts/generate_vault_index.py

این اسکریپت فقط بخش بین نشانه‌های AUTO-GENERATED را بازنویسی می‌کند؛
متن قبل و بعد از این نشانه‌ها (مثلاً مقدمه یا یادداشت‌های دستی) دست‌نخورده
باقی می‌ماند.
"""
import glob
import os
import re
import sys

import datetime

PERSIAN_DIGITS = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")


def _gregorian_to_jalali(gy, gm, gd):
    """تبدیل میلادی به شمسی، بدون نیاز به کتابخانه بیرونی (الگوریتم استاندارد)."""
    g_d_m = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
    gy2 = gy + 1 if gm > 2 else gy
    days = (
        355666 + (365 * gy) + ((gy2 + 3) // 4) - ((gy2 + 99) // 100)
        + ((gy2 + 399) // 400) + gd + g_d_m[gm - 1]
    )
    jy = -1595 + (33 * (days // 12053))
    days %= 12053
    jy += 4 * (days // 1461)
    days %= 1461
    if days > 365:
        jy += (days - 1) // 365
        days = (days - 1) % 365
    if days < 186:
        jm = 1 + days // 31
        jd = 1 + (days % 31)
    else:
        jm = 7 + (days - 186) // 30
        jd = 1 + ((days - 186) % 30)
    return jy, jm, jd


def today_fa():
    g = datetime.date.today()
    jy, jm, jd = _gregorian_to_jalali(g.year, g.month, g.day)
    return f"{jy:04d}-{jm:02d}-{jd:02d}".translate(PERSIAN_DIGITS)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)

INDEX_PATH = "00_Meta/VAULT-INDEX.md"
START_MARKER = "<!-- AUTO-GENERATED:START -->"
END_MARKER = "<!-- AUTO-GENERATED:END -->"

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.S)
ABSTRACT_RE = re.compile(r"^> \[!abstract\][^\n]*\n((?:>.*\n?)+)", re.M)
FM_FIELD_RE = re.compile(r"^(\w+):\s*(.*)$", re.M)

# ترتیب و عنوان فارسی پوشه‌های نودها. اگر پوشه جدیدی اضافه شود که در این
# دیکشنری نیست، همچنان با نام خام پوشه در فهرست ظاهر می‌شود (اسکریپت خطا
# نمی‌دهد).
GROUP_LABELS = {
    "01_Founder": "🧑‍💼 بنیان‌گذار (Founder)",
    "02_PreLaunch/L1-STR": "🎯 راهبرد (Strategy)",
    "02_PreLaunch/L1-BRD": "🎨 برند (Brand)",
    "02_PreLaunch/L1-LEG": "⚖️ حقوقی (Legal)",
    "02_PreLaunch/L1-FIN": "💰 مالی (Finance)",
    "02_PreLaunch/L1-MKT": "📈 بازار (Market)",
    "03_Launch/L2-AI": "🤖 هوش مصنوعی (AI)",
    "03_Launch/L2-FIN": "💰 مالی (Finance)",
    "03_Launch/L2-HR": "👥 منابع انسانی (HR)",
    "03_Launch/L2-LEG": "⚖️ حقوقی (Legal)",
    "03_Launch/L2-MKT": "📣 بازاریابی (Marketing)",
    "03_Launch/L2-OPS": "⚙️ عملیات (Operations)",
    "03_Launch/L2-PLT": "💻 پلتفرم (Platform)",
    "03_Launch/L2-SEC": "🔒 امنیت (Security)",
    "03_Launch/L2-TEC": "🛠️ خدمات فنی (Technical Services)",
    "00_Meta/Integration": "🔌 یکپارچه‌سازی فنی (Integration)",
    "00_Meta/Governance": "🏛️ حاکمیت و نقش‌ها (Governance)",
    "05_Knowledge/L1-KNW": "📚 پایگاه دانش (Knowledge Base)",
}

# ترتیب نمایش بخش‌های اصلی (لایه‌ها)
TOP_SECTIONS = [
    ("01_Founder", "۱. بنیان‌گذار (Founder)"),
    ("02_PreLaunch", "۲. پیش از راه‌اندازی (PreLaunch)"),
    ("03_Launch", "۳. راه‌اندازی (Launch)"),
    ("00_Meta/Integration", "۴. یکپارچه‌سازی فنی (Meta / Integration)"),
    ("00_Meta/Governance", "۵. حاکمیت و نقش‌ها (Meta / Governance)"),
    ("05_Knowledge", "۶. پایگاه دانش (Knowledge)"),
]

NODE_DIRS = ["01_Founder", "02_PreLaunch", "03_Launch", "00_Meta/Integration", "00_Meta/Governance", "05_Knowledge"]


def parse_node(path):
    text = open(path, encoding="utf-8").read()
    m = FRONTMATTER_RE.match(text)
    if not m:
        return None
    fm_text = m.group(1)
    fields = dict(FM_FIELD_RE.findall(fm_text))
    node_id = fields.get("id", "").strip()
    title = fields.get("title", "").strip()
    status = fields.get("status", "").strip()

    body = text[m.end():]
    summary = ""
    am = ABSTRACT_RE.search(body)
    if am:
        lines = [l.strip()[1:].strip() for l in am.group(1).strip().split("\n")]
        summary = " ".join(l for l in lines if l)

    return {
        "id": node_id or os.path.splitext(os.path.basename(path))[0],
        "title": title,
        "status": status,
        "summary": summary,
        "path": path,
    }


def natural_key(node_id):
    parts = re.split(r"(\d+)", node_id)
    return [int(p) if p.isdigit() else p for p in parts]


def group_key_for(path):
    rel_dir = os.path.dirname(path)
    # گروه‌بندی بر اساس زیرپوشه دو-سطحی برای PreLaunch/Launch (مثلاً L1-LEG)
    return rel_dir


def collect_nodes():
    all_nodes = []
    for base in NODE_DIRS:
        for f in glob.glob(base + "/**/*.md", recursive=True):
            node = parse_node(f)
            if node:
                all_nodes.append(node)
    return all_nodes


def make_link(path):
    rel = os.path.relpath(path, start=os.path.dirname(INDEX_PATH))
    rel = rel.replace(os.sep, "/")
    if rel.startswith(".."):
        return f"<{rel}>"
    return f"<./{rel}>"


def render():
    nodes = collect_nodes()
    nodes.sort(key=lambda n: natural_key(n["id"]))

    by_group = {}
    for n in nodes:
        g = group_key_for(n["path"])
        by_group.setdefault(g, []).append(n)

    lines = []
    total = 0
    for base, label in TOP_SECTIONS:
        # زیرگروه‌های مستقیم زیر این بخش
        sub_groups = sorted(
            [g for g in by_group if g == base or g.startswith(base + "/")],
            key=lambda g: natural_key(g),
        )
        if not sub_groups:
            continue
        lines.append(f"## {label}\n")
        for g in sub_groups:
            glabel = GROUP_LABELS.get(g, g)
            if g != base:
                lines.append(f"### {glabel}\n")
            for n in sorted(by_group[g], key=lambda n: natural_key(n["id"])):
                total += 1
                link = make_link(n["path"])
                summary = f" — {n['summary']}" if n["summary"] else ""
                lines.append(f"- [**{n['id']}** — {n['title']}]({link}){summary}")
            lines.append("")
        lines.append("")

    lines.append("## 📋 اسناد حاکمیتی و قالب‌ها\n")
    lines.append(
        "- [**META-CONV-001** — قواعد توسعه پروژه]"
        "(<./Conventions/META-CONV-001 — قواعد توسعه پروژه.md>) — "
        "مرجع رسمی تمام قواعد و استانداردهای Vault."
    )
    lines.append(
        "- [**node-template**](<./Templates/node-template.md>) — "
        "قالب پیش‌فرض برای ساخت نود جدید."
    )
    lines.append("")

    lines.append("## 🗄️ منابع خام و بایگانی\n")
    lines.append(
        "- [00_Meta/Sources](<./Sources/README.md>) — اسناد خام منبع که هنوز "
        "به‌طور کامل به نود تبدیل نشده‌اند."
    )
    lines.append(
        "- [00_Meta/Archive](<./Archive/README.md>) — اسناد منسوخ‌شده‌ای که "
        "محتوایشان به نودهای رسمی منتقل شده است."
    )
    lines.append("")

    lines.append(f"**تعداد کل نودهای رسمی: {total}**")
    lines.append(f"**آخرین به‌روزرسانی خودکار: {today_fa()}**")

    return "\n".join(lines).rstrip() + "\n"


def update_index_file():
    generated = render()
    if os.path.exists(INDEX_PATH):
        current = open(INDEX_PATH, encoding="utf-8").read()
    else:
        current = (
            "---\n"
            "id: META-INDEX\n"
            "title: فهرست درختی Vault\n"
            "layer: Meta\n"
            "domain: CONV\n"
            "status: approved\n"
            f"owner: احمد فیروزمندی بندپی\n"
            "created: 2026-10-22\n"
            "version: 1.0.0\n"
            "dependencies: [META-CONV-001]\n"
            "tags: [meta, index, navigation]\n"
            "---\n\n"
            "# فهرست درختی Vault\n\n"
            "> [!abstract] هدف\n"
            "> دسترسی سریع به تمام نودهای موجود در Vault بدون نیاز به باز و بسته "
            "کردن دستی تمام پوشه‌ها — این فایل به‌طور خودکار توسط "
            "`00_Meta/Scripts/generate_vault_index.py` تولید می‌شود.\n\n"
            "> [!tip] نحوه به‌روزرسانی\n"
            "> این فهرست روی هر Pull Request به `dev`/`main` به‌صورت خودکار "
            "توسط GitHub Action (`.github/workflows/update-vault-index.yml`) "
            "بازسازی و در صورت نیاز کامیت می‌شود — نیازی به اجرای دستی نیست. "
            "در صورت تمایل به بررسی محلی پیش از باز کردن PR، می‌توانید از ریشه "
            "ریپازیتوری دستور `python3 00_Meta/Scripts/generate_vault_index.py` "
            "را هم دستی اجرا کنید (طبق قاعده ۱۸ در META-CONV-001). محتوای بین "
            "نشانه‌های زیر به‌طور خودکار بازنویسی می‌شود؛ متن خارج از آن‌ها "
            "دست‌نخورده می‌ماند.\n\n"
            "## ارجاعات\n"
            "- [[META-CONV-001 — قواعد توسعه پروژه|META-CONV-001]] — "
            "قاعده ۱۸ (فهرست و نقشه Vault)\n\n"
            "---\n\n"
            f"{START_MARKER}\n{END_MARKER}\n"
        )

    if START_MARKER not in current or END_MARKER not in current:
        print("ERROR: marker های AUTO-GENERATED در فایل یافت نشد.", file=sys.stderr)
        sys.exit(1)

    pre, rest = current.split(START_MARKER, 1)
    _, post = rest.split(END_MARKER, 1)
    new_content = pre + START_MARKER + "\n\n" + generated + "\n" + END_MARKER + post

    with open(INDEX_PATH, "w", encoding="utf-8") as fh:
        fh.write(new_content)
    print(f"{INDEX_PATH} به‌روزرسانی شد.")


if __name__ == "__main__":
    update_index_file()
