#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — بارگذاری فهرست نمایشگاه در PostgreSQL تا ربات بله بخواند
#
# اجرا روی VPS (از مسیر iee1405-deploy):
#   bash 03_ops/load_exhibitors.sh              # ساخت آینه + بارگذاری داده
#   bash 03_ops/load_exhibitors.sh --check      # فقط بازبینی، بدون تغییر
#   bash 03_ops/load_exhibitors.sh --dry-run    # فایل SQL ساخته شود، اجرا نشود
#
# چه می‌کند:
#   ۱) از پایگاه SQLite تأییدشده (۲۹۷/۴۹۷/۳۰۰) یک فایل SQL می‌سازد
#   ۲) اسکیمای آینهٔ `barghpa` را می‌سازد (بدون دست‌زدن به CRM)
#   ۳) فایل را داخل کانتینر PostgreSQL اجرا می‌کند
#   ۴) با `barghpa.selftest()` عددها را با آخرین بارگذاری تطبیق می‌دهد
#
# چه نمی‌کند: هیچ ردیفی در crm.organizations نمی‌نویسد. شرکت نمایشگاه «مشتری»
# نیست (تصمیم R5 در L2-MKT-006)؛ آینه با `DROP SCHEMA barghpa CASCADE` پاک می‌شود.
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/03_ops/lib_common.sh"

# ── حالت آزمایشی/بدون کانتینر ─────────────────────────────────────────
# اگر PG_DIRECT_PSQL داده شود (مثلاً هنگام آزمون روی یک خوشهٔ محلی)، به‌جای
# «docker exec» همان psql مستقیم صدا زده می‌شود. روی سرور لازم نیست.
if [[ -n "${PG_DIRECT_PSQL:-}" ]]; then
    dk_detect() { return 0; }
    ct_detect() { return 0; }
    pg_user_detect() { return 0; }
    PG_CT="(مستقیم)"; PG_USER="${PG_USER:-postgres}"
    pgq()          { local db="$1"; shift; $PG_DIRECT_PSQL -X -t -A -d "$db" "$@"; }
    pgq_pretty()   { local db="$1"; shift; $PG_DIRECT_PSQL -X -P pager=off -d "$db" "$@"; }
    pg_db_exists() { [[ -n "$($PG_DIRECT_PSQL -X -t -A -d postgres \
                        -c "SELECT 1 FROM pg_database WHERE datname='$1'")" ]]; }
fi

MODE="load"
case "${1:-}" in
    --check)   MODE="check" ;;
    --dry-run) MODE="dry" ;;
    "")        MODE="load" ;;
    *)         c_bad "گزینهٔ ناشناخته: $1"; c_hint "استفاده: bash 03_ops/load_exhibitors.sh [--check|--dry-run]"; exit 2 ;;
esac

SQLITE="${SQLITE_DB:-$HOME/xennic-data/barghpa-26-iee1405/db/barghpa_iee1405.sqlite}"
OUT_SQL="${OUT_SQL:-$HOME/xennic-data/barghpa-26-iee1405/exports/barghpa_load.sql}"

# ابزار صدور: کپی سرور، وگرنه نسخهٔ مخزن
EXPORTER="${EXPORTER:-}"
if [[ -z "$EXPORTER" ]]; then
    for cand in "$HOME/xennic-data/barghpa-26-iee1405/tools/export_to_pg.py" \
                "$HERE/../iee1405-field-toolkit/export_to_pg.py"; do
        [[ -f "$cand" ]] && { EXPORTER="$cand"; break; }
    done
fi

echo "════════════════════════════════════════════════"
echo " آینهٔ فهرست نمایشگاه → PostgreSQL"
echo " SQLite: $SQLITE"
echo " حالت:   $MODE"
echo "════════════════════════════════════════════════"

if ! dk_detect; then
    c_bad "Docker یا دسترسی به آن موجود نیست"
    c_hint "این اسکریپت روی سرور و با دسترسی docker اجرا می‌شود."
    exit 1
fi
if ! ct_detect; then
    c_bad "کانتینر PostgreSQL پیدا نشد"
    c_hint "docker ps را ببینید؛ یا PG_CONTAINER=<name> bash 03_ops/load_exhibitors.sh"
    exit 1
fi
if ! pg_user_detect; then
    c_bad "اتصال به PostgreSQL برقرار نشد (کاربر: ${PG_USER:-؟})"
    exit 1
fi
if ! pg_db_exists "$PG_DB"; then
    c_bad "دیتابیس «$PG_DB» وجود ندارد"
    c_hint "اول ساختار را مستقر کنید: bash 03_ops/deploy_sql.sh"
    exit 1
fi
echo "→ کانتینر: $PG_CT · کاربر: $PG_USER · دیتابیس: $PG_DB"

# ── ۱) بازبینی: هیچ نوشتنی ─────────────────────────────────────────────
if [[ "$MODE" == "check" ]]; then
    echo
    echo "→ بازبینی آینه (barghpa.selftest)"
    pgq_pretty "$PG_DB" -c "SELECT * FROM barghpa.selftest();" 2>/dev/null \
        || { c_bad "تابع selftest موجود نیست"; c_hint "bash 03_ops/deploy_sql.sh  (فایل 08 را هم اجرا می‌کند)"; exit 1; }
    echo
    echo "→ آمار آینه"
    pgq_pretty "$PG_DB" -c "SELECT barghpa.stats_text();"
    echo
    echo "→ نمونهٔ پاسخ ربات برای «/c»"
    pgq_pretty "$PG_DB" -c "SELECT barghpa.bot_reply('') AS reply;"
    if [[ -f "$SQLITE" ]]; then
        local_c=$(python3 - "$SQLITE" <<'PY' 2>/dev/null || echo "?"
import sqlite3, sys
c = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
print(c.execute("SELECT count(*) FROM company").fetchone()[0])
PY
)
        mirror_c=$(pgq "$PG_DB" -c "SELECT count(*) FROM barghpa.company" 2>/dev/null | tr -d '[:space:]')
        echo
        printf "  مقایسه: SQLite=%s · آینه=%s\n" "${local_c:-?}" "${mirror_c:-?}"
        if [[ "${local_c:-x}" == "${mirror_c:-y}" ]]; then
            c_ok "شمار شرکت‌ها با هم می‌خواند"
        else
            c_warn "شمار شرکت‌ها نمی‌خواند — بارگذاری را تکرار کنید: bash 03_ops/load_exhibitors.sh"
        fi
    fi
    exit 0
fi

# ── ۲) ساخت فایل SQL از SQLite ─────────────────────────────────────────
if [[ ! -f "$SQLITE" ]]; then
    c_bad "پایگاه SQLite پیدا نشد: $SQLITE"
    c_hint "SQLITE_DB=/مسیر/دیگر.sqlite bash 03_ops/load_exhibitors.sh"
    exit 1
fi
if [[ -z "$EXPORTER" || ! -f "$EXPORTER" ]]; then
    c_bad "script صدور پیدا نشد (export_to_pg.py)"
    c_hint "آن را از مخزن بگیرید: iee1405-field-toolkit/export_to_pg.py → ~/xennic-data/barghpa-26-iee1405/tools/"
    exit 1
fi

echo
echo "→ ساخت فایل SQL از SQLite"
mkdir -p "$(dirname "$OUT_SQL")"
if ! python3 "$EXPORTER" --db "$SQLITE" --out "$OUT_SQL" --manifest "$OUT_SQL.manifest.json"; then
    c_bad "صدور ناموفق بود؛ ادامه داده نشد"
    exit 1
fi
c_ok "فایل ساخته شد: $OUT_SQL"

if [[ "$MODE" == "dry" ]]; then
    c_hint "حالت --dry-run: هیچ چیزی در پایگاه اجرا نشد."
    c_hint "برای اجرا: bash 03_ops/load_exhibitors.sh"
    exit 0
fi

# ── ۳) پشتیبان + اجرا ──────────────────────────────────────────────────
echo
echo "→ پشتیبان پیش از بارگذاری"
if [[ -n "${PG_DIRECT_PSQL:-}" ]]; then
    c_hint "حالت مستقیم: پشتیبان‌گیری کانتینری رد شد (آینه از SQLite بازسازی‌شدنی است)"
elif bash "$HERE/03_ops/backup_now.sh" >/dev/null 2>&1; then
    c_ok "پشتیبان گرفته شد"
else
    c_warn "پشتیبان نگرفته شد (ادامه می‌دهیم؛ آینه قابل بازسازی از SQLite است)"
fi

echo "→ اجرای اسکیمای آینه (08_exhibitor_mirror.sql)"
if pgq "$PG_DB" -v ON_ERROR_STOP=1 -f - < "$HERE/01_sql/08_exhibitor_mirror.sql" >/tmp/iee_exh_schema.log 2>&1; then
    c_ok "اسکیمای barghpa آماده است"
else
    c_bad "اجرای اسکیما ناموفق بود"
    grep -m5 ERROR /tmp/iee_exh_schema.log | sed 's/^/     /'
    exit 1
fi

echo "→ بارگذاری داده (تراکنشی؛ در صورت خطا هیچ چیزی نوشته نمی‌شود)"
if pgq "$PG_DB" -v ON_ERROR_STOP=1 -f - < "$OUT_SQL" >/tmp/iee_exh_load.log 2>&1; then
    c_ok "بارگذاری انجام شد"
else
    c_bad "بارگذاری ناموفق بود"
    grep -m5 ERROR /tmp/iee_exh_load.log | sed 's/^/     /'
    exit 1
fi

# ── ۴) تطبیق عددها ─────────────────────────────────────────────────────
echo
echo "→ بازبینی پس از بارگذاری"
pgq_pretty "$PG_DB" -c "SELECT * FROM barghpa.selftest();"
echo
pgq_pretty "$PG_DB" -c "SELECT barghpa.stats_text();"

bad=$(pgq "$PG_DB" -c "SELECT count(*) FROM barghpa.selftest() WHERE NOT ok" | tr -d '[:space:]')
echo
if [[ "${bad:-1}" == "0" ]]; then
    c_ok "همهٔ بازبینی‌ها سبز است"
    echo
    c_hint "در بله امتحان کنید:  /c   ·   /c 38B   ·   /c نام شرکت"
    exit 0
fi
c_bad "$bad بازبینی ناموفق است (بالا را ببینید)"
exit 1
