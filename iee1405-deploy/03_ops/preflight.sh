#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — بررسی پیش‌نیازها قبل از استقرار (فقط خواندن)
#
# اجرا روی VPS، از داخل پوشه iee1405-deploy:
#   bash 03_ops/preflight.sh
#
# چه می‌کند؟
#   • تأیید می‌کند روی خودِ سرور هستید و فایل‌ها سرِ جایشان هستند
#   • کانتینرهای واقعی را از «docker ps» می‌خواند (نه از compose ps که در
#     نسخه‌های مختلف compose رفتار متفاوت دارد)
#   • کانتینر PostgreSQL را پیدا می‌کند، حتی اگر نام سرویس «postgres» نباشد
#   • اگر PostgreSQL بالا نیست، لاگ خطای آن را نشان می‌دهد
#   • نام واقعی دیتابیس، نسخه n8n و وضعیت متغیرهای لازم را چاپ می‌کند
#   • در پایان، دستور بعدی را با مقادیر واقعی آماده می‌کند
#
# هیچ چیزی تغییر نمی‌دهد: فقط SELECT، docker ps/logs و خواندن فایل.
# گزینه‌های دستی:
#   PG_CONTAINER=<name> N8N_CONTAINER=<name> bash 03_ops/preflight.sh
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/03_ops/lib_common.sh"
INFRA_DIR="${INFRA_DIR:-$HOME/xennic-infra}"
COMPOSE_FILE="${COMPOSE_FILE:-$INFRA_DIR/docker-compose.yml}"

C_OK=0; C_WARN=0; C_FAIL=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$*"; C_OK=$((C_OK+1)); }
warn() { printf '  \033[33m⚠️ \033[0m %s\n' "$*"; C_WARN=$((C_WARN+1)); }
bad()  { printf '  \033[31m❌\033[0m %s\n' "$*"; C_FAIL=$((C_FAIL+1)); }
head_(){ printf '\n\033[1m%s\033[0m\n' "$*"; }
hint() { printf '     %s\n' "$*"; }

DK=""
DB_FOUND=""
PG_CT=""
N8N_CT=""
PG_USER_OK=""

# ── ۲) Docker ──────────────────────────────────────────────────────────
head_ "۱) Docker"
if ! command -v docker >/dev/null 2>&1; then
    bad "docker نصب نیست یا در PATH نیست"
    hint "اگر روی لپ‌تاپ هستید، اول وارد سرور شوید؛ این اسکریپت باید روی سرور اجرا شود."
else
    if docker info >/dev/null 2>&1; then
        DK="docker"; ok "دِمون Docker در دسترس است"
    elif sudo -n docker info >/dev/null 2>&1; then
        DK="sudo docker"; warn "Docker فقط با sudo کار می‌کند"
        hint "راه‌حل: sudo usermod -aG docker $(whoami) سپس خروج و ورود مجدد"
    else
        bad "به دِمون Docker دسترسی نیست"
        hint "بررسی: groups  →  باید docker داشته باشد"
    fi
fi

# ── ۲) کانتینرها: منبع حقیقت = docker ps ───────────────────────────────
head_ "۲) کانتینرهای واقعی"
if [[ -n "$DK" ]]; then
    fmt='{{.Names}}\t{{.Image}}\t{{.State}}\t{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.service"}}'
    ALL="$($DK ps -a --format "$fmt" 2>/dev/null)"
    RUNNING="$($DK ps --format "$fmt" 2>/dev/null)"
    if [[ -z "$RUNNING" ]]; then
        bad "هیچ کانتینری در حال اجرا نیست"
        if [[ -n "$ALL" ]]; then
            hint "کانتینرهای متوقف‌شده:"
            printf '%s\n' "$ALL" | while IFS=$'\t' read -r n i s p sv; do
                hint "  $n ($i) — $s"
            done
        fi
        hint "راه‌اندازی:  cd $INFRA_DIR && docker compose up -d"
    else
        ok "کانتینرهای در حال اجرا:"
        printf '%s\n' "$RUNNING" | while IFS=$'\t' read -r n i s p sv; do
            hint "  $n  ·  $i  ·  سرویس: ${sv:-—}  ·  پروژه: ${p:-—}"
        done
    fi
fi

# ── انتخاب کانتینر PostgreSQL ──────────────────────────────────────────
if [[ -n "$DK" ]]; then
    if [[ -n "${PG_CONTAINER:-}" ]]; then
        PG_CT="$PG_CONTAINER"
    else
        # اول از روی برچسب سرویس، بعد از روی تصویر
        PG_CT="$($DK ps --format '{{.Names}}\t{{.Image}}\t{{.Label "com.docker.compose.service"}}' 2>/dev/null |
                awk -F'\t' 'tolower($3)=="postgres"||tolower($3)=="postgresql"||tolower($3)=="db"{print $1; exit}')"
        if [[ -z "$PG_CT" ]]; then
            PG_CT="$($DK ps --format '{{.Names}}\t{{.Image}}' 2>/dev/null |
                    awk -F'\t' 'tolower($2) ~ /postgres/ {print $1; exit}')"
        fi
    fi
    if [[ -n "$PG_CT" ]]; then
        ok "کانتینر PostgreSQL: $PG_CT"
    else
        bad "هیچ کانتینر PostgreSQL در حال اجرایی پیدا نشد"
        hint "اگر نامش را می‌دانید:  PG_CONTAINER=<name> bash 03_ops/preflight.sh"
    fi
fi

# ── انتخاب کانتینر n8n ─────────────────────────────────────────────────
if [[ -n "$DK" ]]; then
    if [[ -n "${N8N_CONTAINER:-}" ]]; then
        N8N_CT="$N8N_CONTAINER"
    else
        N8N_CT="$($DK ps --format '{{.Names}}\t{{.Image}}\t{{.Label "com.docker.compose.service"}}' 2>/dev/null |
                 awk -F'\t' 'tolower($3)=="n8n"||tolower($2) ~ /n8n/ {print $1; exit}')"
    fi
    [[ -n "$N8N_CT" ]] && ok "کانتینر n8n: $N8N_CT" || warn "کانتینر n8n در حال اجرا نیست"
fi

# ── ۳) PostgreSQL ──────────────────────────────────────────────────────
head_ "۳) PostgreSQL"
pgq() { $DK exec -i "$PG_CT" psql -U "$PG_USER_OK" -X -t -A "$@" 2>&1; }

if [[ -n "$PG_CT" ]]; then
    # کاربر دیتابیس: postgres یا مقدار POSTGRES_USER داخل کانتینر
    for u in postgres "$($DK exec -i "$PG_CT" printenv POSTGRES_USER 2>/dev/null | tr -d '\r')"; do
        [[ -z "$u" ]] && continue
        if $DK exec -i "$PG_CT" psql -U "$u" -X -t -A -c 'SELECT 1' >/dev/null 2>&1; then
            PG_USER_OK="$u"; break
        fi
    done
    if [[ -z "$PG_USER_OK" ]]; then
        bad "psql با کاربر postgres داخل «$PG_CT» جواب نداد"
        hint "۲۰ خط آخر لاگ کانتینر:"
        $DK logs --tail 20 "$PG_CT" 2>&1 | sed 's/^/       /' | tail -20
        hint "اگر در لاگ «database system is starting up» یا خطای دیسک بود، صبر کنید/فضا را بررسی کنید."
    else
        ver="$(pgq -c 'SHOW server_version' | tr -d '[:space:]')"
        ok "PostgreSQL $ver · کاربر «$PG_USER_OK» · کانتینر «$PG_CT»"
        dbs="$(pgq -c "SELECT datname FROM pg_database WHERE NOT datistemplate ORDER BY 1")"
        hint "دیتابیس‌ها: $(printf '%s' "$dbs" | tr '\n' ' ')"
        if printf '%s\n' "$dbs" | grep -qx 'xennic'; then
            DB_FOUND="xennic"
            ok "دیتابیس اختصاصی «xennic» موجود است"
        else
            DB_FOUND="xennic"
            warn "دیتابیس اختصاصی «xennic» وجود ندارد — در گام استقرار ساخته می‌شود"
            hint "دیتابیس «n8n» دست نمی‌خورد؛ هیچ دیتابیس موقت نمایشگاهی ساخته نمی‌شود."
        fi
        # ساختار از قبل؟
        for db in $dbs; do
            n="$($DK exec -i "$PG_CT" psql -U "$PG_USER_OK" -d "$db" -X -t -A \
                 -c "SELECT count(*) FROM pg_tables WHERE schemaname IN ('crm','iee1405')" 2>/dev/null | tr -d '[:space:]')"
            n="${n:-0}"
            if [[ -n "$n" && "$n" != "0" ]]; then
                warn "در «$db» تعداد $n جدول crm/iee1405 از قبل هست (استقرار مجدد بی‌خطر است)"
            fi
        done
        # پورت عمومی
        if $DK ps --format '{{.Ports}}' 2>/dev/null | grep -q '0\.0\.0\.0:5432'; then
            bad "پورت ۵۴۳۲ روی همه اینترفیس‌ها باز است — باید فقط 127.0.0.1 باشد"
        else
            ok "پورت PostgreSQL روی اینترنت باز نیست"
        fi
    fi
else
    warn "اتصال PostgreSQL آزمایش نشد"
fi

# ── ۴) n8n ─────────────────────────────────────────────────────────────
head_ "۴) n8n"
if [[ -n "$N8N_CT" ]]; then
    n8nv="$($DK exec -i "$N8N_CT" n8n --version 2>/dev/null | tr -d '\r' | tail -1)"
    if [[ -n "$n8nv" ]]; then
        ok "نسخه n8n: $n8nv"
        major_minor="$(printf '%s' "$n8nv" | grep -oE '^[0-9]+\.[0-9]+' || true)"
        if [[ -n "$major_minor" ]]; then
            mm_major="${major_minor%%.*}"; mm_minor="${major_minor##*.}"
            if (( mm_major > 1 )) || (( mm_major == 1 && mm_minor >= 60 )); then
                ok "نسخه برای typeVersion های گردش‌کارها کافی است (postgres 2.6 · schedule 1.3 · splitOut 1 · http 4.2)"
            else
                warn "n8n قدیمی است؛ گره‌های گردش‌کار ممکن است ایمپورت نشوند"
                hint "به‌روزرسانی: cd $INFRA_DIR && docker compose pull n8n && docker compose up -d n8n"
            fi
        fi
    else
        warn "نسخه n8n خوانده نشد"
        $DK logs --tail 10 "$N8N_CT" 2>&1 | sed 's/^/       /'
    fi

    envs="$($DK exec -i "$N8N_CT" printenv 2>/dev/null | grep -E '^(BALE_API_URL|N8N_BLOCK_ENV_ACCESS_IN_NODE|GENERIC_TIMEZONE|TZ)=' || true)"
    u="$(printf '%s\n' "$envs" | grep '^BALE_API_URL=' | cut -d= -f2- || true)"
    if printf '%s' "$u" | grep -qE '^https://tapi\.bale\.ai/bot[0-9]{5,}:'; then
        ok "BALE_API_URL با توکن معتبر تنظیم شده است (محرمانه، چاپ نمی‌شود)"
    elif [[ -n "$u" ]]; then
        bad "BALE_API_URL هست اما توکن ندارد (احتمالاً BALE_TOKEN_BOT در .env خالی است)"
        hint "راه‌حل:  bash 03_ops/setup_env.sh"
    else
        bad "BALE_API_URL در سرویس n8n تعریف نشده — ارسال پیام بله کار نمی‌کند"
        hint "راه‌حل خودکار:  bash 03_ops/setup_env.sh"
    fi
    tk="$(env_get BALE_TOKEN_BOT || true)"
    [[ -z "$tk" ]] && bad "BALE_TOKEN_BOT در .env خالی است (منبع توکن همین کلید است)" \
                   || ok "BALE_TOKEN_BOT در .env پر است"
    printf '%s' "$envs" | grep -q '^N8N_BLOCK_ENV_ACCESS_IN_NODE=false' \
        && ok "N8N_BLOCK_ENV_ACCESS_IN_NODE=false" \
        || { bad "N8N_BLOCK_ENV_ACCESS_IN_NODE=false نیست — \$env در دسترس نیست"; hint "راه‌حل خودکار:  bash 03_ops/setup_env.sh"; }
    if printf '%s\n' "$envs" | grep -qE '^(GENERIC_TIMEZONE|TZ)=Asia/Tehran'; then
        ok "منطقه زمانی تهران تنظیم است"
    else
        warn "GENERIC_TIMEZONE=Asia/Tehran نیست — ساعت گزارش‌ها جابه‌جا می‌شود"
    fi
else
    warn "n8n بالا نیست؛ بخش متغیرها آزمایش نشد"
fi

# ── ۵) فضای دیسک ───────────────────────────────────────────────────────
head_ "۵) فضای دیسک"
avail="$(df -h / 2>/dev/null | awk 'NR==2{print $4}')"
printf '  فضای آزاد ریشه: %s\n' "${avail:-نامشخص}"
free_g="$(printf '%s' "${avail:-}" | sed 's/[^0-9.]//g')"
if [[ -n "$free_g" ]] && awk -v g="$free_g" 'BEGIN{exit !(g < 5)}'; then
    warn "فضای دیسک کم است (زیر ۵ گیگابایت)"
else
    ok "فضای دیسک کافی است"
fi

# ── ۶) نتیجه ───────────────────────────────────────────────────────────
head_ "نتیجه"
printf '  موفق: %d · هشدار: %d · خطا: %d\n' "$C_OK" "$C_WARN" "$C_FAIL"
echo ""

if [[ -z "$PG_USER_OK" ]]; then
    printf '  \033[33mاول PostgreSQL را بالا بیاورید، بعد دوباره این اسکریپت را اجرا کنید:\033[0m\n\n'
    cat <<EOF
     cd $INFRA_DIR
     docker compose up -d
     docker compose ps
     cd ~/ZNNY-Xennic-Vault/iee1405-deploy && bash 03_ops/preflight.sh
EOF
    exit 1
fi

DB_ARG="${DB_FOUND:-xennic}"
cat <<EOF
  کانتینر: ${PG_CT:-?} · کاربر دیتابیس: ${PG_USER_OK:-${PG_USER:-?}}

  دستورهای بعدی (به همین ترتیب):

  ۱) اگر BALE_API_URL یا N8N_BLOCK_ENV_ACCESS_IN_NODE خطا داشت:
     bash 03_ops/setup_env.sh

  ۲) بازرسی کامل و ثبت گزارش:
     bash 00_audit/audit_postgres.sh

  ۳) استقرار ساختار و منطق (دیتابیس «$DB_ARG» در صورت نبود ساخته می‌شود):
     APP_PASSWORD="\$(openssl rand -base64 18)" bash 03_ops/deploy_sql.sh

  ۴) ایمپورت گردش‌کارها:
     bash 03_ops/import_workflows.sh import

  ۵) در رابط n8n: کارت «Xennic PostgreSQL» بسازید
     (میزبان: postgres · دیتابیس: $DB_ARG · کاربر: iee_app)

  ۶) فعال‌سازی:
     bash 03_ops/import_workflows.sh activate
EOF
