#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — ساخت اعتبارنامه و فعال‌سازی گردش‌کارها
#
# اجرا:
#   bash 03_ops/activate_all.sh
#
# چرا یک اسکریپت جدا؟
#   ایمپورت گردش‌کار، خودش کافی نیست. سه چیز باید درست انجام شود:
#     ۱. اعتبارنامه PostgreSQL در n8n وجود داشته باشد — وگرنه هر گره با
#        «credential not found» شکست می‌خورد.
#     ۲. گردش‌کار «منتشر» شود. در n8n نسخه ۲، دستور قدیمی
#        «update:workflow --active=true» منسوخ است و به publish:workflow
#        منتقل شده؛ استفاده از دستور قدیمی فقط هشدار می‌دهد.
#     ۳. n8n باید ری‌استارت شود. خود CLI هشدار می‌دهد:
#        «تغییرات تا زمانی که n8n در حال اجراست اثر نمی‌کند».
#
# اجرای دوباره بی‌خطر است (idempotent).
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib_common.sh"

CRED_ID="XENNIC-PG-CREDENTIAL"
CRED_NAME="Xennic PostgreSQL"
PASS_FILE="$HOME/.iee1405-app-password"

if ! dk_detect || ! ct_detect; then
    c_bad "Docker یا کانتینر n8n پیدا نشد"
    exit 1
fi
if [[ -z "${N8N_CT:-}" ]]; then
    c_bad "کانتینر n8n در حال اجرا نیست"
    c_hint "cd $INFRA_DIR && docker compose up -d n8n"
    exit 1
fi

n8n() { $DK exec -i "$N8N_CT" n8n "$@"; }

c_head "۱) اعتبارنامه PostgreSQL"

if [[ ! -f "$PASS_FILE" ]]; then
    c_bad "فایل رمز پیدا نشد: $PASS_FILE"
    c_hint "این فایل را اسکریپت استقرار می‌سازد. اگر ندارید، دوباره با رمز اجرا کنید:"
    c_hint "  APP_PASSWORD='<رمز>' bash 03_ops/deploy_sql.sh"
    exit 1
fi
APP_PASS="$(tr -d '\r\n' < "$PASS_FILE")"
[[ -z "$APP_PASS" ]] && { c_bad "فایل رمز خالی است"; exit 1; }

# بررسی وجود اعتبارنامه (export بدون رمز، فقط برای دیدن نام‌ها)
HAVE_CRED=0
if n8n export:credentials --all --output=/tmp/cred-check.json --decrypted=false >/dev/null 2>&1; then
    if $DK exec -i "$N8N_CT" sh -c 'cat /tmp/cred-check.json' 2>/dev/null | grep -q "\"$CRED_NAME\""; then
        HAVE_CRED=1
    fi
    $DK exec -i "$N8N_CT" sh -c 'rm -f /tmp/cred-check.json' 2>/dev/null || true
fi

if [[ "$HAVE_CRED" == "1" ]]; then
    c_ok "اعتبارنامه «$CRED_NAME» از قبل وجود دارد"
else
    echo "  ساخت اعتبارنامه «$CRED_NAME» (id ثابت، مطابق ارجاع گردش‌کارها)"
    # فایل اعتبارنامه فقط داخل کانتینر و فقط برای چند لحظه وجود دارد
    N8N_CT="$N8N_CT" CRED_ID="$CRED_ID" CRED_NAME="$CRED_NAME" \
    DB_HOST="postgres" DB_NAME="$PG_DB" DB_USER="iee_app" DB_PASS="$APP_PASS" \
    python3 -c '
import json, os
e = os.environ
cred = [{
    "id": e["CRED_ID"],
    "name": e["CRED_NAME"],
    "type": "postgres",
    "data": {
        "host": e["DB_HOST"],
        "database": e["DB_NAME"],
        "user": e["DB_USER"],
        "password": e["DB_PASS"],
        "port": 5432,
        "ssl": "disable",
        "maxConnections": 10
    }
}]
print(json.dumps(cred, ensure_ascii=False))
' | $DK exec -i "$N8N_CT" sh -c 'cat > /tmp/iee-cred.json && chmod 600 /tmp/iee-cred.json'

    if n8n import:credentials --input=/tmp/iee-cred.json 2>&1 | tee /tmp/iee-cred.out | grep -q "Successfully imported"; then
        c_ok "اعتبارنامه ساخته شد"
    else
        c_bad "ایمپورت اعتبارنامه ناموفق"
        tail -5 /tmp/iee-cred.out | sed 's/^/     /'
        $DK exec -i "$N8N_CT" sh -c 'rm -f /tmp/iee-cred.json' 2>/dev/null || true
        exit 1
    fi
    $DK exec -i "$N8N_CT" sh -c 'rm -f /tmp/iee-cred.json'
    c_ok "فایل موقت اعتبارنامه پاک شد"
fi

c_head "۲) انتشار گردش‌کارها"
# list:workflow خروجی «id|name» می‌دهد و سرستون ندارد — هر خط یک گردش‌کار
LIST="$(n8n list:workflow 2>/dev/null)"
if [[ -z "$LIST" ]]; then
    c_bad "فهرست گردش‌کارها خالی است — ایمپورت انجام شده؟"
    c_hint "bash 03_ops/import_workflows.sh import"
    exit 1
fi

COUNT=0
while IFS='|' read -r wid wname; do
    [[ -z "${wid:-}" ]] && continue
    case "$wname" in
        *IEE1405*) ;;
        *) continue ;;
    esac
    COUNT=$((COUNT + 1))
    printf '  → %s (%s) ' "$wname" "$wid"
    if n8n publish:workflow --id="$wid" >/tmp/iee_pub.log 2>&1; then
        echo "✅ منتشر شد"
    else
        echo "❌"
        tail -3 /tmp/iee_pub.log | sed 's/^/     /'
    fi
done <<< "$LIST"

if [[ "$COUNT" == "0" ]]; then
    c_bad "هیچ گردش‌کاری با پیشوند IEE1405 پیدا نشد"
    exit 1
fi
c_ok "$COUNT گردش‌کار منتشر شد"

c_head "۳) ری‌استارت n8n (لازم است تا انتشار اثر کند)"
if ( cd "$INFRA_DIR" && docker compose restart "$N8N_SERVICE" >/dev/null 2>&1 ); then
    c_ok "n8n ری‌استارت شد"
else
    c_warn "ری‌استارت با compose انجام نشد؛ تلاش با docker restart"
    $DK restart "$N8N_CT" >/dev/null 2>&1 && c_ok "n8n ری‌استارت شد" || c_bad "ری‌استارت ناموفق"
fi

echo "→ انتظار برای بالا آمدن n8n"
for i in $(seq 1 30); do
    if $DK exec -i "$N8N_CT" n8n --version >/dev/null 2>&1; then break; fi
    sleep 2
done
sleep 5
c_ok "n8n پاسخ می‌دهد"

c_head "۴) تأیید فعال بودن"
ACTIVE="$(n8n list:workflow --active=true 2>/dev/null | grep -c "IEE1405" || true)"
printf '  گردش‌کارهای فعال IEE1405: %s (انتظار: %s)\n' "${ACTIVE:-0}" "$COUNT"
if [[ "${ACTIVE:-0}" -ge "$COUNT" ]]; then
    c_ok "همه گردش‌کارها فعال هستند"
else
    c_warn "برخی گردش‌کارها فعال نشدند — در رابط n8n دکمه Active را بزنید"
    c_hint "http://127.0.0.1:5678 (از طریق تونل SSH)"
fi

c_head "۵) تأیید واقعی: آیا گردش‌کار به PostgreSQL وصل شده؟"
# اگر WF-01 در حال اجرا باشد، هر ۲۰ ثانیه last_poll_at را به‌روز می‌کند
BEFORE="$(pgq "$PG_DB" -c "SELECT coalesce(value,'-') FROM iee1405.bot_state WHERE key='last_poll_at'" 2>/dev/null | tr -d '[:space:]')"
echo "  انتظار ۳۰ ثانیه برای یک دور اجرای گردش‌کار..."
sleep 30
AFTER="$(pgq "$PG_DB" -c "SELECT coalesce(value,'-') FROM iee1405.bot_state WHERE key='last_poll_at'" 2>/dev/null | tr -d '[:space:]')"

if [[ "$AFTER" != "-" && "$AFTER" != "$BEFORE" ]]; then
    c_ok "گردش‌کار در حال اجراست (last_poll_at به‌روز شد)"
elif [[ "$AFTER" != "-" ]]; then
    c_warn "last_poll_at ثبت شده اما تازه نشد — ممکن است اجراها با خطا متوقف شده باشند"
    c_hint "bash 03_ops/smoke_test.sh   # جزئیات خطاها"
else
    c_warn "هنوز هیچ دور اجرایی ثبت نشده"
    c_hint "در رابط n8n → Executions ببینید؛ یا ۳۰ ثانیه بعد دوباره: bash 03_ops/smoke_test.sh"
fi

echo ""
echo "════ کار تمام شد ════"
echo "  حالا از گوشی خود به ربات «XennicNotifierbot» در بله /start بفرستید."
echo "  سپس:  bash 03_ops/smoke_test.sh"
