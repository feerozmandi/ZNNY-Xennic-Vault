#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — استقرار ساختار و منطق در PostgreSQL
#
# اجرا روی VPS (از مسیر iee1405-deploy):
#   bash 03_ops/deploy_sql.sh                 # ساختار + منطق + نقش‌ها
#   bash 03_ops/deploy_sql.sh --verify-only   # فقط بررسی، بدون تغییر
#   bash 03_ops/deploy_sql.sh --no-backup     # بدون پشتیبان (نه پیشنهاد می‌شود)
#
# کانتینر، کاربر دیتابیس و نام دیتابیس خودکار کشف می‌شوند
# (روی این سرور: xennic-infra-postgres-1 · n8n · دیتابیس اختصاصی xennic).
# اگر دیتابیس وجود نداشته باشد ساخته می‌شود؛ دیتابیس n8n دست نمی‌خورد.
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL_DIR="$HERE/01_sql"
# shellcheck source=/dev/null
source "$HERE/03_ops/lib_common.sh"

MODE="${1:-deploy}"
[[ "$MODE" == "--verify-only" || "$MODE" == "--no-backup" ]] || MODE="deploy"

if ! dk_detect; then
    c_bad "Docker یا دسترسی به آن موجود نیست"
    c_hint "این اسکریپت باید روی سرور و با دسترسی docker اجرا شود."
    exit 1
fi

if ! ct_detect; then
    c_bad "کانتینر PostgreSQL پیدا نشد"
    c_hint "docker ps  را ببینید؛ یا PG_CONTAINER=<name> bash 03_ops/deploy_sql.sh"
    exit 1
fi

if ! pg_user_detect; then
    c_bad "اتصال به PostgreSQL با کاربر «$PG_USER» برقرار نشد"
    c_hint "docker logs --tail 20 $PG_CT"
    exit 1
fi

echo "════════════════════════════════════════════════"
echo " استقرار IEE 1405"
echo " کانتینر: $PG_CT · کاربر: $PG_USER · دیتابیس: $PG_DB"
echo " حالت: $MODE"
echo "════════════════════════════════════════════════"

# ── دیتابیس مقصد ──────────────────────────────────────────────────────
if ! pg_db_exists "$PG_DB"; then
    if [[ "$MODE" == "--verify-only" ]]; then
        c_warn "دیتابیس «$PG_DB» وجود ندارد (در حالت استقرار ساخته می‌شود)"
        c_hint "دیتابیس‌های موجود: $(pgq postgres -c "SELECT string_agg(datname, ' ' ORDER BY datname) FROM pg_database" | tr -d '\n')"
        exit 0
    fi
    echo "→ ساخت دیتابیس اختصاصی «$PG_DB»"
    if pg_db_create "$PG_DB"; then
        c_ok "دیتابیس «$PG_DB» ساخته شد (دیتابیس n8n دست‌نخورده ماند)"
    else
        c_bad "ساخت دیتابیس ناموفق بود"
        c_hint "کاربر «$PG_USER» اجازه CREATEDB ندارد؛ با کاربر سوپریوزر امتحان کنید:"
        c_hint "  PG_USER=postgres bash 03_ops/deploy_sql.sh"
        exit 1
    fi
fi

pgfile() { pgq "$PG_DB" -v ON_ERROR_STOP=1 "$@" 2>/tmp/iee_err.txt; }

run_file() {
    local f="$1"
    echo "→ $(basename "$f")"
    if ! pgq "$PG_DB" -v ON_ERROR_STOP=1 -f - < "$f" >/tmp/iee_out.txt 2>/tmp/iee_err.txt; then
        c_bad "خطا در $(basename "$f")"
        grep -E "ERROR|FATAL" /tmp/iee_err.txt | head -10 | sed 's/^/     /'
        # همین خطا دو بار ربات را بی‌صدا کرد؛ راه‌حل را همان‌جا بگو
        if grep -q "cannot change return type" /tmp/iee_err.txt; then
            c_hint "پایگاه نسخهٔ کهنهٔ یک تابع را دارد و CREATE OR REPLACE نمی‌تواند نوع خروجی را عوض کند."
            c_hint "از نسخهٔ ۰.۱.۳۳ فایل‌ها خودشان نسخهٔ کهنه را حذف می‌کنند؛ اگر این پیام را دیدید،"
            c_hint "یعنی فایل ۰۱ (که تابع نگهبان را می‌سازد) در همین اجرا مشکل داشته. ترتیب اجرا را ببینید."
            c_hint "راه سریع: bash 03_ops/test_stale_signatures.sh  ← نشان می‌دهد نگهبان کار می‌کند یا نه"
        fi
        exit 1
    fi
    local notices
    notices="$(grep -c "NOTICE" /tmp/iee_err.txt 2>/dev/null)"
    notices="${notices:-0}"
    if [[ "$notices" == "0" ]]; then
        c_ok "اجرا شد"
    else
        c_ok "اجرا شد ($notices اعلان طبیعی — اشیای موجود بازنویسی نشدند)"
    fi
}

if [[ "$MODE" == "--verify-only" ]]; then
    echo ""
    c_head "وضعیت فعلی"
    pgq_pretty "$PG_DB" -c "SELECT schemaname AS schema, count(*) AS tables
                             FROM pg_tables WHERE schemaname IN ('crm','iee1405')
                            GROUP BY 1 ORDER BY 1" | sed 's/^/  /'
    echo ""
    c_head "توابع"
    printf '  %s تابع\n' "$(pgq "$PG_DB" -c "SELECT count(*) FROM information_schema.routines WHERE routine_schema IN ('crm','iee1405')")"
    if [[ "$(pgq "$PG_DB" -c "SELECT count(*) FROM pg_tables WHERE schemaname IN ('crm','iee1405')")" != "0" ]]; then
        echo ""
        c_head "سلامت"
        pgq_pretty "$PG_DB" -c "SELECT iee1405.health_text()" | sed 's/^/  /'
    fi
    exit 0
fi

# ── پشتیبان قبل از تغییر ──────────────────────────────────────────────
EXISTING="$(pgq "$PG_DB" -c "SELECT count(*) FROM pg_tables WHERE schemaname IN ('crm','iee1405')" 2>/dev/null | tr -d '[:space:]')"
echo "جدول‌های موجود در crm/iee1405: ${EXISTING:-0}"

if [[ "$MODE" != "--no-backup" && "${EXISTING:-0}" != "0" ]]; then
    echo "→ پشتیبان قبل از تغییر"
    if ! BACKUP_DIR="${BACKUP_DIR:-$HOME/xennic-backups}" \
         PG_DB="$PG_DB" PG_CONTAINER="$PG_CT" PG_USER="$PG_USER" \
         bash "$HERE/03_ops/backup_now.sh" predeploy; then
        c_bad "پشتیبان‌گیری ناموفق بود؛ برای ادامه عمداً متوقف شد"
        c_hint "اگر مطمئن هستید: bash 03_ops/deploy_sql.sh --no-backup"
        exit 1
    fi
fi

# ── اجرای فایل‌ها (ترتیب مهم است) ─────────────────────────────────────
# ۱۰ پیش از ۰۹ اجرا می‌شود: خودآزمون ۰۹ وجود دکمهٔ «🎤 مصاحبه» را که از ۱۰
# می‌آید بررسی می‌کند؛ ۱۰ به ۰۹ وابسته نیست (همین ترتیب روی پایگاه تازه تست شد).
for f in 01_schema_core.sql 02_seed_reference.sql 03_views.sql 04_bot_logic.sql 05_ops_helpers.sql \
         07_import_indexes.sql 08_exhibitor_mirror.sql 10_interview.sql 09_company_list.sql; do
    run_file "$SQL_DIR/$f"
done

# ── نقش‌ها ────────────────────────────────────────────────────────────
echo "→ نقش‌ها و دسترسی‌ها"
if [[ -n "${APP_PASSWORD:-}" ]]; then
    pgq "$PG_DB" -v ON_ERROR_STOP=1 -v app_password="$APP_PASSWORD" \
        -f - < "$SQL_DIR/06_roles.sql" >/dev/null 2>/tmp/iee_err.txt \
        && c_ok "نقش iee_app با رمز ساخته/به‌روز شد" \
        || { c_bad "ساخت نقش‌ها ناموفق"; grep ERROR /tmp/iee_err.txt | head -5 | sed 's/^/     /'; exit 1; }
    echo "$APP_PASSWORD" > "$HOME/.iee1405-app-password"
    chmod 600 "$HOME/.iee1405-app-password"
    c_hint "رمز در ~/.iee1405-app-password ذخیره شد (فقط برای ساخت کارت اعتبارنامه در n8n)"
else
    if pgq "$PG_DB" -v ON_ERROR_STOP=1 -f - < "$SQL_DIR/06_roles.sql" >/tmp/iee_roles.log 2>&1; then
        c_warn "نقش‌ها بدون رمز ساخته شدند — قبل از استفاده رمز بگذارید:"
        c_hint "APP_PASSWORD='رمز-قوی' bash 03_ops/deploy_sql.sh"
    else
        # شکست در گرنت‌ها باید همین‌جا دیده شود، نه با «permission denied» در n8n
        c_bad "ساخت نقش‌ها/گرنت‌ها ناموفق بود:"
        grep -E "ERROR|FATAL" /tmp/iee_roles.log | head -5 | sed 's/^/     /'
        exit 1
    fi
fi

# ── اتصال گوشی اصلی، اگر شناسه گفت‌وگو در .env باشد ──────────────────
CHAT_ID="$(env_get BALE_CHAT_ID || true)"
if [[ -n "$CHAT_ID" ]]; then
    pgq "$PG_DB" -c "UPDATE crm.users SET bale_chat_id = $CHAT_ID WHERE username = 'ahmad'" >/dev/null 2>&1 \
        && c_ok "شناسه گفت‌وگوی مدیر از .env ثبت شد (BALE_CHAT_ID=$CHAT_ID)" \
        || c_warn "ثبت BALE_CHAT_ID ناموفق (مقدار عددی است؟)"
else
    c_hint "BALE_CHAT_ID در .env خالی است — بعد از /start در بله آن را پر کنید"
fi

# ── تأیید نهایی ───────────────────────────────────────────────────────
c_head "تأیید"
pgq_pretty "$PG_DB" -c "
SELECT 'جدول' AS مورد, count(*)::text AS تعداد FROM pg_tables WHERE schemaname IN ('crm','iee1405')
UNION ALL SELECT 'نما', count(*)::text FROM pg_views WHERE schemaname IN ('crm','iee1405')
UNION ALL SELECT 'تابع', count(*)::text FROM information_schema.routines WHERE routine_schema IN ('crm','iee1405')
UNION ALL SELECT 'دسته محصول', count(*)::text FROM crm.product_categories
UNION ALL SELECT 'نمایشگاه', count(*)::text FROM iee1405.exhibitions
UNION ALL SELECT 'کاربر', count(*)::text FROM crm.users" | sed 's/^/  /'

echo ""
pgq_pretty "$PG_DB" -c "SELECT iee1405.health_text()" | sed 's/^/  /'

# ── دسترسی نقش ربات: خطاهای واقعی «permission denied» این‌جا پیدا می‌شوند ──
echo ""
c_head "دسترسی نقش iee_app (همان نقشی که n8n استفاده می‌کند)"
GAPS="$(pgq "$PG_DB" -c "SELECT count(*) FROM iee1405.privilege_gaps()" 2>/dev/null | tr -d '[:space:]')"
if [[ "$GAPS" == "0" ]]; then
    c_ok "بدون کمبود دسترسی"
elif [[ -z "$GAPS" ]]; then
    c_warn "تابع بازبینی ساخته نشده (06_roles.sql اجرا نشده است)"
    c_hint "APP_PASSWORD='رمز-قوی' bash 03_ops/deploy_sql.sh"
else
    c_bad "کمبود دسترسی: $GAPS مورد — ربات در تولید با «permission denied» متوقف می‌شود"
    pgq_pretty "$PG_DB" -c "SELECT kind, object_name, needed FROM iee1405.privilege_gaps()" | sed 's/^/  /'
    c_hint "grants در 01_sql/06_roles.sql است؛ دوباره اجرا کنید: bash 03_ops/deploy_sql.sh"
fi

# آزمون واقعی: توابع ربات با نقش iee_app (نه با postgres)
# SET ROLE خودش یک خط «SET» چاپ می‌کند؛ فقط آخرین خط، جواب کوئری است
APP_TEST="$(pgq "$PG_DB" -c "SET ROLE iee_app; SELECT iee1405.poll_offset();" 2>&1 |
            tail -1 | tr -d '[:space:]')"
if [[ "$APP_TEST" =~ ^[0-9]+$ ]]; then
    c_ok "توابع پایه با نقش iee_app اجرا می‌شوند"
else
    c_warn "آزمون نقش iee_app ناموفق: $(printf '%s' "$APP_TEST" | head -c 80)"
    c_hint "bash 03_ops/deploy_sql.sh   # گرنت‌ها را دوباره اعمال می‌کند"
fi

echo ""
echo "✅ استقرار تمام شد"
echo "   گام بعدی: bash 03_ops/import_workflows.sh import"
echo "   در n8n کارت اعتبارنامه: میزبان postgres · دیتابیس $PG_DB · کاربر iee_app"
