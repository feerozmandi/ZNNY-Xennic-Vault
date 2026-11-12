#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — «چرا ربات جواب نداد؟» یک دستور، یک جواب
#
#   bash 03_ops/why_silent.sh              # گزارش کامل (فقط می‌خواند)
#   bash 03_ops/why_silent.sh --chat 389570094
#
# این اسکریپت برای همان شکایتی است که دو بار پیش آمد: «پیام می‌فرستم، هیچ
# چیزی بالا نمی‌آید». به‌جای حدس، زنجیره را از آخر به اول می‌سنجد:
#   ۱) آیا آپدیت به پایگاه رسید؟        (bot_updates)
#   ۲) آیا پاسخی ساخته شد؟              (reply_text)
#   ۳) اگر ساخته نشد، چرا؟              (ضدتکرار / duplicate / error / unauthorized)
#   ۴) اگر ساخته شد، چرا نرفت؟          (صف pending_replies و delivered_at)
#   ۵) و در آخر: «همین حالا یک آپدیت تازه» داخل تراکنش آزمایش می‌شود.
# هیچ چیزی تغییر نمی‌کند؛ آزمون پایانی با ROLLBACK برمی‌گردد و پیامی هم به
# بله نمی‌رود (n8n فقط ردیف‌های commit‌شده را می‌بیند).
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

CHAT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --chat) CHAT="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "گزینه ناشناخته: $1" >&2; exit 2 ;;
    esac
done

dk_detect || { c_bad "docker در دسترس نیست"; exit 1; }
ct_detect || { c_bad "کانتینر PostgreSQL بالا نیست"; exit 1; }
pg_user_detect >/dev/null 2>&1 || true

q() { pgq "$PG_DB" -c "$1"; }

echo "════════════════════════════════════════════════"
echo " چرا ربات جواب نداد؟"
echo "════════════════════════════════════════════════"

# ── ۰) چت مورد بررسی ─────────────────────────────────────────────────
if [[ -z "$CHAT" ]]; then
    CHAT="$(q "SELECT COALESCE((SELECT chat_id FROM iee1405.bot_updates
                                 WHERE chat_id IS NOT NULL
                                 ORDER BY received_at DESC LIMIT 1), 0)")"
fi
if [[ -z "$CHAT" || "$CHAT" == "0" ]]; then
    c_bad "هیچ آپدیتی در پایگاه نیست — یعنی هیچ پیامی از بله نرسیده"
    c_hint "bash 03_ops/diagnose_n8n.sh   (گردش‌کار ۰۱ فعال است؟ offset سالم است؟)"
    exit 1
fi

USERNAME="$(q "SELECT COALESCE((SELECT username FROM crm.users WHERE bale_chat_id = $CHAT), '—')")"
echo " گفت‌وگو: $CHAT (کاربر: $USERNAME)"

# ── ۱) پنجرهٔ ضدتکرار ────────────────────────────────────────────────
DEDUPE="$(q "SELECT COALESCE((SELECT value FROM iee1405.bot_state
                              WHERE key = 'help_dedupe_seconds'), '45')")"

# ── ۲) آخرین آپدیت‌ها ────────────────────────────────────────────────
c_head "۱) آخرین ۶ آپدیت این گفت‌وگو"
pgq_pretty "$PG_DB" -c "
SELECT u.update_id,
       left(COALESCE(u.command, '—'), 18)                    AS ورودی,
       u.status,
       CASE WHEN u.reply_text IS NULL THEN '— سکوت —'
            ELSE left(replace(u.reply_text, E'\n', ' '), 34) END AS پاسخ,
       CASE WHEN u.reply_text IS NULL THEN '—'
            WHEN u.delivered_at IS NULL THEN 'در صف'
            ELSE to_char(u.delivered_at, 'HH24:MI:SS') END    AS ارسال,
       to_char(u.processed_at, 'HH24:MI:SS')                  AS پردازش
  FROM iee1405.bot_updates u
 WHERE u.chat_id = $CHAT
 ORDER BY u.update_id DESC
 LIMIT 6;"

# ── ۳) چرا سکوت؟ (تشخیص ردیف‌های بی‌پاسخ) ────────────────────────────
c_head "۲) علت سکوت آخرین پیام‌ها"

SILENT="$(q "SELECT count(*) FROM iee1405.bot_updates
              WHERE chat_id = $CHAT AND reply_text IS NULL
                AND update_id >= (SELECT COALESCE(max(update_id), 0) - 20
                                    FROM iee1405.bot_updates WHERE chat_id = $CHAT)")"

if [[ "${SILENT:-0}" == "0" ]]; then
    c_ok "هیچ پیام بی‌پاسخی در ۲۰ آپدیت آخر نیست — سکوت از این سمت نمی‌آید"
    c_hint "پس پیام به پایگاه نرسیده یا ارسال نشده: بخش ۳ و ۴ را ببینید"
else
    pgq_pretty "$PG_DB" -c "
    SELECT u.update_id,
           left(COALESCE(u.command, '—'), 18) AS ورودی,
           CASE
             WHEN u.status = 'duplicate'
               THEN 'همین update_id قبلاً پردازش شده (تصادف یا تکرار بله)'
             WHEN u.status = 'error'
               THEN 'در پردازش خطا خورد — bot_errors را ببینید'
             WHEN u.status = 'unauthorized'
               THEN 'چت در crm.users مجاز نیست'
             WHEN COALESCE(u.command, '') LIKE '/start%' OR COALESCE(u.command, '') LIKE '/help%'
               THEN 'ضدتکرار راهنما: پاسخ هم‌متن در ' || '$DEDUPE' || ' ثانیهٔ گذشته ارسال شده بود'
             WHEN COALESCE(u.command, '') = ''
               THEN 'پیام بدون متن (عکس/فایل) — پاسخ راهنما در صف است'
             ELSE 'پاسخ خالی ساخته شد (حالت جلسه یا ورودی نامفهوم)'
           END AS علت_محتمل
      FROM iee1405.bot_updates u
     WHERE u.chat_id = $CHAT AND u.reply_text IS NULL
       AND u.update_id >= (SELECT COALESCE(max(update_id), 0) - 20
                             FROM iee1405.bot_updates WHERE chat_id = $CHAT)
     ORDER BY u.update_id DESC
     LIMIT 5;"
    c_hint "پنجرهٔ فعلی ضدتکرار: $DEDUPE ثانیه  (تنظیم: UPDATE iee1405.bot_state SET value='0' WHERE key='help_dedupe_seconds';)"
fi

# ── ۴) صف ارسال ──────────────────────────────────────────────────────
c_head "۳) صف ارسال به بله"
QUEUE="$(q "SELECT count(*) FROM iee1405.pending_replies(50)")"
OLDEST="$(q "SELECT COALESCE(max(age(now(), u.processed_at))::text, '—')
               FROM iee1405.pending_replies(50) p
               JOIN iee1405.bot_updates u ON u.update_id = p.update_id")"
if [[ "${QUEUE:-0}" == "0" ]]; then
    c_ok "صف خالی است — هر پاسخی که ساخته شده، ارسال شده"
else
    c_warn "$QUEUE پاسخ در صف مانده (قدیمی‌ترین: $OLDEST)"
    c_hint "اگر این عدد بالا می‌رود، گره «ارسال پاسخ» در n8n خطا می‌دهد: diagnose_n8n.sh بخش ۳.۱"
fi

# ── ۵) خطاهای تازه ───────────────────────────────────────────────────
c_head "۴) خطاهای ۳۰ دقیقهٔ گذشته"
ERRS="$(q "SELECT count(*) FROM iee1405.bot_errors
            WHERE occurred_at > now() - interval '30 minutes'")"
if [[ "${ERRS:-0}" == "0" ]]; then
    c_ok "خطایی ثبت نشده"
else
    pgq_pretty "$PG_DB" -c "
    SELECT to_char(occurred_at, 'HH24:MI:SS') AS زمان, stage,
           left(replace(message, E'\n', ' '), 60) AS پیام
      FROM iee1405.bot_errors
     WHERE occurred_at > now() - interval '30 minutes'
     ORDER BY id DESC LIMIT 5;"
fi

# ── ۶) آزمون زنده (تراکنشی) ──────────────────────────────────────────
c_head "۵) آزمون زنده: همین حالا یک /start تازه"
# ضدتکرار داخل همان تراکنش خاموش می‌شود تا آزمون «منطق ربات» را بسنجد، نه
# فاصلهٔ زمانی از پیام قبلی. با ROLLBACK همه‌چیز برمی‌گردد.
OUT="$(q "BEGIN;
          UPDATE iee1405.bot_state SET value = '0'
           WHERE key = 'help_dedupe_seconds';
          SELECT 'وضعیت: ' || status || ' —— پاسخ: ' ||
                 COALESCE(left(replace(reply_text, E'\n', ' '), 70), '«سکوت»')
            FROM iee1405.bot_dispatch_json(jsonb_build_object(
                   'update_id', (SELECT COALESCE(max(update_id), 0) + 1
                                   FROM iee1405.bot_updates),
                   'message', jsonb_build_object(
                       'chat', jsonb_build_object('id', $CHAT),
                       'text', '/start')));
          ROLLBACK;" 2>&1 | grep -v "^BEGIN$\|^ROLLBACK$\|^UPDATE 1$")"
echo "  $OUT"

case "$OUT" in
    *"«سکوت»"*)
        c_warn "پاسخ ساخته نشد با وجود خاموش‌کردن ضدتکرار — خطا یا وضعیت جلسه را ببینید"
        ;;
    *"راهنمای ربات"*)
        c_ok "پایگاه، نقش ربات و منطق دستور سالم است"
        c_hint "اگر در بله پیام نمی‌آید، مشکل در ارسال است: بخش ۳ و ۴ و diagnose_n8n.sh"
        ;;
    *)
        c_warn "پاسخ ساخته شد ولی راهنما نبود — متن بالا را ببینید"
        ;;
esac

echo
c_hint "آزمون بالا داخل تراکنش بود و ROLLBACK شد؛ هیچ پیامی به بله نرفت."
