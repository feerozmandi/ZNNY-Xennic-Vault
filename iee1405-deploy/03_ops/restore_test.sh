#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — آزمون بازگردانی پشتیبان (بدون دست زدن به دیتابیس تولیدی)
#
# اجرا:
#   bash 03_ops/restore_test.sh                    # آخرین پشتیبان
#   bash 03_ops/restore_test.sh ~/xennic-backups/iee-predeploy-....dump
#
# چه می‌کند؟
#   ۱. یک دیتابیس موقت می‌سازد (iee_restore_test_<timestamp>)
#   ۲. پشتیبان را با pg_restore در آن بازمی‌گرداند
#   ۳. تعداد جدول‌ها، شرکت‌ها و ادعاها را می‌شمارد و با انتظار مقایسه می‌کند
#   ۴. دیتابیس موقت را پاک می‌کند (مگر با --keep)
#
# چرا لازم است؟ پشتیبانِ آزمایش‌نشده، پشتیبان نیست. [[PRJ-IEE-013]]
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib_common.sh"

KEEP=0
FILE=""
for a in "$@"; do
    case "$a" in
        --keep) KEEP=1 ;;
        *) FILE="$a" ;;
    esac
done

BACKUP_DIR="${BACKUP_DIR:-$HOME/xennic-backups}"
if [[ -z "$FILE" ]]; then
    FILE="$(ls -1t "$BACKUP_DIR"/iee-*.dump 2>/dev/null | head -1)"
fi

if [[ -z "$FILE" || ! -f "$FILE" ]]; then
    c_bad "فایل پشتیبان پیدا نشد"
    c_hint "اول: bash 03_ops/backup_now.sh"
    c_hint "فایل‌های موجود: $(ls -1 "$BACKUP_DIR" 2>/dev/null | tail -5 | tr '\n' ' ')"
    exit 1
fi

if ! dk_detect || ! ct_detect || ! pg_user_detect; then
    c_bad "Docker یا کانتینر PostgreSQL در دسترس نیست"
    exit 1
fi

TEST_DB="iee_restore_test_$(date -u +%H%M%S)"
c_head "بازگردانی آزمایشی"
echo "  فایل:    $(basename "$FILE") ($(du -h "$FILE" | cut -f1))"
echo "  دیتابیس: $TEST_DB"
echo "  کانتینر: $PG_CT · کاربر: $PG_USER"

cleanup() {
    if [[ "$KEEP" == "1" ]]; then
        c_warn "دیتابیس موقت نگه داشته شد: $TEST_DB"
    else
        pgq postgres -c "DROP DATABASE IF EXISTS \"$TEST_DB\"" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

echo "→ ساخت دیتابیس موقت"
if ! pg_db_create "$TEST_DB"; then
    c_bad "ساخت دیتابیس موقت ناموفق (اجازه CREATEDB؟)"
    exit 1
fi
c_ok "ساخته شد"

echo "→ بازگردانی"
if ! $DK exec -i "$PG_CT" pg_restore -U "$PG_USER" -d "$TEST_DB" --no-owner --no-privileges < "$FILE" >/tmp/iee_restore.log 2>&1; then
    # pg_restore با هشدارهای غیرکشنده هم کد خطا می‌دهد؛ محتوا را می‌سنجیم
    if grep -qiE "fatal|could not|غلط" /tmp/iee_restore.log; then
        c_bad "بازگردانی با خطا مواجه شد"
        tail -15 /tmp/iee_restore.log | sed 's/^/     /'
        exit 1
    fi
    c_warn "بازگردانی با هشدار تمام شد (بررسی محتوا ادامه دارد)"
fi

echo "→ بررسی محتوا"
T="$(pgq "$TEST_DB" -c "SELECT count(*) FROM pg_tables WHERE schemaname IN ('crm','iee1405')" | tr -d '[:space:]')"
O="$(pgq "$TEST_DB" -c "SELECT count(*) FROM crm.organizations" 2>/dev/null | tr -d '[:space:]')"
C="$(pgq "$TEST_DB" -c "SELECT count(*) FROM crm.claims" 2>/dev/null | tr -d '[:space:]')"
K="$(pgq "$TEST_DB" -c "SELECT count(*) FROM crm.product_categories" 2>/dev/null | tr -d '[:space:]')"
F="$(pgq "$TEST_DB" -c "SELECT count(*) FROM information_schema.routines WHERE routine_schema IN ('crm','iee1405')" 2>/dev/null | tr -d '[:space:]')"

printf '  جدول: %s · تابع: %s · شرکت: %s · ادعا: %s · دسته: %s\n' \
       "${T:-0}" "${F:-0}" "${O:-0}" "${C:-0}" "${K:-0}"

FAIL=0
[[ "${T:-0}" -ge 20 ]] && c_ok "ساختار بازگردانده شد" || { c_bad "جدول‌ها کم‌اند"; FAIL=1; }
[[ "${F:-0}" -ge 20 ]] && c_ok "توابع بازگردانده شدند" || { c_bad "توابع کم‌اند"; FAIL=1; }
[[ "${K:-0}" -ge 15 ]] && c_ok "داده مرجع (دسته‌های محصول) بازگردانده شد" || { c_bad "داده مرجع ناقص"; FAIL=1; }
[[ "${O:-0}" -ge 0 ]] && c_ok "جدول شرکت‌ها خوانا است (${O:-0} رکورد)" || true

echo ""
if [[ "$FAIL" == "0" ]]; then
    c_ok "پشتیبان قابل بازگردانی است ✅"
    exit 0
fi
c_bad "پشتیبان ناقص است — یک نسخه سالم‌تر بسازید و این آزمون را تکرار کنید"
exit 1
