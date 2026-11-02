#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — بررسی پیش‌نیازها قبل از استقرار (فقط خواندن)
#
# اجرا روی VPS، از داخل پوشه iee1405-deploy:
#   bash 03_ops/preflight.sh
#
# چه می‌کند؟
#   • تأیید می‌کند روی خودِ سرور هستید (نه روی لپ‌تاپ)
#   • مسیر درست فایل‌ها را بررسی می‌کند (خطای «No such file» را ریشه‌یابی می‌کند)
#   • دسترسی Docker و فایل docker-compose را پیدا می‌کند
#   • نام واقعی کانتینرها، نام دیتابیس و نسخه n8n را چاپ می‌کند
#   • در پایان، دستور دقیق بعدی را با مقادیر واقعی آماده می‌کند
#
# هیچ چیزی تغییر نمی‌دهد: فقط SELECT، docker ps و خواندن فایل.
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="${INFRA_DIR:-$HOME/xennic-infra}"
COMPOSE_FILE="${COMPOSE_FILE:-$INFRA_DIR/docker-compose.yml}"
PG_SERVICE="${PG_SERVICE:-postgres}"
N8N_SERVICE="${N8N_SERVICE:-n8n}"

C_OK=0; C_WARN=0; C_FAIL=0
ok()   { printf '  \033[32m✅\033[0m %s\n' "$*"; C_OK=$((C_OK+1)); }
warn() { printf '  \033[33m⚠️ \033[0m %s\n' "$*"; C_WARN=$((C_WARN+1)); }
bad()  { printf '  \033[31m❌\033[0m %s\n' "$*"; C_FAIL=$((C_FAIL+1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$*"; }

step() { printf '\n▸ %s\n' "$*"; }

DB_FOUND=""
NEXT_CMD=""

# ── ۱) کجا هستیم؟ ──────────────────────────────────────────────────────
head_ "۱) محل اجرا"
printf '  میزبان: %s · کاربر: %s\n' "$(hostname)" "$(whoami)"
printf '  مسیر:   %s\n' "$HERE"
if [[ -f "$HERE/01_sql/04_bot_logic.sql" && -f "$HERE/00_audit/audit.sql" ]]; then
    ok "فایل‌های بسته کامل است (01_sql، 00_audit موجودند)"
else
    bad "این پوشه بسته استقرار نیست — فایل 01_sql/04_bot_logic.sql پیدا نشد"
    printf '     احتمالاً git clone انجام نشده یا از پوشه اشتباه اجرا شده است.\n'
    printf '     مسیر درست: ~/ZNNY-Xennic-Vault/iee1405-deploy\n'
fi
if [[ -f "$HERE/02_n8n/wf-01-bale-ingest.json" ]]; then
    ok "گردش‌کارهای n8n موجودند (۴ فایل)"
else
    bad "فایل‌های گردش‌کار n8n موجود نیستند"
fi

# آیا روی سرور هستیم؟ (وجود docker + پوشه infra نشانه سرور است)
ON_SERVER=0
command -v docker >/dev/null 2>&1 && ON_SERVER=1

# ── ۲) Docker ──────────────────────────────────────────────────────────
head_ "۲) Docker"
if ! command -v docker >/dev/null 2>&1; then
    bad "docker نصب نیست یا در PATH نیست"
    printf '     اگر روی لپ‌تاپ هستید: اول ssh بزنید به سرور، بعد این اسکریپت را اجرا کنید.\n'
    printf '     ssh -p 33878 xennic@185.192.113.199\n'
else
    if docker info >/dev/null 2>&1; then
        ok "دِمون Docker در دسترس است"
    elif sudo -n docker info >/dev/null 2>&1; then
        warn "Docker فقط با sudo کار می‌کند"
        printf '     راه‌حل: sudo usermod -aG docker %s  سپس خروج و ورود مجدد\n' "$(whoami)"
    else
        bad "به دِمون Docker دسترسی نیست (کاربر در گروه docker نیست؟)"
        printf '     بررسی: groups  →  باید docker داشته باشد\n'
    fi
fi

# ── ۳) فایل compose و کانتینرها ────────────────────────────────────────
head_ "۳) پشته Docker"
if [[ -f "$COMPOSE_FILE" ]]; then
    ok "docker-compose یافت شد: $COMPOSE_FILE"
else
    warn "docker-compose در مسیر پیش‌فرض نیست: $COMPOSE_FILE"
    found_compose="$(ls -1 "$HOME"/*/docker-compose.yml /opt/*/docker-compose.yml 2>/dev/null | head -3)"
    if [[ -n "$found_compose" ]]; then
        printf '     گزینه‌های یافت‌شده:\n'
        printf '       %s\n' $found_compose
        COMPOSE_FILE="$(printf '%s\n' $found_compose | head -1)"
        printf '     استفاده از: %s\n' "$COMPOSE_FILE"
        printf '     برای انتخاب دستی: COMPOSE_FILE=/path/docker-compose.yml bash 03_ops/preflight.sh\n'
    fi
fi

if [[ -f "$COMPOSE_FILE" ]] && command -v docker >/dev/null 2>&1; then
    # از پوشه infra اجرا می‌شود تا docker-compose.override.yml و .env هم خوانده شوند
    dc() { ( cd "$INFRA_DIR" && docker compose "$@" ); }
    if "${COMPOSE[@]}" ps >/dev/null 2>&1; then
        running="$("${COMPOSE[@]}" ps --services --filter status=running 2>/dev/null | sort | tr '\n' ' ')"
        if [[ -n "${running// /}" ]]; then
            ok "سرویس‌های در حال اجرا: $running"
        else
            bad "هیچ سرویسی در حال اجرا نیست — docker compose up -d"
        fi
        for svc in "$PG_SERVICE" "$N8N_SERVICE"; do
            if printf '%s\n' "$running" | grep -qw "$svc"; then
                ok "سرویس «$svc» بالاست"
            else
                warn "سرویس «$svc» در حال اجرا نیست"
            fi
        done
    else
        bad "docker compose با این فایل کار نمی‌کند (خطای compose را ببینید)"
    fi
fi

# ── ۴) PostgreSQL ──────────────────────────────────────────────────────
head_ "۴) PostgreSQL"
pgq() { ( cd "$INFRA_DIR" && docker compose exec -T "$PG_SERVICE" psql -U postgres -X -t -A "$@" ); }

if [[ -f "$COMPOSE_FILE" ]] && command -v docker >/dev/null 2>&1; then
    if ver="$(pgq -c 'SHOW server_version' 2>/dev/null)"; then
        ok "اتصال به PostgreSQL برقرار است (نسخه $ver)"
        dbs="$(pgq -c "SELECT datname FROM pg_database WHERE NOT datistemplate ORDER BY 1" 2>/dev/null)"
        printf '     دیتابیس‌ها: %s\n' "$(printf '%s' "$dbs" | tr '\n' ' ')"
        # دیتابیس پیشنهادی
        if printf '%s\n' "$dbs" | grep -qx 'xennic'; then
            DB_FOUND="xennic"
        else
            cand="$(printf '%s\n' "$dbs" | grep -vxE 'postgres|n8n|n8n_data' | head -1)"
            DB_FOUND="${cand:-postgres}"
            if [[ -n "$cand" ]]; then
                warn "دیتابیس «xennic» نیست؛ پیشنهاد استفاده از «$cand»"
            fi
        fi
        # آیا ساختار از قبل هست؟
        for db in $dbs; do
            n="$(pgq -d "$db" -c "SELECT count(*) FROM pg_tables WHERE schemaname IN ('crm','iee1405')" 2>/dev/null)"
            if [[ -n "$n" && "$n" != "0" ]]; then
                warn "در دیتابیس «$db» تعداد $n جدول crm/iee1405 از قبل وجود دارد (استقرار مجدد آن‌ها را بازنویسی نمی‌کند)"
            fi
        done
        # پورت عمومی؟
        if dc ps 2>/dev/null | grep -q '0\.0\.0\.0:5432'; then
            bad "پورت ۵۴۳۲ روی همه اینترفیس‌ها باز است — باید فقط 127.0.0.1 باشد (PRJ-IEE-007)"
        else
            ok "پورت PostgreSQL روی اینترنت باز نیست"
        fi
    else
        bad "psql داخل کانتینر «$PG_SERVICE» جواب نداد"
        printf '     نام سرویس را بررسی کنید: docker compose ps\n'
        printf '     سپس: PG_SERVICE=<name> bash 03_ops/preflight.sh\n'
    fi
else
    warn "اتصال PostgreSQL آزمایش نشد (compose یا Docker در دسترس نبود)"
fi

# ── ۵) n8n ─────────────────────────────────────────────────────────────
head_ "۵) n8n"
if [[ -f "$COMPOSE_FILE" ]] && command -v docker >/dev/null 2>&1; then
    if n8nv="$(dc exec -T "$N8N_SERVICE" n8n --version 2>/dev/null | tail -1)"; then
        ok "نسخه n8n: $n8nv"
        printf '     گردش‌کارها با typeVersion های 2.6 (postgres) و 1.3 (schedule) ساخته شده‌اند.\n'
        printf '     اگر n8n قدیمی‌تر از 1.90 بود، قبل از ایمپورت به‌روزرسانی لازم است.\n'
    else
        warn "نسخه n8n خوانده نشد (سرویس بالاست؟)"
    fi
    # متغیرهای محیطی لازم
    envs="$(dc exec -T "$N8N_SERVICE" printenv 2>/dev/null |
            grep -E '^(BALE_API_URL|N8N_BLOCK_ENV_ACCESS_IN_NODE|GENERIC_TIMEZONE)=' || true)"
    if printf '%s' "$envs" | grep -q '^BALE_API_URL='; then
        # مقدار توکن هرگز چاپ نمی‌شود
        u="$(printf '%s\n' "$envs" | grep '^BALE_API_URL=' | cut -d= -f2-)"
        if printf '%s' "$u" | grep -q '^https://tapi\.bale\.ai/bot'; then
            ok "BALE_API_URL تنظیم شده است (مقدار محرمانه، چاپ نمی‌شود)"
        else
            warn "BALE_API_URL تنظیم شده اما قالب درست نیست — باید با https://tapi.bale.ai/bot شروع شود"
        fi
    else
        bad "BALE_API_URL در سرویس n8n تعریف نشده — ارسال پیام بله کار نمی‌کند"
        printf '     مأخذ: 03_ops/env.example و 03_ops/docker-compose.override.yml\n'
    fi
    if printf '%s' "$envs" | grep -q '^N8N_BLOCK_ENV_ACCESS_IN_NODE=false'; then
        ok "N8N_BLOCK_ENV_ACCESS_IN_NODE=false"
    else
        bad "N8N_BLOCK_ENV_ACCESS_IN_NODE=false نیست — گره‌ها به \$env دسترسی ندارند و ارسال شکست می‌خورد"
    fi
    if printf '%s' "$envs" | grep -q '^GENERIC_TIMEZONE=Asia/Tehran'; then
        ok "منطقه زمانی تهران تنظیم است"
    else
        warn "GENERIC_TIMEZONE=Asia/Tehran نیست — ساعت اجرای گزارش‌ها جابه‌جا می‌شود"
    fi
fi

# ── ۶) فضای دیسک ───────────────────────────────────────────────────────
head_ "۶) فضای دیسک"
avail="$(df -h --output=avail / 2>/dev/null | tail -1 | tr -d ' ')"
printf '  فضای آزاد ریشه: %s\n' "${avail:-نامشخص}"
if [[ -n "${avail:-}" ]] && [[ "${avail%G}" =~ ^[0-9]+$ ]] && (( ${avail%G} < 5 )); then
    warn "فضای دیسک کم است (زیر ۵ گیگابایت) — پشتیبان‌گیری و لاگ‌ها را پایش کنید"
else
    ok "فضای دیسک کافی است"
fi

# ── ۷) نتیجه ───────────────────────────────────────────────────────────
head_ "نتیجه"
printf '  موفق: %d · هشدار: %d · خطا: %d\n' "$C_OK" "$C_WARN" "$C_FAIL"
echo ""

if [[ "$C_FAIL" -gt 0 ]]; then
    printf '  \033[33mقبل از ادامه، خطاهای بالا را رفع کنید.\033[0m\n'
    exit 1
fi

DB_ARG="${DB_FOUND:-xennic}"
cat <<EOF
  همه پیش‌نیازها آماده است. دستورهای بعدی (به همین ترتیب):

  ۱) بازرسی کامل و ثبت گزارش:
     bash 00_audit/audit_postgres.sh

  ۲) استقرار ساختار و منطق در دیتابیس «$DB_ARG»:
     PG_DB=$DB_ARG APP_PASSWORD='<یک-رمز-قوی-بسازید>' bash 03_ops/deploy_sql.sh

  ۳) ایمپورت گردش‌کارها:
     bash 03_ops/import_workflows.sh import

  ۴) در رابط n8n: کارت «Xennic PostgreSQL» بسازید
     (میزبان: postgres · دیتابیس: $DB_ARG · کاربر: iee_app)

  ۵) فعال‌سازی:
     bash 03_ops/import_workflows.sh activate
EOF
