#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — ایمپورت گردش‌کارهای n8n و فعال‌سازی
#
# اجرا روی VPS:
#   bash 03_ops/import_workflows.sh import    # ایمپورت/به‌روزرسانی
#   bash 03_ops/import_workflows.sh activate  # فعال‌سازی گردش‌کارهای IEE1405
#   bash 03_ops/import_workflows.sh list      # فهرست گردش‌کارها
#   bash 03_ops/import_workflows.sh export    # پشتیبان از n8n
#
# پیش‌نیازها (یک بار):
#   ۱) در سرویس n8n:  BALE_API_URL=https://tapi.bale.ai/bot<TOKEN>
#                     N8N_BLOCK_ENV_ACCESS_IN_NODE=false
#                     GENERIC_TIMEZONE=Asia/Tehran
#   ۲) در n8n → Credentials: کارت PostgreSQL با نام «Xennic PostgreSQL»
#      (میزبان: postgres · دیتابیس: xennic · کاربر: iee_app)
#   ۳) پس از ایمپورت، در هر گردش‌کار گره‌های PostgreSQL را باز کنید و همان
#      کارت اعتبارنامه را انتخاب کنید (شناسه در فایل JSON جای‌نگهدار است).
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WF_DIR="$HERE/02_n8n"
INFRA_DIR="${INFRA_DIR:-$HOME/xennic-infra}"
N8N_SERVICE="${N8N_SERVICE:-n8n}"
ACTION="${1:-import}"

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib_common.sh"

# از پوشه infra اجرا می‌شود تا override و .env هم خوانده شوند
dc()  { ( cd "$INFRA_DIR" && docker compose "$@" ); }
n8n() {
    dk_detect && ct_detect || return 1
    $DK exec -i "${N8N_CT:-$N8N_SERVICE}" n8n "$@"
}

require_n8n() {
    if ! n8n --version >/dev/null 2>&1; then
        echo "❌ سرویس n8n پاسخ نمی‌دهد."
        echo "   docker compose -f $INFRA_DIR/docker-compose.yml ps"
        exit 1
    fi
}

case "$ACTION" in
import)
    require_n8n
    echo "════ ایمپورت گردش‌کارها (n8n $(n8n --version 2>/dev/null | tail -1)) ════"
    for f in "$WF_DIR"/wf-*.json; do
        base="$(basename "$f")"
        printf '→ %s ' "$base"
        $DK exec -i "${N8N_CT:-$N8N_SERVICE}" sh -c 'cat > /tmp/wf.json' < "$f"
        if n8n import:workflow --input=/tmp/wf.json >/tmp/n8n_import.log 2>&1; then
            echo "✅"
        else
            echo "❌"
            tail -5 /tmp/n8n_import.log
            exit 1
        fi
    done
    echo ""
    echo "در n8n → Workflows: چهار گردش‌کار با پیشوند «IEE1405» را ببینید."
    echo "سپس: bash 03_ops/import_workflows.sh activate"
    ;;

activate)
    require_n8n
    echo "════ فعال‌سازی ════"
    echo "در n8n نسخه ۲، فعال‌سازی با publish:workflow انجام می‌شود و"
    echo "پس از آن n8n باید ری‌استارت شود. این کار در activate_all.sh انجام می‌شود."
    echo ""
    bash "$(dirname "$0")/activate_all.sh"
    ;;

list)
    require_n8n
    echo "════ گردش‌کارهای n8n ════"
    n8n list:workflow
    ;;

export)
    require_n8n
    STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
    OUT="${BACKUP_DIR:-$HOME/xennic-backups}"
    mkdir -p "$OUT"
    n8n export:workflow --all --output=/tmp/n8n-export.json >/dev/null 2>&1 || true
    $DK exec -i "${N8N_CT:-$N8N_SERVICE}" cat /tmp/n8n-export.json > "$OUT/n8n-workflows-$STAMP.json"
    echo "→ $OUT/n8n-workflows-$STAMP.json"
    ls -lh "$OUT/n8n-workflows-$STAMP.json"
    ;;

*)
    echo "استفاده: $0 {import|activate|list|export}"
    exit 1
    ;;
esac
