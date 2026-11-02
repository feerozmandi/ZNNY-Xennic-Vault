#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — آماده‌سازی متغیرهای محیطی n8n
#
# چرا لازم است؟
#   گردش‌کارها توکن بله را از محیط می‌خوانند ($env.BALE_API_URL)، نه از فایل.
#   بدون این متغیر، گره «ارسال پاسخ» خطای 401/404 می‌دهد.
#
# اجرا:
#   bash 03_ops/setup_env.sh
#
# چه می‌کند؟
#   • توکن را با ورودی مخفی می‌پرسد (در تاریخچه شل و لاگ ذخیره نمی‌شود)
#   • از ~/xennic-infra/.env نسخه پشتیبان می‌گیرد
#   • فقط کلیدهای غایب را اضافه می‌کند (کلیدهای موجود دست‌نخورده می‌مانند)
#   • اگر پروژه Docker Compose فایل override نداشته باشد، یکی می‌سازد
#   • n8n را بازسازی می‌کند و تأیید می‌کند متغیر داخل کانتینر دیده می‌شود
#
# اجرای دوباره بی‌خطر است (idempotent).
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/03_ops/lib_common.sh"
INFRA_DIR="${INFRA_DIR:-$HOME/xennic-infra}"
ENV_FILE="${ENV_FILE:-$INFRA_DIR/.env}"
OVERRIDE="$INFRA_DIR/docker-compose.override.yml"
N8N_SERVICE="${N8N_SERVICE:-n8n}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

c_ok()   { printf '  \033[32m✅\033[0m %s\n' "$*"; }
c_warn() { printf '  \033[33m⚠️ \033[0m %s\n' "$*"; }
c_bad()  { printf '  \033[31m❌\033[0m %s\n' "$*"; }
c_hint() { printf '     %s\n' "$*"; }

echo "════ آماده‌سازی متغیرهای محیطی n8n ════"

if [[ ! -d "$INFRA_DIR" ]]; then
    c_bad "پوشه $INFRA_DIR پیدا نشد"
    c_hint "اگر جای دیگری است:  INFRA_DIR=/path/to/xennic-infra bash 03_ops/setup_env.sh"
    exit 1
fi
c_ok "پوشه زیرساخت: $INFRA_DIR"

# ── نوشتن/جایگزینی کلید در .env (بدون اجرای محتوا) ────────────────────
env_set() {
    local key="$1" value="$2"
    touch "$ENV_FILE"
    if grep -qE "^${key}=" "$ENV_FILE"; then
        # جایگزینی در همان خط، با حفظ سایر خطوط
        local tmp; tmp="$(mktemp)"
        awk -v k="$key" -v v="$value" '
            index($0, k "=") == 1 { print k "=" v; next }
            { print }
        ' "$ENV_FILE" > "$tmp" && mv "$tmp" "$ENV_FILE"
    else
        printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
    fi
}

# ── ۱) توکن بله ────────────────────────────────────────────────────────
# توکن ممکن است با هر یک از این نام‌ها در .env باشد
EXISTING_TOKEN="$(env_get BALE_TOKEN_BOT || true)"
[[ -z "$EXISTING_TOKEN" ]] && EXISTING_TOKEN="$(env_get BALE_TOKEN || true)"
[[ -z "$EXISTING_TOKEN" ]] && EXISTING_TOKEN="$(env_get TELEGRAM_BOT_TOKEN || true)"
EXISTING_URL="$(env_get BALE_API_URL || true)"

# اگر آدرس کامل از قبل هست، توکن را از آن بیرون می‌کشیم
if [[ -z "$EXISTING_TOKEN" && -n "$EXISTING_URL" ]]; then
    EXISTING_TOKEN="$(printf '%s' "$EXISTING_URL" | sed -n 's#.*/bot\([^/]*\)$#\1#p')"
fi

TOKEN_IN="${BALE_TOKEN_BOT:-$EXISTING_TOKEN}"
if [[ -n "$TOKEN_IN" ]]; then
    c_ok "توکن از .env خوانده شد (چاپ نمی‌شود)"
else
    echo ""
    echo "  توکن ربات «XennicNotifierbot» را وارد کنید."
    echo "  در بله: @BotFather → ربات → توکن (چیزی که نمایش داده نمی‌شود)"
    echo "  در .env فعلی کلید BALE_TOKEN_BOT خالی است."
    echo ""
    printf '  توکن: '
    read -rs TOKEN_IN
    echo ""
fi
TOKEN_IN="$(printf '%s' "$TOKEN_IN" | tr -d '[:space:]')"
if [[ -z "$TOKEN_IN" ]]; then
    c_bad "توکنی وارد نشد — بدون آن ارسال پیام بله ممکن نیست"
    exit 1
fi
if ! printf '%s' "$TOKEN_IN" | grep -qE '^[0-9]{5,}:[A-Za-z0-9_-]{20,}$'; then
    c_warn "قالب توکن معمول نیست (ادامه می‌دهیم؛ اگر ارسال شکست خورد همین را بررسی کنید)"
fi

# ── ۲) به‌روزرسانی .env (فقط کلیدهای غایب) ─────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
    cp -a "$ENV_FILE" "$ENV_FILE.bak-$STAMP"
    c_ok "نسخه پشتیبان: $ENV_FILE.bak-$STAMP"
fi

CHANGED=0
if [[ "$(env_get BALE_TOKEN_BOT || true)" != "$TOKEN_IN" ]]; then
    env_set BALE_TOKEN_BOT "$TOKEN_IN"; CHANGED=$((CHANGED+1))
    c_ok "BALE_TOKEN_BOT نوشته شد"
fi
for kv in "N8N_BLOCK_ENV_ACCESS_IN_NODE=false" "GENERIC_TIMEZONE=Asia/Tehran" "TZ=Asia/Tehran"; do
    k="${kv%%=*}"; v="${kv#*=}"
    if [[ "$(env_get "$k" || true)" != "$v" ]]; then
        env_set "$k" "$v"; CHANGED=$((CHANGED+1))
        c_ok "$k=$v"
    fi
done
[[ "$CHANGED" == "0" ]] && c_ok "همه کلیدهای لازم از قبل درست بودند"
chmod 600 "$ENV_FILE"

# ── ۳) فایل override (اگر n8n متغیر را از .env نگیرد) ──────────────────
if [[ -f "$OVERRIDE" ]]; then
    c_ok "docker-compose.override.yml موجود است (دست‌نخورده می‌ماند)"
else
    cp "$HERE/03_ops/docker-compose.override.yml" "$OVERRIDE"
    c_ok "docker-compose.override.yml ساخته شد"
fi

# ── ۴) بازسازی n8n و تأیید ─────────────────────────────────────────────
dc() { ( cd "$INFRA_DIR" && docker compose "$@" ); }

echo ""
echo "→ بازسازی سرویس n8n با متغیرهای جدید"
if ! dc up -d "$N8N_SERVICE" 2>&1 | tail -5; then
    c_bad "اجرای docker compose up -d ناموفق بود"
    exit 1
fi

echo "→ بررسی داخل کانتینر"
sleep 3
dk_detect || { c_bad "docker در دسترس نیست"; exit 1; }
ct_detect || true
N8N_CT="${N8N_CT:-$N8N_SERVICE}"

chk="$($DK exec -i "$N8N_CT" printenv BALE_API_URL 2>/dev/null | tr -d '\r')"
if [[ -n "$chk" ]] && printf '%s' "$chk" | grep -qE '/bot[0-9]{5,}:'; then
    c_ok "BALE_API_URL داخل کانتینر ساخته شد و توکن دارد (چاپ نمی‌شود)"
else
    c_bad "متغیر داخل کانتینر نیست"
    c_hint "بررسی: docker exec -i $N8N_CT printenv | grep -c BALE"
    c_hint "اگر compose پروژه دیگری داشته باشد، نام پروژه را بررسی کنید: docker compose ls"
    exit 1
fi
$DK exec -i "$N8N_CT" printenv N8N_BLOCK_ENV_ACCESS_IN_NODE 2>/dev/null | grep -q '^false$' \
    && c_ok "N8N_BLOCK_ENV_ACCESS_IN_NODE=false داخل کانتینر" \
    || { c_bad "N8N_BLOCK_ENV_ACCESS_IN_NODE داخل کانتینر false نیست"; exit 1; }

echo ""
echo "════ تمام ════"
cat <<'EOF'
  گام بعدی:
    bash 03_ops/preflight.sh          # باید همه سبز باشد
    bash 00_audit/audit_postgres.sh
EOF
