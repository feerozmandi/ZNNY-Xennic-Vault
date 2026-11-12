#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — بازخوانی آپدیت‌ها از بله
#
#   bash 03_ops/replay_updates.sh --dry-run   # فقط پیش‌نمایش، بدون تغییر
#   bash 03_ops/replay_updates.sh             # اجرای واقعی
#   bash 03_ops/replay_updates.sh --from 42   # از شناسه مشخص
#
# چرا ایمن است؟ جدول bot_updates کلید یکتا روی update_id دارد و پردازش با
# INSERT ... ON CONFLICT DO NOTHING شروع می‌شود. پس آپدیتی که قبلاً پردازش
# شده، در بازخوانی «duplicate» می‌شود و **دوباره پاسخ نمی‌گیرد**. فقط
# آپدیت‌هایی که واقعاً گم شده‌اند پردازش می‌شوند.
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_common.sh
source "$HERE/lib_common.sh"

MODE="run"; FROM="0"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) MODE="dry" ;;
        --from)    FROM="${2:-0}"; shift ;;
        *) c_bad "گزینه ناشناخته: $1"; exit 1 ;;
    esac
    shift
done

dk_detect || { c_bad "docker در دسترس نیست"; exit 1; }
ct_detect >/dev/null 2>&1 || { c_bad "کانتینر پیدا نشد"; exit 1; }
[[ -n "${N8N_CT:-}" ]] || { c_bad "کانتینر n8n در حال اجرا نیست"; exit 1; }

c_head "۱) وضعیت فعلی"
CUR="$(pgq "$PG_DB" -c "SELECT iee1405.poll_offset()" | tr -d '[:space:]')"
STORED="$(pgq "$PG_DB" -c "SELECT count(*) FROM iee1405.bot_updates" | tr -d '[:space:]')"
printf '  offset فعلی: %s · آپدیت‌های ثبت‌شده: %s\n' "${CUR:-?}" "${STORED:-?}"

c_head "۲) بله چه چیزی دارد؟ (فقط شمارش، بدون نمایش متن پیام)"
# از داخل کانتینر، چون curl در ایمیج n8n نیست
PROBE="$($DK exec -i "$N8N_CT" node -e '
const url = process.env.BALE_API_URL;
if (!url) { console.log("NORURL"); process.exit(0); }
(async () => {
  try {
    const r = await fetch(url + "/getUpdates?offset=0&limit=100&timeout=0",
                          { signal: AbortSignal.timeout(15000) });
    const j = await r.json();
    const ids = (j.result || []).map(u => u.update_id);
    console.log("IDS=" + ids.join(","));
    console.log("COUNT=" + ids.length);
    console.log("MAX=" + (ids.length ? Math.max(...ids) : 0));
  } catch (e) {
    console.log("ERR=" + (e.name || "") + ": " + (e.message || ""));
  }
})();
' 2>&1 | grep -E '^(IDS|COUNT|MAX|ERR|NORURL)=')"

if printf '%s' "$PROBE" | grep -q '^NORURL'; then
    c_bad "BALE_API_URL داخل کانتینر n8n نیست"
    c_hint "bash 03_ops/setup_env.sh"
    exit 1
fi
if printf '%s' "$PROBE" | grep -q '^ERR='; then
    c_bad "دریافت از بله ناموفق: $(printf '%s' "$PROBE" | sed -n 's/^ERR=//p')"
    exit 1
fi

REMOTE_COUNT="$(printf '%s' "$PROBE" | sed -n 's/^COUNT=//p')"
REMOTE_MAX="$(printf '%s' "$PROBE" | sed -n 's/^MAX=//p')"
IDS="$(printf '%s' "$PROBE" | sed -n 's/^IDS=//p')"
echo "  بله در حال حاضر ${REMOTE_COUNT:-0} آپدیت دارد (بزرگ‌ترین شناسه: ${REMOTE_MAX:-0})"

if [[ "${REMOTE_COUNT:-0}" -eq 0 ]]; then
    c_ok "بله هیچ آپدیتی ندارد — بازخوانی چیزی برای انجام دادن ندارد"
    c_hint "برای آزمون، در بله به ربات پیام بدهید (/status) و ۲۰ ثانیه صبر کنید"
    exit 0
fi

# کدام شناسه‌ها در دیتابیس نیستند؟ همان‌ها «گم‌شده» هستند
KNOWN="$(pgq "$PG_DB" -c "SELECT string_agg(update_id::text, ',') FROM iee1405.bot_updates")"
MISSING="$(python3 - "$IDS" "$KNOWN" <<'PY'
import sys
ids = [x for x in sys.argv[1].split(",") if x.strip()]
known = set(x for x in (sys.argv[2] or "").split(",") if x.strip())
missing = [i for i in ids if i.strip() not in known]
print(len(missing))
PY
)"

c_head "۳) نتیجه مقایسه"
echo "  آپدیت‌های موجود در بله : ${REMOTE_COUNT}"
echo "  آپدیت‌های ثبت‌شده ما   : ${STORED:-0}"
echo "  آپدیت‌های گم‌شده        : ${MISSING:-0}"

if [[ "${MISSING:-0}" -eq 0 ]]; then
    c_ok "همه آپدیت‌های بله در دیتابیس ما هستند — چیزی گم نشده"
    c_hint "اگر جوابی ارسال نشده، بخش ۳ و ۴ همین گزارش بالاتر را ببینید:"
    c_hint "bash 03_ops/inspect_state.sh"
else
    c_warn "${MISSING} آپدیت در بله هست که در دیتابیس ما نیست — بازخوانی این‌ها را نجات می‌دهد"
fi

if [[ "$MODE" == "dry" ]]; then
    c_head "۴) پیش‌نمایش (هیچ تغییری اعمال نشد)"
    echo "  با اجرای واقعی، offset از ${FROM} تنظیم می‌شود و گردش‌کار در چرخه بعد"
    echo "  این آپدیت‌ها را می‌گیرد. آپدیت‌های تکراری پاسخ دوباره نمی‌گیرند."
    c_hint "اجرای واقعی: bash 03_ops/replay_updates.sh --from ${FROM}"
    exit 0
fi

c_head "۴) اعمال"
NEWOFF="$(pgq "$PG_DB" -c "SELECT iee1405.poll_reset($FROM)" | tr -d '[:space:]')"
c_ok "offset روی $NEWOFF تنظیم شد (نشانگرهای کمکی هم صفر شدند)"
echo
echo "  حالا یکی از این دو:"
echo "    • ۲۰ ثانیه صبر کنید تا زمان‌بند اجرا شود"
echo "    • یا در UI روی گردش‌کار IEE1405-01 دکمه «Execute workflow» را بزنید"
echo
c_hint "بعد از اجرا وضعیت را ببینید: bash 03_ops/inspect_state.sh"
echo
