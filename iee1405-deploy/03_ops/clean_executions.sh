#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — بستن اجراهای مرده n8n («running» هایی که دیگر تمام نمی‌شوند)
#
#   bash 03_ops/clean_executions.sh            # نمایش + بستن موارد قدیمی‌تر از ۱۰ دقیقه
#   bash 03_ops/clean_executions.sh --dry-run  # فقط نمایش
#   bash 03_ops/clean_executions.sh --older 5  # آستانه ۵ دقیقه
#
# چرا لازم است؟
#   وقتی گره HTTP معلق می‌ماند، اجرا در وضعیت running می‌ماند. n8n این‌ها را
#   فقط هنگام ری‌استارت «crashed» می‌کند و اگر بازه اجرا کوتاه باشد (۲۰ ثانیه)
#   چند ده ردیف مرده جمع می‌شود. این ردیف‌ها خطا نیستند ولی گزارش سلامت را
#   قرمز می‌کنند و آدم را به عیب‌یابی اشتباه می‌فرستند.
#
# چه کاری می‌کند؟ همان کاری که n8n در crash-recovery خودش می‌کند:
#   status: running → crashed   (هیچ ردیفی حذف نمی‌شود)
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_common.sh
source "$HERE/lib_common.sh"

DRY_RUN=0
OLDER=10
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --older)   OLDER="${2:-10}"; shift 2 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "گزینه ناشناخته: $1" >&2; exit 2 ;;
    esac
done

if ! [[ "$OLDER" =~ ^[0-9]+$ ]] || [[ "$OLDER" -lt 1 ]]; then
    echo "مقدار --older باید عدد مثبت باشد" >&2
    exit 2
fi

dk_detect || { c_bad "docker در دسترس نیست"; exit 1; }
ct_detect >/dev/null 2>&1 || { c_bad "کانتینر پیدا نشد"; exit 1; }
pg_user_detect >/dev/null 2>&1 || true
N8N_DB="$(n8n_db_detect)"
if [[ -z "$N8N_DB" ]]; then
    c_bad "دیتابیس n8n پیدا نشد"
    c_hint "N8N_DB=<نام> bash 03_ops/clean_executions.sh"
    exit 1
fi

COUNT="$(pgq "$N8N_DB" -c "
    SELECT count(*) FROM execution_entity
     WHERE status = 'running'
       AND \"startedAt\" < now() - interval '$OLDER minutes'" 2>/dev/null | tr -d '[:space:]')"

echo "════ اجراهای گیرکرده ════  (دیتابیس: $N8N_DB · آستانه: $OLDER دقیقه)"
if [[ -z "${COUNT:-}" ]]; then
    c_bad "خواندن execution_entity ناموفق بود"
    exit 1
fi
if [[ "$COUNT" == "0" ]]; then
    c_ok "هیچ اجرای گیرکرده‌ای نیست"
    exit 0
fi

c_warn "$COUNT اجرا در وضعیت running بیش از $OLDER دقیقه"
pgq_pretty "$N8N_DB" -c "
    SELECT id,
           to_char(\"startedAt\", 'MM-DD HH24:MI:SS') AS started,
           round(EXTRACT(EPOCH FROM (now() - \"startedAt\")) / 60) AS minutes
      FROM execution_entity
     WHERE status = 'running'
       AND \"startedAt\" < now() - interval '$OLDER minutes'
     ORDER BY id DESC
     LIMIT 10" | sed 's/^/     /'

if [[ "$DRY_RUN" == "1" ]]; then
    c_hint "حالت --dry-run: چیزی تغییر نکرد"
    exit 0
fi

pgq "$N8N_DB" -c "
    UPDATE execution_entity
       SET status = 'crashed', \"stoppedAt\" = now()
     WHERE status = 'running'
       AND \"startedAt\" < now() - interval '$OLDER minutes'" >/dev/null 2>&1 \
    && c_ok "$COUNT اجرا به crashed تغییر کرد (ردیفی حذف نشد)" \
    || { c_bad "به‌روزرسانی ناموفق — با کاربر مالک دیتابیس اجرا کنید"; exit 1; }

c_hint "اگر این وضعیت تکرار شد، ریشه‌اش در تست شبکه/زمان‌بندی است:"
c_hint "bash 03_ops/diagnose_n8n.sh"
