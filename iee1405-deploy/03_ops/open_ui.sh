#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — بازکردن رابط n8n روی لپ‌تاپ شما (از طریق تونل SSH)
#
#   bash 03_ops/open_ui.sh
#
# چرا تونل؟ n8n فقط روی 127.0.0.1 سرور گوش می‌دهد (قاعده امنیتی PRJ-IEE-007).
# پس مرورگر شما باید از طریق SSH به همان پورت برسد؛ هیچ پورتی عمومی نمی‌شود.
#
# این اسکریپت آدرس سرور و پورت SSH را از متغیر SSH_CONNECTION خودتان می‌خواند،
# بنابراین دستور چاپ‌شده **آماده کپی** است (هیچ جای‌نگهداری ندارد).
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_common.sh
source "$HERE/lib_common.sh"

c_head "۱) وضعیت سرویس n8n روی سرور"
if ! dk_detect; then
    c_bad "docker در دسترس نیست"
    exit 1
fi
ct_detect >/dev/null 2>&1 || { c_bad "کانتینر n8n پیدا نشد"; exit 1; }

if [[ -z "${N8N_CT:-}" ]]; then
    c_bad "کانتینر n8n در حال اجرا نیست"
    c_hint "cd $INFRA_DIR && docker compose up -d n8n"
    exit 1
fi

PORT_MAP="$($DK ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null | grep "^$N8N_CT" | head -1)"
echo "  $PORT_MAP"

if printf '%s' "$PORT_MAP" | grep -q "127.0.0.1:5678"; then
    c_ok "n8n روی 127.0.0.1:5678 سرور گوش می‌دهد (فقط از داخل سرور)"
else
    c_warn "نگاشت پورت 5678 در docker ps دیده نشد"
    c_hint "اگر از داخل سرور کار می‌کند ولی پورت نگاشت نشده، override را اعمال کنید:"
    c_hint "cp $HERE/docker-compose.override.yml $INFRA_DIR/ && cd $INFRA_DIR && docker compose up -d n8n"
fi

# پاسخ‌دهی HTTP از داخل سرور (curl ممکن است نصب نباشد → با python3)
if command -v curl >/dev/null 2>&1; then
    CODE="$(curl -s -o /dev/null -m 5 -w '%{http_code}' http://127.0.0.1:5678/rest/login 2>/dev/null)"
else
    CODE="$(python3 - <<'PY' 2>/dev/null
import urllib.request
try:
    with urllib.request.urlopen("http://127.0.0.1:5678/rest/login", timeout=5) as r:
        print(r.status)
except Exception as e:
    code = getattr(e, "code", None)
    print(code if code else "000")
PY
)"
fi
case "$CODE" in
    200|401|403) c_ok "رابط n8n از داخل سرور پاسخ می‌دهد (HTTP $CODE)" ;;
    *)           c_warn "پاسخ غیرمنتظره از رابط n8n: ${CODE:-—}" ;;
esac

c_head "۲) دستور تونل برای لپ‌تاپ شما"

TUNNEL_PORT="5678"
if [[ -n "${SSH_CONNECTION:-}" ]]; then
    # SSH_CONNECTION = "<client-ip> <client-port> <server-ip> <server-port>"
    read -r C_IP C_PORT S_IP S_PORT <<< "$SSH_CONNECTION"
    SSH_USER="$(whoami)"
    HOSTNAME_S="$(hostname 2>/dev/null)"
    echo "  در یک ترمینال **روی لپ‌تاپ خودتان** (نه روی سرور) این را اجرا کنید:"
    echo
    printf '     ssh -N -L %s:127.0.0.1:%s %s@%s -p %s\n\n' \
        "$TUNNEL_PORT" "$TUNNEL_PORT" "$SSH_USER" "$S_IP" "$S_PORT"
    c_hint "همان آدرسی که برای ssh به سرور استفاده می‌کنید را بگذارید؛ اگر $S_IP جواب نداد،"
    c_hint "از آدرس عمومی یا «$HOSTNAME_S» استفاده کنید (پورت SSH: $S_PORT)"
    c_hint "این پنجره را باز بگذارید؛ هیچ پیامی چاپ نشود = تونل برقرار است"
else
    c_warn "این جلسه از طریق SSH نیست (SSH_CONNECTION خالی است)"
    SSH_USER="$(whoami)"
    echo "  از لپ‌تاپ خودتان، با نام/آدرس سرور خودتان:"
    echo
    printf '     ssh -N -L %s:127.0.0.1:%s %s@<آدرس-سرور> -p <پورت-SSH>\n\n' \
        "$TUNNEL_PORT" "$TUNNEL_PORT" "$SSH_USER"
fi

c_head "۳) در مرورگر"
echo "  آدرس:  http://localhost:$TUNNEL_PORT"
c_hint "اگر صفحه ورود نیامد: (الف) تونل باز است؟ (ب) از داخل سرور پاسخ می‌دهد؟ بخش ۱"
c_hint "رمز ورود فراموش شده: فقط اگر کاربر ندارید، n8n صفحه «راه‌اندازی اولیه» نشان می‌دهد"

c_head "۴) مسیر پیشنهادی در UI (گام‌به‌گام)"
cat <<'EOF'
  1. Workflows → «IEE1405-01 — دریافت پیام‌های بله» را باز کنید
  2. روی گره «📍 خواندن offset» دوبار کلیک → دکمه «Execute step» (اجرای تک‌گره)
     ✓ خروجی: یک ردیف با offset (=0). یعنی اعتبارنامه PostgreSQL سالم است.
  3. همان کار را برای «💓 ضربان دریافت» تکرار کنید
     ✓ باید یک timestamp برگردد؛ در همان لحظه bot_state هم به‌روز می‌شود.
  4. حالا «📥 دریافت پیام‌ها» → «Execute step»
     • اگر ۲۰ ثانیه بعد خطا/پایان داد → مشکل قبلی از بین رفته؛ ادامه زنجیره
     • اگر بی‌پایان «Executing…» ماند → همین گره مقصر است؛ پیامش را بفرستید
       (پایین پنل، بخش Output/Error و همچنین «Details» نشان می‌دهد)
  5. اگر گیر کرد: همان گره را باز کنید → Options → Timeout را ۵۰۰۰ بگذارید و
     دوباره Execute step؛ اگر این بار تمام شد، مشکل «بدون timeout» بوده است.
  6. بعد از رفع، همان گردش‌کار را Save کنید و از دکمه «Active» مطمئن شوید.
EOF

c_head "۵) یک گردش‌کار تشخیصی (اختیاری، بدون دست‌زدن به تولید)"
echo "  bash 03_ops/debug_bale.sh    # سه گره موازی: دقیقاً مثل wf-01، ساده، و bare"
echo
