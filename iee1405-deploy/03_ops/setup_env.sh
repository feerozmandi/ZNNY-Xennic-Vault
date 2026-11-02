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
INFRA_DIR="${INFRA_DIR:-$HOME/xennic-infra}"
ENV_FILE="$INFRA_DIR/.env"
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

# ── ۱) توکن بله ────────────────────────────────────────────────────────
EXISTING_TOKEN=""
if [[ -f "$ENV_FILE" ]]; then
    EXISTING_TOKEN="$(grep -E '^BALE_API_URL=' "$ENV_FILE" | tail -1 | cut -d= -f2- || true)"
fi

if [[ -n "${BALE_API_URL:-}" ]]; then
    TOKEN_URL="$BALE_API_URL"
    c_ok "BALE_API_URL از متغیر محیطی خوانده شد"
elif [[ -n "$EXISTING_TOKEN" ]] && printf '%s' "$EXISTING_TOKEN" | grep -q 'tapi\.bale\.ai/bot'; then
    TOKEN_URL="$EXISTING_TOKEN"
    c_ok "BALE_API_URL از قبل در .env هست (دست‌نخورده می‌ماند)"
else
    echo ""
    echo "  توکن ربات بله را وارد کنید."
    echo "  (در بله: @BotFather → ربات خود → توکن؛ چیزی که نمایش داده نمی‌شود)"
    echo "  قالب: 123456789:AAE...xyz"
    echo ""
    printf '  توکن: '
    read -rs TOKEN_IN
    echo ""
    TOKEN_IN="$(printf '%s' "$TOKEN_IN" | tr -d '[:space:]')"
    if [[ -z "$TOKEN_IN" ]]; then
        c_bad "توکنی وارد نشد"
        exit 1
    fi
    if ! printf '%s' "$TOKEN_IN" | grep -qE '^[0-9]{6,}:[A-Za-z0-9_-]{20,}$'; then
        c_warn "قالب توکن معمول نیست (ادامه می‌دهیم؛ اگر ارسال شکست خورد همین را بررسی کنید)"
    fi
    TOKEN_URL="https://tapi.bale.ai/bot${TOKEN_IN}"
fi

# ── ۲) به‌روزرسانی .env (فقط کلیدهای غایب) ─────────────────────────────
NEED=()
grep -qE '^BALE_API_URL=' "$ENV_FILE" 2>/dev/null || NEED+=("BALE_API_URL=$TOKEN_URL")
grep -qE '^N8N_BLOCK_ENV_ACCESS_IN_NODE=' "$ENV_FILE" 2>/dev/null || NEED+=("N8N_BLOCK_ENV_ACCESS_IN_NODE=false")
grep -qE '^GENERIC_TIMEZONE=' "$ENV_FILE" 2>/dev/null || NEED+=("GENERIC_TIMEZONE=Asia/Tehran")
grep -qE '^TZ=' "$ENV_FILE" 2>/dev/null || NEED+=("TZ=Asia/Tehran")

if [[ ${#NEED[@]} -eq 0 ]]; then
    c_ok "همه کلیدهای لازم از قبل در .env هستند"
else
    if [[ -f "$ENV_FILE" ]]; then
        cp -a "$ENV_FILE" "$ENV_FILE.bak-$STAMP"
        c_ok "نسخه پشتیبان: $ENV_FILE.bak-$STAMP"
    fi
    {
        echo ""
        echo "# ── IEE 1405 — افزوده‌شده در $(date -u '+%Y-%m-%d %H:%M UTC') ──"
        printf '%s\n' "${NEED[@]}"
    } >> "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    c_ok "${#NEED[@]} کلید اضافه شد: $(printf '%s ' "${NEED[@]%%=*}")"
fi

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
N8N_CT="$(dc ps --format '{{.Names}}' "$N8N_SERVICE" 2>/dev/null | head -1)"
[[ -z "$N8N_CT" ]] && N8N_CT="$N8N_SERVICE"

chk="$(docker exec -i "$N8N_CT" printenv BALE_API_URL 2>/dev/null | tr -d '\r')"
if [[ -n "$chk" ]]; then
    c_ok "BALE_API_URL داخل کانتینر دیده می‌شود (مقدار چاپ نمی‌شود)"
else
    c_bad "متغیر داخل کانتینر نیست"
    c_hint "بررسی: docker exec -i $N8N_CT printenv | grep -c BALE"
    c_hint "اگر compose پروژه دیگری داشته باشد، نام پروژه را بررسی کنید: docker compose ls"
    exit 1
fi
docker exec -i "$N8N_CT" printenv N8N_BLOCK_ENV_ACCESS_IN_NODE 2>/dev/null | grep -q '^false$' \
    && c_ok "N8N_BLOCK_ENV_ACCESS_IN_NODE=false داخل کانتینر" \
    || { c_bad "N8N_BLOCK_ENV_ACCESS_IN_NODE داخل کانتینر false نیست"; exit 1; }

echo ""
echo "════ تمام ════"
cat <<'EOF'
  گام بعدی:
    bash 03_ops/preflight.sh          # باید همه سبز باشد
    bash 00_audit/audit_postgres.sh
EOF
