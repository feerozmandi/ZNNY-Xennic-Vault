#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — توابع مشترک کشف محیط (source می‌شود، اجرا نمی‌شود)
#
#   source "$(dirname "$0")/lib_common.sh"
#
# چرا؟ روی سرور واقعی این‌ها هیچ‌کدام پیش‌فرض نیستند و باید کشف شوند:
#   • نام کانتینر PostgreSQL  → xennic-infra-postgres-1
#   • نام کاربر دیتابیس        → n8n  (نه postgres)
#   • نام پروژه Compose        → xennic-infra
#   • دیتابیس برنامه           → هیچ‌کدام؛ باید ساخته شود
# ═══════════════════════════════════════════════════════════════════════

INFRA_DIR="${INFRA_DIR:-$HOME/xennic-infra}"
ENV_FILE="${ENV_FILE:-$INFRA_DIR/.env}"
PG_DB="${PG_DB:-xennic}"
PG_USER="${PG_USER:-}"
N8N_SERVICE="${N8N_SERVICE:-n8n}"
PG_SERVICE="${PG_SERVICE:-postgres}"

# ── انتخاب روش اجرای docker (با یا بدون sudo) ─────────────────────────
dk_detect() {
    if [[ -n "${DK:-}" ]]; then return 0; fi
    if ! command -v docker >/dev/null 2>&1; then DK=""; return 1; fi
    if docker info >/dev/null 2>&1; then
        DK="docker"
    elif sudo -n docker info >/dev/null 2>&1; then
        DK="sudo docker"
    else
        DK=""; return 1
    fi
    return 0
}

# ── کشف کانتینرها از docker ps (منبع حقیقت) ────────────────────────────
# برچسب سرویس compose اولویت دارد، بعد نام تصویر.
ct_detect() {
    dk_detect || { echo "docker در دسترس نیست" >&2; return 1; }

    if [[ -z "${PG_CT:-}" ]]; then
        PG_CT="$($DK ps --format '{{.Names}}\t{{.Image}}\t{{.Label "com.docker.compose.service"}}' 2>/dev/null |
                awk -F'\t' 'tolower($3) ~ /^(postgres|postgresql|db|database)$/ {print $1; exit}')"
    fi
    if [[ -z "${PG_CT:-}" ]]; then
        PG_CT="$($DK ps --format '{{.Names}}\t{{.Image}}' 2>/dev/null |
                awk -F'\t' 'tolower($2) ~ /postgres/ {print $1; exit}')"
    fi

    if [[ -z "${N8N_CT:-}" ]]; then
        N8N_CT="$($DK ps --format '{{.Names}}\t{{.Image}}\t{{.Label "com.docker.compose.service"}}' 2>/dev/null |
                 awk -F'\t' 'tolower($3) == "n8n" || tolower($2) ~ /n8n/ {print $1; exit}')"
    fi

    [[ -n "${PG_CT:-}" ]] || { echo "کانتینر PostgreSQL پیدا نشد" >&2; return 1; }
    return 0
}

# ── کشف کاربر دیتابیس ─────────────────────────────────────────────────
# ترتیب: متغیر محیطی → POSTGRES_USER داخل کانتینر → postgres
pg_user_detect() {
    [[ -n "${PG_USER:-}" ]] && return 0
    local u
    u="$($DK exec -i "$PG_CT" printenv POSTGRES_USER 2>/dev/null | tr -d '\r\n')"
    if [[ -n "$u" ]] && pg_can_login "$u"; then
        PG_USER="$u"; return 0
    fi
    if pg_can_login postgres; then
        PG_USER="postgres"; return 0
    fi
    PG_USER="${u:-postgres}"
    return 1
}

pg_can_login() {
    $DK exec -i "$PG_CT" psql -U "$1" -d postgres -X -t -A -c 'SELECT 1' >/dev/null 2>&1
}

# ── اجرای psql: pgq <db> [args...] ────────────────────────────────────
# رمز از env داخل کانتینر می‌آید (POSTGRES_PASSWORD) پس به رمز نیاز نداریم.
pgq() {
    local db="$1"; shift
    # کاربر دیتابیس در اولین فراخوانی کشف می‌شود (روی سرور «n8n» است، نه postgres)
    [[ -z "${PG_USER:-}" ]] && { dk_detect; ct_detect >/dev/null; pg_user_detect >/dev/null; }
    $DK exec -i "$PG_CT" psql -U "$PG_USER" -d "$db" -X -t -A "$@"
}

# خروجی جدول‌بندی‌شده برای گزارش چاپی (بدون -t -A)
pgq_pretty() {
    local db="$1"; shift
    [[ -z "${PG_USER:-}" ]] && { dk_detect; ct_detect >/dev/null; pg_user_detect >/dev/null; }
    $DK exec -i "$PG_CT" psql -U "$PG_USER" -d "$db" -X -P pager=off "$@"
}

pg_db_exists() {
    local name="$1"
    [[ "$(pgq postgres -c "SELECT 1 FROM pg_database WHERE datname = '$name'")" == "1" ]]
}

pg_db_create() {
    local name="$1"
    pg_db_exists "$name" && return 0
    # نام دیتابیس فقط حروف/عدد/زیرخط (جلوگیری از تزریق در DDL)
    if ! [[ "$name" =~ ^[a-z_][a-z0-9_]*$ ]]; then
        echo "نام دیتابیس نامعتبر: $name (فقط a-z، 0-9 و _)" >&2
        return 1
    fi
    pgq postgres -c "CREATE DATABASE \"$name\" ENCODING 'UTF8' TEMPLATE template0" >/dev/null
}

# ── خواندن یک کلید از .env بدون اجرای محتوا ────────────────────────────
env_get() {
    local key="$1"
    [[ -f "$ENV_FILE" ]] || return 1
    grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
}

# ── آدرس پایه بله از توکن (بدون چاپ توکن) ──────────────────────────────
# اولویت: BALE_API_URL → BALE_TOKEN_BOT → BALE_TOKEN → TELEGRAM_BOT_TOKEN
bale_url_detect() {
    local url token
    url="$(env_get BALE_API_URL || true)"
    if [[ -n "$url" ]] && printf '%s' "$url" | grep -qE '/bot[0-9]{6,}:'; then
        printf '%s' "$url"; return 0
    fi
    token="$(env_get BALE_TOKEN_BOT || true)"
    [[ -z "$token" ]] && token="$(env_get BALE_TOKEN || true)"
    [[ -z "$token" ]] && token="$(env_get TELEGRAM_BOT_TOKEN || true)"
    if [[ -n "$token" ]]; then
        printf 'https://tapi.bale.ai/bot%s' "$token"; return 0
    fi
    return 1
}

# ── پیام‌های رنگی ──────────────────────────────────────────────────────
c_ok()   { printf '  \033[32m✅\033[0m %s\n' "$*"; }
c_warn() { printf '  \033[33m⚠️ \033[0m %s\n' "$*"; }
c_bad()  { printf '  \033[31m❌\033[0m %s\n' "$*"; }
c_hint() { printf '     %s\n' "$*"; }
c_head() { printf '\n\033[1m%s\033[0m\n' "$*"; }
