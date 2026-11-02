#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — استقرار ساختار و منطق در PostgreSQL
#
# اجرا روی VPS (از مسیر iee1405-deploy):
#   bash 03_ops/deploy_sql.sh                 # استقرار کامل
#   bash 03_ops/deploy_sql.sh --verify-only   # فقط بررسی، بدون تغییر
#
# ویژگی‌ها:
#   • همه فایل‌ها idempotent هستند؛ اجرای دوباره بی‌خطر است
#   • هر فایل در یک تراکنش جدا اجرا می‌شود (ON_ERROR_STOP=1)
#   • قبل از تغییر، نسخه پشتیبان گرفته می‌شود (اگر --no-backup ندهید)
#   • رمز نقش‌ها فقط از متغیر محیطی می‌آید و در فایل ذخیره نمی‌شود
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL_DIR="$HERE/01_sql"
INFRA_DIR="${INFRA_DIR:-$HOME/xennic-infra}"
PG_SERVICE="${PG_SERVICE:-postgres}"
PG_USER="${PG_USER:-postgres}"
PG_DB="${PG_DB:-xennic}"
MODE="${1:-deploy}"

# از پوشه infra اجرا می‌شود تا docker-compose.override.yml و .env هم اثر کنند
if [[ -n "${PSQL_CMD:-}" ]]; then
    read -r -a PSQL <<< "$PSQL_CMD"
    pgq() { "${PSQL[@]}" "$@"; }
    dc()  { docker compose -f "$INFRA_DIR/docker-compose.yml" "$@"; }
else
    dc()  { ( cd "$INFRA_DIR" && docker compose "$@" ); }
    pgq() { dc exec -T "$PG_SERVICE" psql -U "$PG_USER" -d "$PG_DB" -v ON_ERROR_STOP=1 -X "$@"; }
fi

run_file() {
    local f="$1"
    echo "→ $f"
    if ! pgq -f - < "$f" >/tmp/iee_deploy_out.txt 2>/tmp/iee_deploy_err.txt; then
        echo "❌ خطا در $f"
        tail -30 /tmp/iee_deploy_err.txt
        tail -10 /tmp/iee_deploy_out.txt
        exit 1
    fi
    grep -c "NOTICE" /tmp/iee_deploy_err.txt >/dev/null 2>&1 && \
        echo "  (اعلان‌های طبیعی: $(grep -c NOTICE /tmp/iee_deploy_err.txt 2>/dev/null || echo 0))"
    echo "  ✅"
}

echo "════════════════════════════════════════════════"
echo " استقرار IEE 1405 در دیتابیس «$PG_DB»"
echo " حالت: $MODE"
echo "════════════════════════════════════════════════"

# ── بررسی اتصال ──
if ! pgq -c 'SELECT 1' >/dev/null 2>&1; then
    echo "❌ اتصال برقرار نشد. بررسی کنید:"
    echo "   1) docker compose -f $INFRA_DIR/docker-compose.yml ps"
    echo "   2) نام دیتابیس: PG_DB=$PG_DB (پیش‌فرض xennic)"
    exit 1
fi

# ── بررسی وضعیت فعلی ──
EXISTING=$(pgq -t -A -c \
  "SELECT count(*) FROM pg_tables WHERE schemaname IN ('crm','iee1405');")
echo "جدول‌های موجود در schemaهای crm/iee1405: $EXISTING"

if [[ "$MODE" == "--verify-only" ]]; then
    echo ""
    echo "وضعیت:"
    pgq -c "SELECT schemaname, count(*) AS tables FROM pg_tables
                      WHERE schemaname IN ('crm','iee1405') GROUP BY 1 ORDER BY 1;"
    exit 0
fi

# ── پشتیبان قبل از تغییر ──
if [[ "$MODE" != "--no-backup" && "$EXISTING" != "0" ]]; then
    echo "→ گرفتن نسخه پشتیبان قبل از تغییر"
    bash "$HERE/03_ops/backup_now.sh" predeploy || {
        echo "❌ پشتیبان‌گیری ناموفق بود؛ برای ادامه عمداً متوقف شد."
        echo "   اگر مطمئن هستید: bash 03_ops/deploy_sql.sh --no-backup"
        exit 1
    }
fi

# ── ترتیب اجرا مهم است ──
run_file "$SQL_DIR/01_schema_core.sql"
run_file "$SQL_DIR/02_seed_reference.sql"
run_file "$SQL_DIR/03_views.sql"
run_file "$SQL_DIR/04_bot_logic.sql"
run_file "$SQL_DIR/05_ops_helpers.sql"

# ── نقش‌ها: رمز فقط اگر APP_PASSWORD داده شده باشد ──
if [[ -n "${APP_PASSWORD:-}" ]]; then
    echo "→ ساخت نقش‌ها با رمز از متغیر محیطی"
    pgq -v app_password="$APP_PASSWORD" -f - < "$SQL_DIR/06_roles.sql"
    echo "  ✅"
else
    echo "→ نقش‌ها بدون رمز (APP_PASSWORD تنظیم نشده)"
    pgq -c "SELECT 'برای ساخت نقش‌ها: APP_PASSWORD=... bash 03_ops/deploy_sql.sh'" >/dev/null
    pgq -f - < "$SQL_DIR/06_roles.sql" || true
fi

# ── تأیید نهایی ──
echo ""
echo "── تأیید ──"
pgq -c "
SELECT 'table' AS kind, count(*) AS n FROM pg_tables WHERE schemaname IN ('crm','iee1405')
UNION ALL SELECT 'view', count(*) FROM pg_views WHERE schemaname IN ('crm','iee1405')
UNION ALL SELECT 'function', count(*) FROM information_schema.routines
           WHERE routine_schema IN ('crm','iee1405')
UNION ALL SELECT 'orgs', count(*) FROM crm.organizations
UNION ALL SELECT 'categories', count(*) FROM crm.product_categories
UNION ALL SELECT 'exhibition', count(*) FROM iee1405.exhibitions;"
pgq -c "SELECT iee1405.health_text();"

echo ""
echo "✅ استقرار تمام شد"
echo "   گام بعدی: bash 03_ops/import_workflows.sh"
