#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — پشتیبان‌گیری منطقی (pg_dump)
#
# اجرا روی VPS:
#   bash 03_ops/backup_now.sh            # پشتیبان کامل دیتابیس
#   bash 03_ops/backup_now.sh predeploy  # با برچسب
#
# خروجی: ~/xennic-backups/iee-<برچسب>-<تاریخ>.dump (+ .sql.gz برای بازبینی)
# نگهداشت: ۱۴ نسخه اخیر نگه داشته می‌شود.
#
# بازگردانی (روی یک دیتابیس آزمایشی، هرگز مستقیم روی تولید):
#   docker compose exec -T postgres psql -U postgres -c 'CREATE DATABASE restore_test;'
#   docker compose exec -T postgres pg_restore -U postgres -d restore_test --no-owner < file.dump
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="${INFRA_DIR:-$HOME/xennic-infra}"
PG_SERVICE="${PG_SERVICE:-postgres}"
PG_USER="${PG_USER:-postgres}"
PG_DB="${PG_DB:-xennic}"
LABEL="${1:-manual}"
OUT_DIR="${BACKUP_DIR:-$HOME/xennic-backups}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
FILE="$OUT_DIR/iee-${LABEL}-${STAMP}.dump"

mkdir -p "$OUT_DIR"

echo "→ پشتیبان‌گیری از «$PG_DB» → $FILE"
if docker compose -f "$INFRA_DIR/docker-compose.yml" exec -T "$PG_SERVICE" \
        pg_dump -U "$PG_USER" -d "$PG_DB" -Fc --no-owner > "$FILE"; then
    SIZE=$(du -h "$FILE" | cut -f1)
    echo "  ✅ $SIZE"
else
    echo "  ❌ پشتیبان‌گیری ناموفق"
    rm -f "$FILE"
    exit 1
fi

# نسخه متنی برای بازبینی/جست‌وجو (فشرده)
docker compose -f "$INFRA_DIR/docker-compose.yml" exec -T "$PG_SERVICE" \
    pg_dump -U "$PG_USER" -d "$PG_DB" --no-owner 2>/dev/null | gzip -6 > "${FILE%.dump}.sql.gz" || true

# نگهداشت ۱۴ نسخه اخیر
ls -1t "$OUT_DIR"/iee-*.dump 2>/dev/null | tail -n +15 | xargs -r rm -f
ls -1t "$OUT_DIR"/iee-*.sql.gz 2>/dev/null | tail -n +15 | xargs -r rm -f

# بررسی سلامت فایل پشتیبان (بدون بازگردانی)
if docker compose -f "$INFRA_DIR/docker-compose.yml" exec -T "$PG_SERVICE" \
        pg_restore --list < "$FILE" >/dev/null 2>&1; then
    echo "  ✅ فایل پشتیبان سالم و قابل بازگردانی است"
else
    echo "  ⚠️ فهرست پشتیبان خوانده نشد — قبل از اتکا، بازگردانی آزمایشی انجام دهید"
fi

echo "نسخه‌های موجود:"
ls -1t "$OUT_DIR"/iee-*.dump 2>/dev/null | head -5
