#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — «پیام‌های من کجا رفتند؟»
#
#   bash 03_ops/inspect_state.sh
#
# وقتی getUpdates نتیجه خالی (result: []) می‌دهد، یعنی بله آپدیت تازه‌ای
# ندارد — یا همه پردازش شده‌اند، یا offset از آن‌ها گذشته است. این اسکریپت
# تفاوت این دو را نشان می‌دهد. فقط می‌خواند؛ هیچ چیزی را تغییر نمی‌دهد.
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_common.sh
source "$HERE/lib_common.sh"

dk_detect || { c_bad "docker در دسترس نیست"; exit 1; }
ct_detect >/dev/null 2>&1 || { c_bad "کانتینر PostgreSQL پیدا نشد"; exit 1; }

OFFSET="$(pgq "$PG_DB" -c "SELECT iee1405.poll_offset()" 2>/dev/null | tr -d '[:space:]')"
TOTAL="$(pgq "$PG_DB" -c "SELECT count(*) FROM iee1405.bot_updates" 2>/dev/null | tr -d '[:space:]')"
MAXID="$(pgq "$PG_DB" -c "SELECT COALESCE(max(update_id),0) FROM iee1405.bot_updates" 2>/dev/null | tr -d '[:space:]')"
PENDING="$(pgq "$PG_DB" -c "SELECT count(*) FROM iee1405.pending_replies(1000)" 2>/dev/null | tr -d '[:space:]')"
UNDELIV="$(pgq "$PG_DB" -c "SELECT count(*) FROM iee1405.bot_updates WHERE reply_text IS NOT NULL AND delivered_at IS NULL" 2>/dev/null | tr -d '[:space:]')"
ERRS="$(pgq "$PG_DB" -c "SELECT count(*) FROM iee1405.bot_errors" 2>/dev/null | tr -d '[:space:]')"
LASTPOLL="$(pgq "$PG_DB" -c "SELECT COALESCE(value,'—') FROM iee1405.bot_state WHERE key='last_poll_at'" 2>/dev/null | tr -d '\n')"
LASTERR="$(pgq "$PG_DB" -c "SELECT COALESCE(value,'—') FROM iee1405.bot_state WHERE key='last_error'" 2>/dev/null | tr -d '\n')"

c_head "۱) شمارنده‌ها"
printf '  offset (شناسه آخرین آپدیت مصرف‌شده) : %s\n' "${OFFSET:-?}"
printf '  بزرگ‌ترین update_id ثبت‌شده        : %s\n' "${MAXID:-?}"
printf '  آپدیت‌های ثبت‌شده                    : %s\n' "${TOTAL:-?}"
printf '  پاسخ‌های در صف ارسال                : %s\n' "${PENDING:-?}"
printf '  پاسخ‌های ارسال‌نشده                 : %s\n' "${UNDELIV:-?}"
printf '  خطاهای ثبت‌شده                      : %s\n' "${ERRS:-?}"
printf '  آخرین پیمایش                        : %s\n' "${LASTPOLL:-—}"
printf '  آخرین خطا                           : %s\n' "${LASTERR:0:60}"

c_head "۲) آخرین آپدیت‌ها"
pgq_pretty "$PG_DB" -c "
SELECT u.update_id AS شناسه,
       COALESCE(left(u.command, 18), '—') AS دستور,
       u.status AS وضعیت,
       CASE WHEN u.reply_text IS NULL THEN '—' ELSE left(replace(u.reply_text, E'\n', ' '), 28) END AS پاسخ,
       CASE WHEN u.reply_text IS NULL THEN 'لازم نبود'
            WHEN u.delivered_at IS NULL THEN 'خیر'
            ELSE 'بله' END AS ارسال‌شده,
       to_char(u.processed_at, 'HH24:MI:SS') AS ساعت
  FROM iee1405.bot_updates u
 ORDER BY u.update_id DESC LIMIT 8" 2>/dev/null | sed 's/^/  /'

# ── نتیجه‌گیری ───────────────────────────────────────────────────────
c_head "۳) نتیجه"
if [[ -z "${TOTAL:-}" || -z "${OFFSET:-}" ]]; then
    c_bad "خواندن وضعیت ناموفق بود (دیتابیس یا توابع در دسترس نیستند)"
    exit 1
fi

FINDINGS=0
if [[ "$OFFSET" -gt 0 && "$TOTAL" -eq 0 ]]; then
    c_bad "offset=$OFFSET است ولی هیچ آپدیتی ثبت نشده — پیام‌ها از دست رفته‌اند"
    c_hint "یعنی دریافت انجام شد اما پردازش نه (گره پردازش شکست خورده یا اجرا نشده)"
    c_hint "بازخوانی از صفر: SELECT iee1405.poll_reset(0);  سپس ری‌اکتیو کردن گردش‌کار"
    FINDINGS=$((FINDINGS+1))
fi

if [[ "${UNDELIV:-0}" -gt 0 ]]; then
    c_warn "$UNDELIV پاسخ ارسال‌نشده هست — در پیمایش خالی هم باید دوباره تلاش شود"
    c_hint "نسخه‌های قبل از ۰.۱.۱۵ در پیمایش خالی زنجیره را قطع می‌کردند؛ به‌روزرسانی کنید"
    FINDINGS=$((FINDINGS+1))
fi

if [[ "${ERRS:-0}" -gt 0 ]]; then
    c_warn "$ERRS خطا ثبت شده — جزئیات:"
    pgq_pretty "$PG_DB" -c "
        SELECT stage AS مرحله, left(message, 60) AS پیام, to_char(occurred_at, 'HH24:MI:SS') AS ساعت
          FROM iee1405.bot_errors ORDER BY id DESC LIMIT 5" 2>/dev/null | sed 's/^/     /'
    FINDINGS=$((FINDINGS+1))
fi

if [[ "$FINDINGS" -eq 0 ]]; then
    c_ok "همه‌چیز سالم است: هر آپدیتی که بله داد، ثبت و پردازش شد"
    echo
    echo "  خروجی خالی گره «📥 دریافت پیام‌ها» (result: []) در این وضعیت **طبیعی** است:"
    echo "  بله هیچ پیام تازه‌ای ندارد، چون offset=$OFFSET از همه پیام‌های موجود گذشته است."
    echo
    c_hint "برای آزمون دوباره، در بله یک پیام به ربات بفرستید (/status) و ۲۰ ثانیه صبر کنید"
    c_hint "یا فوراً: bash 03_ops/diagnose_n8n.sh   ← بخش ۴ و ۵"
fi

c_head "۴) اگر می‌خواهید همه پیام‌های قبلی دوباره پردازش شوند"
echo "  این کار آگاهانه است و پیام‌ها **دوباره** فرستاده می‌شوند (تکرار = داده تکراری در CRM نه، ولی پیام تکراری در بله بله):"
echo
echo "    bash 03_ops/replay_updates.sh --dry-run   # فقط نشان می‌دهد چه چیزی تکرار می‌شود"
echo "    bash 03_ops/replay_updates.sh             # اجرای واقعی"
echo
