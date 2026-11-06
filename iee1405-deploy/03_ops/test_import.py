#!/usr/bin/env python3
"""آزمون خودکار زنجیره «اکسل → CSV → دیتابیس».

  python3 03_ops/test_import.py

چه چیزی را می‌سنجد:
  ۱) خواندن xlsx با کتابخانه استاندارد (بدون openpyxl) و ساختن CSV
  ۲) تشخیص ستون‌ها از سرستون‌های فارسی، با نام‌های متفاوت در هر شیت
  ۳) یکتایی: اجرای دوباره شرکت تکراری نمی‌سازد
  ۴) یکسان‌سازی نام: نیم‌فاصله/فاصله و ی/ک عربی، یک شرکت حساب می‌شوند
  ۵) پیش‌نمایش (بدون --write) چیزی نمی‌نویسد
  ۶) وب‌سایت تکراری، ایمپورت را نمی‌شکند
"""
from __future__ import annotations

import csv
import html
import os
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
import pgserver

_BIN_CANDIDATES = [
    Path(os.environ["PG_BIN"]) if os.environ.get("PG_BIN") else None,
    Path("/usr/local/lib/python3.11/dist-packages/pgserver/pginstall/bin"),
    Path(pgserver.__file__).resolve().parent / "pginstall" / "bin",
]
BIN = next((b for b in _BIN_CANDIDATES if b and (b / "psql").exists()),
           _BIN_CANDIDATES[1])
PASS, FAIL = [], []


def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(f"{'✅' if cond else '❌'} {name}" + (f"   [{detail}]" if detail else ""))


def psql(sql: str) -> str:
    import pgserver  # noqa: F401  (برای get_server)
    srv = pgserver.get_server("/tmp/pgdata", cleanup_mode=None)
    base = srv.get_uri()
    uri = None
    for db in ("xennic", "postgres"):
        cand = base.replace("/postgres?", f"/{db}?")
        p = subprocess.run([str(BIN / "psql"), cand, "-X", "-t", "-A", "-c",
                            "SELECT to_regclass('iee1405.bot_state') IS NOT NULL"],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if p.stdout.decode().strip() == "t":
            uri = cand
            break
    p = subprocess.run([str(BIN / "psql"), uri, "-X", "-t", "-A", "-v", "ON_ERROR_STOP=1"],
                       input=sql.encode(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = p.stdout.decode().strip()
    # خطای SQL نباید بی‌صدا رد شود (وگرنه آزمون سبز می‌شود و دیتابیس دست‌نخورده)
    if p.returncode != 0 and "ERROR" in out:
        if sql.lstrip().upper().startswith("DELETE") or sql.lstrip().startswith("DO"):
            return out          # پاک‌سازی ممکن است به قید بربخورد؛ خودِ آزمون نسبی است
        raise RuntimeError(f"SQL failed: {sql[:120]}\n{out[:400]}")
    return out


def make_xlsx(path: Path):
    """xlsx آزمایشی با ۴ شیت، سرستون‌های متفاوت و نیم‌فاصله."""
    def c(ref, val):
        return f'<c r="{ref}" t="inlineStr"><is><t>{html.escape(val)}</t></is></c>'

    sheets = {
        "شرکت‌ها": (["ردیف", "نام شرکت", "سالن", "غرفه", "دسته‌بندی", "تلفن", "وب‌سایت"],
                    [["1", "شرکت برق‌آوران پارس", "38", "38-12", "تابلو MV", "021-111", "pars.co"],
                     ["2", "نیرو ترانسفو", "40", "40-A5", "ترانسفورماتور", "021-222", ""]]),
        "تولیدکنندگان": (["نام", "زمینه فعالیت"],
                         [["کابل ابهر", "کابل و هادی"], ["صنایع مس", "مس و هادی"]]),
        "دسته‌بندی": (["گروه", "تعداد"], [["ترانسفورماتور", "24"]]),
        "راهنما": (["توضیح"], [["فایل آزمایشی"]]),
    }
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("[Content_Types].xml",
                   '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>')
        z.writestr("xl/_rels/workbook.xml.rels",
                   '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   + "".join(f'<Relationship Id="rId{i}" Type="worksheet" Target="worksheets/sheet{i}.xml"/>'
                             for i in range(1, len(sheets) + 1)) + "</Relationships>")
        z.writestr("xl/workbook.xml",
                   '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                   'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
                   + "".join(f'<sheet name="{n}" sheetId="{i}" r:id="rId{i}"/>'
                             for i, n in enumerate(sheets, 1)) + "</sheets></workbook>")
        for i, (name, (hdr, body)) in enumerate(sheets.items(), 1):
            rows = ['<row r="1">' + "".join(c(f"{chr(65+j)}1", h) for j, h in enumerate(hdr)) + "</row>"]
            for r, vals in enumerate(body, start=2):
                rows.append(f'<row r="{r}">' + "".join(
                    c(f"{chr(65+j)}{r}", v) for j, v in enumerate(vals) if v) + "</row>")
            z.writestr(f"xl/worksheets/sheet{i}.xml",
                       '<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
                       "<sheetData>" + "".join(rows) + "</sheetData></worksheet>")


def stub_docker(dir_path: Path) -> Path:
    """docker قلابی: psql را به خوشه آزمون وصل می‌کند (خارج از محیط تولید)."""
    stub = dir_path / "docker"
    stub.write_text(f"""#!/usr/bin/env bash
PSQL={BIN / 'psql'}
case "$1" in
  info) echo ok; exit 0 ;;
  ps) printf 'xennic-infra-postgres-1\\tpostgres\\n'; exit 0 ;;
  exec)
    shift
    while [[ "${{1:-}}" == -* ]]; do [[ "$1" == "-e" ]] && shift 2 || shift; done
    shift                                     # container
    if [[ "$1" == "printenv" ]]; then echo postgres; exit 0; fi
    if [[ "$1" == "psql" ]]; then export PGHOST=/tmp/pgdata PGUSER=postgres; shift; exec "$PSQL" "$@"; fi
    exit 0 ;;
esac
exit 1
""")
    stub.chmod(0o755)
    return stub


def run(cmd, env_extra=None):
    env = dict(os.environ)
    env.update(env_extra or {})
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, text=True)


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="iee-import-test-"))
    stub = stub_docker(tmp)
    env = {"PATH": f"{tmp}:{os.environ['PATH']}"}

    xlsx = tmp / "test.xlsx"
    make_xlsx(xlsx)
    conv = run([sys.executable, str(HERE / "xlsx_to_csv.py"), str(xlsx), "--out", str(tmp / "csv")])
    check("xlsx با کتابخانه استاندارد خوانده شد", conv.returncode == 0 and "4 شیت" in conv.stdout,
          conv.stdout.splitlines()[0] if conv.stdout else "")
    check("چهار CSV ساخته شد", len(list((tmp / "csv").glob("sheet-*.csv"))) == 4)

    with (tmp / "csv" / "sheet-01.csv").open(encoding="utf-8") as f:
        header = next(csv.reader(f))
    check("نیم‌فاصله در CSV حفظ شد", "شرکت برق‌آوران پارس" in (tmp / "csv" / "sheet-01.csv").read_text(encoding="utf-8"))
    check("سرستون‌های فارسی درست خوانده شدند", header[1] == "نام شرکت", header[1])

    # پاک‌سازی کامل ردیف‌های آزمون (مستقل از اجراهای قبلی)
    cleanup = """
DO $$
DECLARE v_names text[] := ARRAY['شرکت برق‌آوران پارس','شرکت برق آوران پارس',
                                'نیرو ترانسفو','نيرو ترانسفو','کابل ابهر','صنایع مس',
                                'شرکت تازه با سایت تکراری'];
BEGIN
    -- مقایسه با name_norm (نه legal_name) تا نیم‌فاصله/ی عربی هم بگیرد
    DELETE FROM iee1405.participations
     WHERE organization_id IN (
        SELECT id FROM crm.organizations
         WHERE name_norm IN (SELECT crm.norm_text(x) FROM unnest(v_names) x)
            OR created_by = 'import-exhibitors');
    DELETE FROM crm.organizations
     WHERE name_norm IN (SELECT crm.norm_text(x) FROM unnest(v_names) x)
        OR created_by = 'import-exhibitors';
END $$;
"""
    psql(cleanup)

    before = psql("SELECT count(*) FROM crm.organizations")
    dry = run([sys.executable, str(HERE / "import_exhibitors.py"),
               str(tmp / "csv" / "sheet-01.csv"), "--dry-run"], env)
    after_dry = psql("SELECT count(*) FROM crm.organizations")
    check("پیش‌نمایش چیزی نمی‌نویسد", before == after_dry, f"{before} → {after_dry}")
    import re as _re0
    n_new = int(_re0.search(r"شرکت تازه\s*:\s*(\d+)", dry.stdout).group(1))
    n_upd = int(_re0.search(r"به‌روزرسانی\s*:\s*(\d+)", dry.stdout).group(1))
    check("پیش‌نمایش همه ردیف‌ها را می‌بیند (تازه + به‌روزرسانی)",
          n_new + n_upd == 2, f"تازه {n_new} · به‌روزرسانی {n_upd}")
    check("پیش‌نمایش هر دو شرکت را نام می‌برد",
          "برق" in dry.stdout and "نیرو ترانسفو" in dry.stdout)
    check("پیش‌نمایش دسته را درست تشخیص می‌دهد", "TAB_MV" in dry.stdout and "TRF/B" in dry.stdout)

    # تعداد شرکت تازه‌ای که پیش‌نمایش اعلام کرد
    import re as _re
    declared = int(_re.search(r"شرکت تازه\s*:\s*(\d+)", dry.stdout).group(1))

    w1 = run([sys.executable, str(HERE / "import_exhibitors.py"),
              str(tmp / "csv" / "sheet-01.csv"), "--write"], env)
    n1 = int(psql("SELECT count(*) FROM crm.organizations"))
    check("تعداد درج‌شده همان است که پیش‌نمایش گفت", n1 - int(before) == declared and w1.returncode == 0,
          f"اعلام {declared} · واقعی {n1 - int(before)}")

    # اجرای دوباره: هیچ شرکت تازه‌ای نباید ساخته شود
    run([sys.executable, str(HERE / "import_exhibitors.py"),
         str(tmp / "csv" / "sheet-01.csv"), "--write"], env)
    n2 = int(psql("SELECT count(*) FROM crm.organizations"))
    check("اجرای دوباره شرکت تکراری نمی‌سازد", n2 == n1, f"{n1} → {n2}")

    # همان نام با فاصله به‌جای نیم‌فاصله + ی/ک عربی
    dup = tmp / "dup.csv"
    dup.write_text("نام شرکت,غرفه,دسته\nشرکت برق آوران پارس,38-12,تابلو\nنيرو ترانسفو,40-A5,ترانس\n",
                   encoding="utf-8")
    before_dup = int(psql("SELECT count(*) FROM crm.organizations"))
    run([sys.executable, str(HERE / "import_exhibitors.py"), str(dup), "--write"], env)
    after_dup = int(psql("SELECT count(*) FROM crm.organizations"))
    check("نیم‌فاصله و ی/ک عربی، شرکت تکراری نمی‌سازند", after_dup == before_dup,
          f"{before_dup} → {after_dup}")

    # غرفه تجزیه شد؟
    parts = psql("SELECT count(*) FROM iee1405.participations p "
                 "JOIN crm.organizations o ON o.id = p.organization_id "
                 "WHERE p.hall IS NOT NULL AND o.name_norm IN "
                 "(SELECT crm.norm_text(x) FROM unnest(ARRAY['شرکت برق‌آوران پارس','نیرو ترانسفو']) x)")
    check("غرفه «سالن-شماره» تجزیه شد", int(parts or 0) >= 2, parts)

    # وب‌سایت تکراری نباید کل ایمپورت را بشکند
    clash = tmp / "clash.csv"
    clash.write_text("نام شرکت,وب‌سایت\nشرکت تازه با سایت تکراری,pars.co\n", encoding="utf-8")
    r = run([sys.executable, str(HERE / "import_exhibitors.py"), str(clash), "--write"], env)
    ok = r.returncode == 0
    check("وب‌سایت تکراری ایمپورت را نمی‌شکند", ok,
          r.stdout.strip().splitlines()[-1] if r.stdout else "")

    psql("DELETE FROM iee1405.participations WHERE organization_id IN "
         "(SELECT id FROM crm.organizations WHERE created_by = 'import-exhibitors');")
    psql("DELETE FROM crm.organizations WHERE created_by = 'import-exhibitors';")

    print(f"\n{len(PASS)} موفق · {len(FAIL)} ناموفق")
    if FAIL:
        print("ناموفق‌ها: " + ", ".join(FAIL))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
