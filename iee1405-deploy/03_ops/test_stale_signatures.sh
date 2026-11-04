#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — آزمون نگهبان امضای توابع
#
#   bash 03_ops/test_stale_signatures.sh
#
# چه چیزی را ثابت می‌کند؟
#   اگر پایگاه نسخهٔ کهنهٔ یک تابع را داشته باشد (ستون‌های خروجی متفاوت)،
#   استقرار نباید با «cannot change return type» بیفتد؛ باید خودش نسخهٔ کهنه را
#   حذف و تابع را بازسازی کند.
#
# چطور؟ برای هر مورد: نسخهٔ کهنه را می‌سازد، همان فایل SQL را در **همان نشست**
# اجرا می‌کند و امضای تازه را می‌سنجد — همه داخل یک تراکنش و با ROLLBACK.
# هیچ چیزی در پایگاه نمی‌ماند.
#
# موارد:
#   S1  04_bot_logic.sql      · bot_dispatch_json سه‌ستونی  (باگ واقعی سرور)
#   S2  05_ops_helpers.sql    · pending_replies سه‌ستونی    (باگ واقعی سرور)
#   S3  08_exhibitor_mirror.sql · barghpa.search با ستون دیگر
#   S4  اجرای دوبارهٔ ۰۵ بدون نسخهٔ کهنه → هیچ حذفی نباید رخ دهد (بی‌اثر بودن)
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/03_ops/lib_common.sh"

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

dk_detect || { c_bad "docker پیدا نشد"; exit 1; }
ct_detect || { c_bad "کانتینر PostgreSQL بالا نیست"; exit 1; }
pg_user_detect >/dev/null 2>&1 || true

FAILS=0
pass() { c_ok "$1"; }
fail() { c_bad "$1"; FAILS=$((FAILS+1)); }

# اجرای یک فایل SQL داخل یک تراکنش، با یک «نسخهٔ کهنه» که قبلاً ساخته می‌شود.
#   $1 = برچسب  $2 = SQL نسخهٔ کهنه  $3 = فایل  $4 = کوئری سنجش  $5 = مقدار درست
case_run() {
    local label="$1" stale="$2" file="$3" probe="$4" want="$5"
    local out got
    out="$(
        {
            echo "BEGIN;"
            echo "$stale"
            cat "$HERE/$file"
            echo "SELECT '««RESULT»»' || ($probe);"
            echo "ROLLBACK;"
        } | pgq "$PG_DB" -v ON_ERROR_STOP=1 2>&1
    )"
    if grep -qiE "ERROR:|FATAL:" <<<"$out"; then
        fail "$label — استقرار با خطا ایستاد"
        grep -E "ERROR:|FATAL:" <<<"$out" | head -3 | sed 's/^/       /'
        return
    fi
    got="$(sed -n 's/.*««RESULT»»//p' <<<"$out" | tr -d '\r')"
    if [[ "$got" == "$want" ]]; then
        pass "$label"
    else
        fail "$label — امضا درست نشد"
        printf '       انتظار: %s\n       نتیجه : %s\n' "$want" "$got"
    fi
}

echo "════════════════════════════════════════════════"
echo " آزمون نگهبان امضای توابع"
echo "════════════════════════════════════════════════"

case_run "S1 · bot_dispatch_json سه‌ستونی — فایل ۰۴" \
    "DROP FUNCTION IF EXISTS iee1405.bot_dispatch_json(jsonb);
     CREATE FUNCTION iee1405.bot_dispatch_json(p_update jsonb)
       RETURNS TABLE (chat_id bigint, status text, reply_text text)
       LANGUAGE sql AS 'SELECT NULL::bigint, NULL::text, NULL::text';" \
    "01_sql/04_bot_logic.sql" \
    "pg_get_function_result('iee1405.bot_dispatch_json(jsonb)'::regprocedure)" \
    "TABLE(chat_id bigint, status text, reply_text text, org_code text)"

case_run "S2 · pending_replies سه‌ستونی — فایل ۰۵" \
    "DROP FUNCTION IF EXISTS iee1405.pending_replies(int);
     CREATE FUNCTION iee1405.pending_replies(p_limit int DEFAULT 20)
       RETURNS TABLE (update_id bigint, chat_id bigint, body text)
       LANGUAGE sql AS 'SELECT NULL::bigint, NULL::bigint, NULL::text';" \
    "01_sql/05_ops_helpers.sql" \
    "pg_get_function_result('iee1405.pending_replies(int)'::regprocedure)" \
    "TABLE(update_id bigint, chat_id bigint, text_body text, attempt integer)"

case_run "S3 · barghpa.search با ستون دیگر — فایل ۰۸" \
    "DROP FUNCTION IF EXISTS barghpa.search(text, int);
     CREATE FUNCTION barghpa.search(p_q text, p_limit int DEFAULT 8)
       RETURNS TABLE (company_id bigint, name_fa text, phone text)
       LANGUAGE sql AS 'SELECT NULL::bigint, NULL::text, NULL::text';" \
    "01_sql/08_exhibitor_mirror.sql" \
    "pg_get_function_result('barghpa.search(text, int)'::regprocedure)" \
    "TABLE(company_id bigint, name_fa text, halls text, contact_count integer, provenance text)"

# S4: بدون نسخهٔ کهنه، نگهبان نباید چیزی را حذف کند (بی‌اثر بودن در حالت عادی)
S4="$(
    { echo "BEGIN;"; cat "$HERE/01_sql/05_ops_helpers.sql"; echo "ROLLBACK;"; } \
        | pgq "$PG_DB" -v ON_ERROR_STOP=1 2>&1 | grep -c "امضای کهنه حذف شد"
)"
if [[ "${S4:-x}" == "0" ]]; then
    pass "S4 · اجرای بی‌کهنه هیچ تابعی را حذف نمی‌کند"
else
    fail "S4 · نگهبان در حالت عادی هم حذف می‌کند ($S4 مورد)"
fi

echo
if [[ $FAILS -eq 0 ]]; then
    c_ok "همهٔ موارد سبز است — نسخهٔ کهنه دیگر استقرار را نمی‌خواباند"
    exit 0
else
    c_bad "$FAILS مورد ناموفق"
    exit 1
fi
