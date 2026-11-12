#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — رفع فوری دسترسی نقش ربات (iee_app)
#
#   bash 03_ops/fix_grants.sh
#
# برای چه؟ خطای «permission denied for sequence bot_errors_id_seq» یعنی نقش
# n8n روی سیکوئنس‌ها USAGE ندارد. این اسکریپت گرنت‌ها را اعمال می‌کند و بعد
# **واقعاً آزمایش می‌کند** که ربات با همان نقش کار می‌کند — نه فقط اینکه
# دستور بدون خطا اجرا شد.
#
# فقط گرنت می‌دهد: هیچ ساختار یا داده‌ای تغییر نمی‌کند و رمزی چاپ نمی‌شود.
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_common.sh
source "$HERE/lib_common.sh"

dk_detect || { c_bad "docker در دسترس نیست — این اسکریپت روی سرور اجرا می‌شود"; exit 1; }
ct_detect >/dev/null 2>&1 || { c_bad "کانتینر PostgreSQL پیدا نشد"; exit 1; }
PG_USER="${PG_USER:-$(pg_user_detect 2>/dev/null; printf '%s' "${PG_USER:-postgres}")}"
[[ "$PG_USER" == "postgres" || -n "$PG_USER" ]] || PG_USER="postgres"

c_head "۱) اعمال گرنت‌ها"
if pgq "$PG_DB" -v ON_ERROR_STOP=1 -f - < "$HERE/../01_sql/06_roles.sql" >/tmp/iee_grant.log 2>&1; then
    c_ok "گرنت‌های 06_roles.sql اعمال شد"
else
    c_bad "اجرای 06_roles.sql ناموفق بود:"
    grep -E "ERROR|FATAL" /tmp/iee_grant.log | head -5 | sed 's/^/     /'
    exit 1
fi

c_head "۲) بازبینی دسترسی‌ها"
GAPS="$(pgq "$PG_DB" -c "SELECT count(*) FROM iee1405.privilege_gaps()" 2>/dev/null | tr -d '[:space:]')"
if [[ "$GAPS" == "0" ]]; then
    c_ok "هیچ کمبود دسترسی‌ای نیست"
else
    c_bad "کمبود دسترسی: ${GAPS:-?} مورد"
    pgq_pretty "$PG_DB" -c "
        SELECT kind AS نوع, object_name AS شیء, needed AS دسترسی_لازم
          FROM iee1405.privilege_gaps()" | sed 's/^/  /'
fi

c_head "۳) آزمون واقعی با نقش iee_app"
# توجه: فراخوانی bot_dispatch_json به‌تنهایی کافی نیست؛ برای پیام مجاز/نامجاز
# مسیر خطا طی نمی‌شود و به bot_errors نمی‌نویسد. پس دقیقاً همان INSERTهایی
# زده می‌شود که ربات در عمل انجام می‌دهد — همه داخل تراکنش و بازگشتی.
TEST="$(pgq "$PG_DB" -c "
BEGIN;
SET ROLE iee_app;
INSERT INTO iee1405.bot_errors (stage, message) VALUES ('grant_test', 'x');
INSERT INTO iee1405.bot_updates (update_id, raw) VALUES (-1, '{}'::jsonb);
UPDATE iee1405.bot_state SET updated_at = clock_timestamp() WHERE key = 'bale_offset';
SELECT 'OK-INSERT';
ROLLBACK;" 2>&1)"

if printf '%s' "$TEST" | grep -q '^OK-INSERT'; then
    c_ok "نوشتن در bot_errors / bot_updates / bot_state با نقش iee_app مجاز است"
else
    c_bad "نوشتن با نقش iee_app شکست خورد (این همان خطای گره «پردازش» است):"
    printf '%s\n' "$TEST" | grep -E "ERROR|denied" | head -3 | sed 's/^/     /'
    exit 1
fi

SEQ="$(pgq "$PG_DB" -c "
    SELECT has_sequence_privilege('iee_app', 'iee1405.bot_errors_id_seq', 'USAGE')" 2>/dev/null | tr -d '[:space:]')"
[[ "$SEQ" == "t" ]] && c_ok "iee_app روی bot_errors_id_seq دسترسی USAGE دارد" \
                    || { c_bad "bot_errors_id_seq: USAGE ندارد (${SEQ:-?})"; exit 1; }

c_head "۴) ورود واقعی با رمز برنامه (اگر ذخیره شده باشد)"
PW_FILE="$HOME/.iee1405-app-password"
if [[ -f "$PW_FILE" ]]; then
    LOGIN="$($DK exec -e "PGPASSWORD=$(cat "$PW_FILE")" "$PG_CT" \
             psql -h 127.0.0.1 -U iee_app -d "$PG_DB" -X -t -A \
             -c "SELECT 'login-ok'" 2>&1 | tail -1 | tr -d '[:space:]')"
    if [[ "$LOGIN" == "login-ok" ]]; then
        c_ok "ورود iee_app با رمز ذخیره‌شده کار می‌کند (همان چیزی که n8n استفاده می‌کند)"
    else
        c_warn "ورود با رمز iee_app ناموفق: $(printf '%s' "$LOGIN" | head -c 80)"
        c_hint "رمز کارت اعتبارنامه در n8n ممکن است قدیمی باشد؛ رمز را از $PW_FILE بازسازی کنید:"
        c_hint "APP_PASSWORD='رمز-قوی' bash 03_ops/deploy_sql.sh"
    fi
else
    c_hint "فایل $PW_FILE نیست — آزمون ورود رد شد (این خطا را ایجاد نمی‌کند)"
fi

c_head "۵) گام بعدی"
echo "  هیچ ری‌استارتی لازم نیست (مجوزها فوری اثر می‌کنند)."
echo "  در n8n روی همان گره «🧠 پردازش در PostgreSQL» دوباره Execute step بزنید."
echo
c_hint "اگر باز هم خطا داد، خروجی این اسکریپت را بفرستید — بخش ۲ و ۳ دقیقاً می‌گویند چه چیزی کم است"
echo
