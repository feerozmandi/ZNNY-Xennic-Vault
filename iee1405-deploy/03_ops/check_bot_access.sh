#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — بازبینی دسترسی ربات بله به آینهٔ فهرست نمایشگاه (barghpa)
#
# اجرا روی VPS (از مسیر iee1405-deploy):
#   bash 03_ops/check_bot_access.sh            # فقط‌خواندنی: گرنت‌ها + پاسخ /c
#   bash 03_ops/check_bot_access.sh --full     # + مسیر کامل ربات (bot_dispatch_json)
#
# چرا این فایل هست: گرنت‌های آینه اگر **پیش از** ساخته‌شدن نقش اجرا شوند
# بی‌صدا رد می‌شوند (نقش وجود ندارد) و نتیجه‌اش فقط در بله دیده می‌شود:
#   ERROR: permission denied for schema barghpa
# این بررسی همان‌جا جلوی تحویل را می‌گیرد.
#
# چه چیزی را سبز می‌شمارد:
#   ۱) نقش iee_app روی اسکیمای barghpa دسترسی USAGE دارد
#   ۲) همهٔ شش جدول آینه برای iee_app خواندنی‌اند
#   ۳) همهٔ توابع آینه برای iee_app اجراشدنی‌اند (bot_reply, selftest, …)
#   ۴) iee_app نمی‌تواند در آینه بنویسد (فقط‌خواندنی بودن واقعاً برقرار است)
#   ۵) selftest وقتی با نقش ربات اجرا می‌شود همه سبز است
#   ۶) barghpa.bot_reply('') با نقش ربات خلاصهٔ غیرخالی می‌دهد
#   ۷) CRM دست‌نخورده است (شمار سازمان‌ها گزارش می‌شود)
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/03_ops/lib_common.sh"

# ── حالت آزمایشی/بدون کانتینر ─────────────────────────────────────────
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

FULL=0
case "${1:-}" in
    "")       FULL=0 ;;
    --full)   FULL=1 ;;
    *)        c_bad "گزینهٔ ناشناخته: $1"; c_hint "استفاده: bash 03_ops/check_bot_access.sh [--full]"; exit 2 ;;
esac

echo "════════════════════════════════════════════════"
echo " بازبینی دسترسی ربات به آینهٔ نمایشگاه"
echo "════════════════════════════════════════════════"

dk_detect || { c_bad "docker پیدا نشد"; exit 1; }
ct_detect || { c_bad "کانتینر PostgreSQL بالا نیست"; exit 1; }
pg_user_detect || true

# pgq در lib_common منتظر ‎-c‎ است؛ این میان‌بر فقط SQL می‌گیرد
q() { pgq "$PG_DB" -c "$1"; }

FAILS=0
pass() { c_ok "$1"; }
fail() { c_bad "$1"; [[ $# -gt 1 ]] && c_hint "$2"; FAILS=$((FAILS+1)); }

# ── ۰) پیش‌نیازها ─────────────────────────────────────────────────────
c_head "۰) پیش‌نیازها"

if [[ "$(q "SELECT to_regclass('barghpa.company') IS NOT NULL")" == "t" ]]; then
    pass "اسکیمای آینه موجود است"
else
    fail "اسکیمای barghpa ساخته نشده" "bash 03_ops/deploy_sql.sh && bash 03_ops/load_exhibitors.sh"
    echo
    c_bad "بازبینی بی‌معناست؛ اول آینه را بسازید."
    exit 1
fi

if [[ "$(q "SELECT count(*) FROM pg_roles WHERE rolname='iee_app'")" == "1" ]]; then
    pass "نقش iee_app موجود است"
else
    fail "نقش iee_app ساخته نشده" "PG_APP_PASSWORD=… bash 03_ops/deploy_sql.sh  (فایل ۰۶)"
    exit 1
fi

ROWS="$(q "SELECT count(*) FROM barghpa.company")"
if [[ "${ROWS:-0}" -gt 0 ]]; then
    pass "آینه داده دارد: $ROWS شرکت"
else
    fail "آینه خالی است" "bash 03_ops/load_exhibitors.sh"
fi

# ── ۱) گرنت‌های نقش ربات ──────────────────────────────────────────────
c_head "۱) گرنت‌های iee_app"

chk_priv() {  # $1=label  $2=SQL برمی‌گرداند t/f  $3=راه رفع
    if [[ "$(q "$2")" == "t" ]]; then pass "$1"; else fail "$1" "$3"; fi
}

chk_priv "USAGE روی اسکیمای barghpa" \
    "SELECT has_schema_privilege('iee_app','barghpa','USAGE')" \
    "bash 03_ops/deploy_sql.sh   (گرنت آینه در 06_roles.sql است؛ فایل ۰۸ پیش از ساخت نقش اجرا می‌شود)"

for t in company contact participation company_flag pilot load_batch; do
    chk_priv "SELECT روی barghpa.$t" \
        "SELECT has_table_privilege('iee_app','barghpa.$t','SELECT')" \
        "bash 03_ops/deploy_sql.sh"
done

# توابع: با شناسهٔ pg_proc بررسی می‌شوند تا به امضای دقیق وابسته نباشیم
for f in bot_reply selftest stats_text search card by_hall conf_label fa_digits; do
    chk_priv "EXECUTE روی barghpa.$f()" \
        "SELECT coalesce((SELECT bool_and(has_function_privilege('iee_app', p.oid, 'EXECUTE'))
                           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                          WHERE n.nspname = 'barghpa' AND p.proname = '$f'), false)" \
        "bash 03_ops/deploy_sql.sh"
done

# ── ۲) فقط‌خواندنی بودن (نباید بتواند بنویسد) ─────────────────────────
c_head "۲) آینه فقط‌خواندنی است"

# INSERT با شناسهٔ منفی: اگر دسترسی اشتباهاً داده شده باشد، همین ردیف پیدا می‌شود.
W_OUT="$(q "SET ROLE iee_app;
    INSERT INTO barghpa.company (id, name_fa, name_norm)
    VALUES (-999999, 'آزمون دسترسی', 'آزمون دسترسی');
    RESET ROLE;
    SELECT count(*) FROM barghpa.company WHERE id = -999999;" 2>&1)"

if [[ "$W_OUT" == *"permission denied"* ]]; then
    pass "INSERT با نقش ربات رد می‌شود (همان‌طور که باید)"
elif [[ "$W_OUT" == *"0"* ]]; then
    fail "نقش ربات می‌تواند در آینه بنویسد" "GRANT بیش از حد؛ REVOKE INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA barghpa FROM iee_app"
    q "DELETE FROM barghpa.company WHERE id = -999999" >/dev/null 2>&1 || true
else
    fail "نتیجهٔ آزمون نوشتن روشن نبود" "$W_OUT"
fi

# ── ۳) توابع با نقش ربات ─────────────────────────────────────────────
c_head "۳) پاسخ توابع با نقش iee_app"

ST="$(q "SET ROLE iee_app; SELECT count(*) || '/' || count(*) FILTER (WHERE ok) FROM barghpa.selftest();" 2>&1 | tail -1)"
if [[ "$ST" == "9/9" ]]; then
    pass "selftest با نقش ربات: ۹ از ۹ سبز"
else
    fail "selftest با نقش ربات سبز نیست: $ST" "psql -c \"SET ROLE iee_app; SELECT * FROM barghpa.selftest();\""
fi

REPLY="$(q "SET ROLE iee_app; SELECT barghpa.bot_reply('');" 2>&1)"
if [[ "$REPLY" == *"آینه"* && "$REPLY" == *"شرکت:"* ]]; then
    pass "barghpa.bot_reply('') با نقش ربات خلاصهٔ آینه را داد"
    echo "$REPLY" | sed -n '2,5p' | sed 's/^/       /'
elif [[ "$REPLY" == *"permission denied"* ]]; then
    fail "bot_reply با نقش ربات «permission denied» داد" "bash 03_ops/deploy_sql.sh   (گرنت USAGE/EXECUTE آینه در 06_roles.sql)"
else
    fail "bot_reply پاسخ مورد انتظار را نداد: $REPLY"
fi

HALL="$(q "SET ROLE iee_app; SELECT barghpa.bot_reply('38B');" 2>&1)"
if [[ "$HALL" == *"سالن"* ]]; then
    pass "پرس‌وجوی سالن با نقش ربات کار می‌کند"
else
    fail "پرس‌وجوی سالن کار نکرد: $HALL"
fi

# ── ۴) مسیر کامل ربات (اختیاری) ───────────────────────────────────────
if [[ $FULL -eq 1 ]]; then
    c_head "۴) مسیر کامل ربات (bot_dispatch_json)"

    CHAT="$(q "SELECT coalesce((SELECT bale_chat_id FROM crm.users
                             WHERE bale_chat_id IS NOT NULL AND is_active
                             ORDER BY id LIMIT 1), 0)")"
    if [[ "${CHAT:-0}" == "0" ]]; then
        c_warn "هیچ کاربر مجاز بله ثبت نشده؛ آزمون مسیر کامل رد شد"
        c_hint "کاربر را اضافه کنید، یا در بله /start بزنید و شناسه را ثبت کنید"
    else
        UPD=$(( $(date +%s) * 10 + RANDOM % 10 ))
        D_OUT="$(q "SET ROLE iee_app;
            SELECT (iee1405.bot_dispatch_json(jsonb_build_object(
                       'update_id', $UPD,
                       'message', jsonb_build_object(
                           'chat', jsonb_build_object('id', $CHAT),
                           'text', '/c')))).reply_text;" 2>&1 | tail -n +2)"
        if [[ "$D_OUT" == *"آینه"* ]]; then
            pass "wf-01 → bot_dispatch_json با نقش ربات پاسخ داد (چت $CHAT)"
        elif [[ "$D_OUT" == *"permission denied"* ]]; then
            fail "مسیر کامل ربات «permission denied» داد" "bash 03_ops/deploy_sql.sh"
        else
            fail "مسیر کامل ربات پاسخ نداد: $D_OUT"
            c_hint "اگر «این حساب مجاز نیست» بود، یعنی چت $CHAT در crm.users مجاز نیست"
        fi
    fi
else
    c_hint "برای آزمون مسیر کامل (bot_dispatch_json) با --full اجرا کنید."
fi

# ── ۵) CRM دست‌نخورده ─────────────────────────────────────────────────
c_head "۵) مرز CRM"
ORG="$(q "SELECT count(*) FROM crm.organizations")"
c_ok "سازمان‌های CRM: ${ORG:-?} (آینه چیزی به آن‌ها اضافه نمی‌کند)"

echo
if [[ $FAILS -eq 0 ]]; then
    c_ok "همهٔ بازبینی‌ها سبز است — ربات می‌تواند در بله /c بزند"
    echo
    c_hint "در بله امتحان کنید:  /c   ·   /c 38B   ·   /c نام شرکت"
    exit 0
else
    c_bad "$FAILS بازبینی ناموفق است؛ تا رفع، /c در بله کار نمی‌کند"
    exit 1
fi
