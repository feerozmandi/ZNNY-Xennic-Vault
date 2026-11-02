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
#   bash 03_ops/restore_test.sh <file.dump>     # بازگردانی آزمایشی در دیتابیس موقت
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib_common.sh"
LABEL="${1:-manual}"
OUT_DIR="${BACKUP_DIR:-$HOME/xennic-backups}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
FILE="$OUT_DIR/iee-${LABEL}-${STAMP}.dump"

mkdir -p "$OUT_DIR"

if ! dk_detect || ! ct_detect; then
    echo "❌ Docker یا کانتینر PostgreSQL پیدا نشد"
    exit 1
fi
pg_user_detect || true

echo "→ پشتیبان‌گیری از «$PG_DB» → $FILE"
if $DK exec -i "$PG_CT" pg_dump -U "$PG_USER" -d "$PG_DB" -Fc --no-owner > "$FILE"; then
    SIZE=$(du -h "$FILE" | cut -f1)
    echo "  ✅ $SIZE"
else
    echo "  ❌ پشتیبان‌گیری ناموفق"
    rm -f "$FILE"
    exit 1
fi

# نسخه متنی برای بازبینی/جست‌وجو (فشرده)
$DK exec -i "$PG_CT" pg_dump -U "$PG_USER" -d "$PG_DB" --no-owner 2>/dev/null \
    | gzip -6 > "${FILE%.dump}.sql.gz" || true

# نگهداشت ۱۴ نسخه اخیر
ls -1t "$OUT_DIR"/iee-*.dump 2>/dev/null | tail -n +15 | xargs -r rm -f
ls -1t "$OUT_DIR"/iee-*.sql.gz 2>/dev/null | tail -n +15 | xargs -r rm -f

# بررسی سلامت فایل پشتیبان (بدون بازگردانی)
if $DK exec -i "$PG_CT" pg_restore --list < "$FILE" >/dev/null 2>&1; then
    echo "  ✅ فایل پشتیبان سالم و قابل بازگردانی است"
else
    echo "  ⚠️ فهرست پشتیبان خوانده نشد — قبل از اتکا، بازگردانی آزمایشی انجام دهید"
fi

echo "نسخه‌های موجود:"
ls -1t "$OUT_DIR"/iee-*.dump 2>/dev/null | head -5
