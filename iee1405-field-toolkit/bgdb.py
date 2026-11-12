#!/usr/bin/env python3
"""هستهٔ مشترک ابزار بازدید: اتصال، مهاجرت نسخه‌دار، نرمال‌سازی فارسی.

قواعد:
  * migrations/*.sql به ترتیب عددی اجرا می‌شوند؛ هر کدام یک‌بار.
  * checksum هر مهاجرت ذخیره می‌شود؛ تغییر فایلِ اجراشده خطا می‌دهد
    (به‌جای مهاجرت خاموش).
  * pragma: foreign_keys=ON, journal_mode=DELETE (پوشه همگام‌شده)،
    synchronous=FULL (خواستهٔ L2-MKT-006 §۵).
"""
from __future__ import annotations

import hashlib
import re
import sqlite3
import unicodedata
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
MIGRATIONS = TOOL_DIR / "schema"

AR_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
ZERO_WIDTH = dict.fromkeys(map(ord, "\u200b\u200c\u200d\u200e\u200f\u202a\u202b"
                                    "\u202c\u202d\u202e\ufeff"), None)
ARABIC_MAP = {"ي": "ی", "ك": "ک", "ۀ": "ه", "ة": "ه",
              "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ؤ": "و", "ئ": "ی"}


def norm_text(s: str | None) -> str:
    """نرمال‌سازی برای تطبیق/جست‌وجو — هرگز روی دادهٔ اصلی اعمال نمی‌شود."""
    if not s:
        return ""
    s = unicodedata.normalize("NFC", str(s)).translate(AR_DIGITS).translate(ZERO_WIDTH)
    s = "".join(ARABIC_MAP.get(ch, ch) for ch in s)
    s = s.replace("\u0640", "")                       # کشیده
    s = re.sub(r"[\u064b-\u0652\u0670]", "", s)       # اعراب
    s = re.sub(r"[^\w\u0600-\u06FF]+", " ", s).lower()
    return re.sub(r"\s+", " ", s).strip()


PLACEHOLDER_TOKENS = {
    "-", "—", "–", "−", "_", ".", "...", "…", "?", "؟", "0",
    "ندارد", "نداریم", "یافت نشد", "یافت‌نشد", "پیدا نشد", "نامشخص", "نامعلوم",
    "خالی", "بدون", "هیچ", "هیچکدام", "هیچ کدام", "بدون اطلاعات",
    "اطلاعاتی نیست", "ثبت نشده", "در دسترس نیست", "موجود نیست",
    "n/a", "na", "none", "null", "nil", "nan", "false", "no", "unknown",
    "❌", "×", "✗", "✘",
}
_PH = {re.sub(r"\s+", " ", unicodedata.normalize("NFC", p).strip().lower())
       for p in PLACEHOLDER_TOKENS}


def is_real_cell(cell: str | None) -> bool:
    """«-» و «ندارد» و «یافت نشد» داده نیستند.

    این تابع از اجرای واقعی روی فایل نمایشگاه بیرون آمد: سلول خالی با «-»
    پر شده بود و شمردن آن به‌عنوان داده، «۲۹۷ شرکت دارای ایمیل» می‌ساخت.
    """
    v = re.sub(r"\s+", " ", unicodedata.normalize("NFC", str(cell or "")).strip().lower())
    if not v or v in _PH:
        return False
    return not set(v) <= set("-–—_ .\u200c")


def norm_booth(raw: str | None) -> tuple[str | None, str]:
    """موقعیت غرفه: مقدار خام همیشه نگه داشته می‌شود؛ ستون booth فقط اگر
    الگوی روشن «سالن-شماره» یا شمارهٔ تنها داشت پر می‌شود. هیچ حدسی زده نمی‌شود.
    """
    v = str(raw or "").translate(AR_DIGITS).strip()
    if not is_real_cell(v):
        return None, "خالی"
    compact = re.sub(r"\s+", "", v).upper()
    if re.fullmatch(r"\d{1,3}[A-Z]?-\d{1,3}", compact) or re.fullmatch(r"\d{1,4}", compact):
        return compact, "الگوی روشن"
    return None, "الگوی نامشخص — خام نگه داشته شد"


def norm_key(s: str | None) -> str:
    """کلید مقایسهٔ نام ستون‌ها: بدون فاصله و نویسه‌های نامرئی.

    اجرای واقعی نشان داد یک سرستون با نویسهٔ نامرئی متفاوت هرگز با نام
    جای‌گزین برابر نمی‌شد، در حالی که چشم آن را یکی می‌دید.
    """
    return re.sub(r"\s+", "", norm_text(s))


def norm_phone(s: str | None) -> str:
    """+98/0098 → 0، حذف جداکننده‌ها. ۰۲۱‑۸۸۷۷ → 0218877..."""
    if not s:
        return ""
    s = str(s).translate(AR_DIGITS)
    s = re.sub(r"[^\d+]", "", s)
    s = re.sub(r"^(\+98|0098|98)(?=\d)", "0", s)
    return s


def norm_email(s: str | None) -> str:
    return (s or "").strip().lower().replace(" ", "")


def norm_url(s: str | None) -> str:
    v = (s or "").strip().lower()
    v = re.sub(r"^https?://", "", v).rstrip("/")
    return re.sub(r"^www\.", "", v)


def phone_is_valid(v: str) -> bool:
    n = norm_phone(v)
    return 8 <= len(n) <= 13 and n.startswith("0") or (n.startswith("+") and 10 <= len(n) <= 15)


def connect(db_path: str | Path, *, readonly: bool = False) -> sqlite3.Connection:
    p = Path(db_path)
    if readonly:
        con = sqlite3.connect(f"file:{p}?mode=ro", uri=True)
    else:
        p.parent.mkdir(parents=True, exist_ok=True)
        con = sqlite3.connect(p)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys=ON")
    if not readonly:
        con.execute("PRAGMA journal_mode=DELETE")
        con.execute("PRAGMA synchronous=FULL")
    return con


def _checksum(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def migrate(con: sqlite3.Connection, *, verbose: bool = False) -> list[str]:
    """اجرای مهاجرت‌های اجرانشده. بازگشت: فهرست نسخه‌های تازه اجراشده."""
    con.execute("""CREATE TABLE IF NOT EXISTS schema_migrations (
        version   INTEGER PRIMARY KEY,
        name      TEXT NOT NULL,
        checksum  TEXT NOT NULL,
        applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
    )""")
    applied = {r["version"]: r for r in con.execute(
        "SELECT version, name, checksum FROM schema_migrations")}

    files = sorted(MIGRATIONS.glob("*.sql"))
    if not files:
        raise RuntimeError(f"هیچ مهاجرتی در {MIGRATIONS} نیست")
    done = []
    for f in files:
        m = re.match(r"(\d+)_", f.name)
        if not m:
            raise RuntimeError(f"نام مهاجرت باید با شماره شروع شود: {f.name}")
        ver = int(m.group(1))
        sql = f.read_text(encoding="utf-8")
        csum = _checksum(sql)
        if ver in applied:
            if applied[ver]["checksum"] != csum:
                raise RuntimeError(
                    f"مهاجرت {f.name} پس از اجرا تغییر کرده است — مهاجرت جدید بسازید")
            continue
        con.executescript(sql)
        con.execute("INSERT INTO schema_migrations(version, name, checksum) VALUES (?,?,?)",
                    (ver, f.name, csum))
        con.commit()
        done.append(f.name)
        if verbose:
            print(f"  ✅ مهاجرت {f.name} اجرا شد")
    highest = max(int(re.match(r"(\d+)", f.name).group(1)) for f in files)
    con.execute("PRAGMA user_version=%d" % highest)
    return done


def get_or_create(con: sqlite3.Connection, table: str, key: dict, values: dict) -> int:
    """درج اگر نبود، در غیر این صورت یافتن — بدون تغییر مقادیر موجود."""
    where = " AND ".join(f"{k}=?" for k in key)
    row = con.execute(f"SELECT id FROM {table} WHERE {where}",
                      tuple(key.values())).fetchone()
    if row:
        return row["id"]
    cols = ", ".join(list(key) + list(values))
    qs = ", ".join("?" * (len(key) + len(values)))
    cur = con.execute(f"INSERT INTO {table}({cols}) VALUES ({qs})",
                      tuple(list(key.values()) + list(values.values())))
    return cur.lastrowid


def backup(con: sqlite3.Connection, dest: str | Path) -> Path:
    """پشتیبان‌گیری امن از پایگاه باز، با API خود SQLite (نه cp)."""
    d = Path(dest)
    d.parent.mkdir(parents=True, exist_ok=True)
    out = sqlite3.connect(d)
    with out:
        con.backup(out)
    out.close()
    return d


def integrity(con: sqlite3.Connection) -> dict:
    return {
        "integrity_check": con.execute("PRAGMA integrity_check").fetchone()[0],
        "foreign_key_check": len(con.execute("PRAGMA foreign_key_check").fetchall()),
        "user_version": con.execute("PRAGMA user_version").fetchone()[0],
    }


def refresh_search(con: sqlite3.Connection, company_id: int) -> None:
    """بازسازی ستون جست‌وجو از متن اصلی (برگرفته از نام، لاتین، درباره، استان، سالن)."""
    row = con.execute("""SELECT c.name_fa, c.name_en, c.about_fa, c.province_label,
                                (SELECT group_concat(h.code,' ') FROM participation p
                                   JOIN hall h ON h.id=p.hall_id
                                  WHERE p.company_id=c.id) AS halls
                           FROM company c WHERE c.id=?""", (company_id,)).fetchone()
    if not row:
        return
    name_norm = norm_text(row["name_fa"])
    parts = [row["name_fa"], row["name_en"], row["about_fa"], row["province_label"],
             row["halls"], name_norm.replace(" ", "")]
    text_norm = norm_text(" ".join(str(p) for p in parts if p))
    con.execute("""INSERT INTO company_search(company_id, name_norm, text_norm)
                   VALUES (?,?,?)
                   ON CONFLICT(company_id) DO UPDATE SET
                     name_norm=excluded.name_norm, text_norm=excluded.text_norm""",
                (company_id, name_norm, text_norm))


def _fts_query(q: str) -> str:
    """پرس‌وجوی FTS5: هر واژه پیشوند می‌شود تا «ترانسف» → «ترانسفو» برسد."""
    toks = [t for t in norm_text(q).split() if len(t) > 1]
    return " AND ".join(f'"{t}"*' for t in toks)


def search(con: sqlite3.Connection, q: str, limit: int = 50) -> list[sqlite3.Row]:
    """جست‌وجوی فارسی در نام و متن نرمال‌شده، با توزین نام.

    نرمال‌سازی روی پرس‌وجو و روی ستون‌های *_norm اعمال می‌شود؛ متن اصلی
    دست‌نخورده می‌ماند. اگر FTS چیزی نداد، LIKE پشتیبان اجرا می‌شود.
    """
    expr = _fts_query(q)
    if not expr:
        return []
    sql = """SELECT c.id, c.name_fa, v.halls, v.priority,
                    bm25(company_fts, 5.0, 1.0) AS rank
               FROM company_fts f
               JOIN company_search s ON s.company_id = f.rowid
               JOIN company c ON c.id = s.company_id
               LEFT JOIN v_company_card v ON v.company_id = c.id
              WHERE company_fts MATCH ?
              ORDER BY rank, c.name_fa LIMIT ?"""
    try:
        rows = con.execute(sql, (expr, limit)).fetchall()
    except sqlite3.OperationalError:
        rows = []
    if rows:
        return rows
    like = f"%{norm_text(q)}%"
    return con.execute("""SELECT c.id, c.name_fa, v.halls, v.priority, 0.0 AS rank
                            FROM company_search s JOIN company c ON c.id=s.company_id
                            LEFT JOIN v_company_card v ON v.company_id=c.id
                           WHERE s.name_norm LIKE ? OR s.text_norm LIKE ?
                           ORDER BY c.name_fa LIMIT ?""", (like, like, limit)).fetchall()


def classify_provenance(text: str | None) -> str:
    """طبقه‌بندی «منبع تکمیل اطلاعات» به یک برچسب قابل تصمیم.

    official  : خودِ منبع می‌گوید از سایت رسمی شرکت آمده
    guessed   : «حدس دامنه» — دامنه با نام شرکت تطبیق داده شده، تأیید نشده
    portal    : فقط از پورتال برق‌پا
    web_search: جست‌وجوی وب/گوگل
    other/unknown
    """
    n = norm_text(text)
    if not n:
        return "unknown"
    if "حدس" in n:
        return "guessed"
    # «فقط از پورتال‌ها (بدون سایت رسمی تأییدشده)» یعنی عکسِ «سایت رسمی»
    if "پورتال" in n or "بدون سایت" in n:
        return "portal"
    if "سایت" in n or "رسمی" in n:
        return "official"
    if "جستجو" in n or "گوگل" in n or "وب" in n:
        return "web_search"
    return "other"


STOP_TOKENS = {"شرکت", "گروه", "صنایع", "صنعتی", "بازرگانی", "خدمات", "توسعه",
               "مهندسی", "پس", "از", "فروش", "های", "ها", "و"}


def name_tokens(name: str | None) -> set[str]:
    """واژه‌های معنادار نام شرکت، برای تشخیص «خانواده» (مثل ایران ترانسفو)."""
    s = re.sub(r"[()\[\]«»]", " ", str(name or ""))
    return {w for w in norm_text(s).split() if len(w) > 2 and w not in STOP_TOKENS}


def same_family(a: str | None, b: str | None, min_shared: int = 2,
                ignore: set[str] | None = None) -> bool:
    """آیا دو نام از یک خانواده‌اند؟ `ignore` واژه‌هایی است که در استخر عمومی‌اند.

    بدون `ignore`، دو شرکت بی‌ربط که هر دو «برق» و «صنعت» در نامشان دارند
    هم‌خانواده شمرده می‌شوند و `--max-group` فهرست را بی‌دلیل کوتاه می‌کند.
    """
    shared = name_tokens(a) & name_tokens(b)
    if ignore:
        shared -= ignore
    return len(shared) >= min_shared


def common_tokens(names, share: float = 0.08, floor: int = 3) -> set[str]:
    """واژه‌هایی که در بیش از `share` از نام‌ها تکرار شده‌اند (نه واژهٔ هویتی)."""
    freq: dict[str, int] = {}
    for n in names:
        for w in name_tokens(n):
            freq[w] = freq.get(w, 0) + 1
    line = max(floor, int(len(list(names)) * share))
    return {w for w, c in freq.items() if c >= line}
