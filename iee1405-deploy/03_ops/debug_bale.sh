#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — گردش‌کار تشخیصی بله (IEE1405-99)
#
#   bash 03_ops/debug_bale.sh            # ایمپورت + دستور تونل
#   bash 03_ops/debug_bale.sh --remove   # حذف گردش‌کار تشخیصی
#
# چرا؟ در یک اجرا سه شکل درخواست به بله فرستاده می‌شود:
#   A) دقیقاً مثل wf-01 (sendQuery=keypair)   B) ساده (پارامتر در آدرس)   C) bare
# از روی اینکه کدام شاخه برمی‌گردد و کدام معلق می‌ماند، علت دقیق مشخص می‌شود.
# این گردش‌کار به هیچ جدولی نمی‌نویسد و فعال (Active) هم نمی‌شود.
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_common.sh
source "$HERE/lib_common.sh"

WF_ID="IEE1405-99"
WF_FILE="$HERE/../02_n8n/wf-debug-bale.json"
MODE="${1:-import}"

dk_detect || { c_bad "docker در دسترس نیست"; exit 1; }
ct_detect >/dev/null 2>&1 || { c_bad "کانتینر n8n پیدا نشد"; exit 1; }
[[ -n "${N8N_CT:-}" ]] || { c_bad "کانتینر n8n در حال اجرا نیست"; exit 1; }
n8n() { $DK exec -i "$N8N_CT" n8n "$@" </dev/null; }

if [[ "$MODE" == "--remove" ]]; then
    c_head "حذف گردش‌کار تشخیصی"
    n8n unpublish:workflow --id="$WF_ID" >/dev/null 2>&1 || true
    if n8n delete:workflow --id="$WF_ID" >/dev/null 2>&1; then
        c_ok "گردش‌کار $WF_ID حذف شد"
    else
        c_warn "دستور delete در این نسخه کار نکرد — از UI حذف کنید: Workflows → IEE1405-99"
    fi
    exit 0
fi

[[ -f "$WF_FILE" ]] || { c_bad "فایل $WF_FILE نیست"; exit 1; }

c_head "۱) ایمپورت گردش‌کار تشخیصی"
$DK exec -i "$N8N_CT" sh -c 'cat > /tmp/iee-debug.json' < "$WF_FILE"
n8n import:workflow --input=/tmp/iee-debug.json >/tmp/iee_dbg.log 2>&1
N8N_DB="$(n8n_db_detect)"
IN_DB=""
[[ -n "$N8N_DB" ]] && IN_DB="$(pgq "$N8N_DB" -c "SELECT count(*) FROM workflow_entity WHERE id = '$WF_ID'" 2>/dev/null | tr -d '[:space:]')"
if [[ "$IN_DB" == "1" ]]; then
    c_ok "گردش‌کار تشخیصی در n8n هست ($WF_ID)"
elif grep -qiE "success|imported" /tmp/iee_dbg.log; then
    c_ok "گردش‌کار تشخیصی ایمپورت شد ($WF_ID)"
else
    c_warn "ایمپورت تأیید نشد — خروجی:"
    tail -5 /tmp/iee_dbg.log | sed 's/^/     /'
    c_hint "در UI → Workflows ببینید؛ اگر نبود: bash 03_ops/import_workflows.sh import"
fi
$DK exec -i "$N8N_CT" sh -c 'rm -f /tmp/iee-debug.json' 2>/dev/null || true

c_head "۲) اجرا در UI"
cat <<'EOF'
  1. رابط را باز کنید:  bash 03_ops/open_ui.sh   (دستور تونل را چاپ می‌کند)
  2. در n8n → Workflows → «IEE1405-99 — آزمون اتصال بله (تشخیصی)»
  3. دکمه «Execute workflow» را بزنید (این گردش‌کار زمان‌بند ندارد و Active نیست)
  4. نتیجه سه شاخه را بخوانید:

     ✅ هر سه سبز         → گره HTTP سالم است؛ مشکل در جای دیگری از wf-01 است
                             (بخش ۳.۲ در diagnose_n8n.sh می‌گوید کدام گره)
     ✅ فقط B و C سبز      → ایراد از sendQuery/specifyQuery است → نسخه A را کنار می‌گذاریم
     ✅ فقط C سبز         → هر پارامتری مشکل دارد → پارامترها را با URL می‌سازیم
     ❌ هر سه گیر می‌کنند   → گره HTTP n8n با این دامنه سازگار نیست →
                             مسیر جای‌گزین: نود انجمن «bale» یا نود Telegram با Base URL

  5. اگر شاخه‌ای گیر کرد: روی همان گره کلیک کنید → پنل «Output/Error» پایین
     صفحه پیام دقیق را نشان می‌دهد. هر سه شاخه timeout دارند (۲۰/۱۰/۱۰ ثانیه)،
     پس اجرا بیشتر از یک دقیقه معطل نمی‌ماند.
EOF

c_head "۳) اگر هر سه گیر کردند"
cat <<'EOF'
  نود رسمی بله (بسته انجمن) — در UI: Settings → Community nodes → Install
    → نام بسته: n8n-nodes-bale
  سپس در گردش‌کار، گره «📥 دریافت پیام‌ها» با نود «Bale» و Action = Get Updates
  جای‌گزین می‌شود و کارت اعتبارنامه Bale API با همان توکن ساخته می‌شود.
  ⚠️ آن نود فعلاً پارامتر offset ندارد؛ برای تولید، نسخه HTTP نیاز به اصلاح دارد.
EOF
echo
c_hint "برای حذف بعد از پایان تشخیص: bash 03_ops/debug_bale.sh --remove"
