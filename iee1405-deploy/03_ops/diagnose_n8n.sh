#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — تشخیص: چرا گردش‌کار اجرا نمی‌شود؟
#
#   bash 03_ops/diagnose_n8n.sh          # گزارش کامل (فقط خواندن)
#   bash 03_ops/diagnose_n8n.sh --run    # + اجرای دستی wf-01 برای دیدن خطای واقعی
#
# این اسکریپت به دیتابیس خود n8n نگاه می‌کند (نه فقط به خروجی CLI):
#   • workflow_entity    → active و activeVersionId
#   • credentials_entity → آیا کارت «Xennic PostgreSQL» واقعاً ساخته شده؟
#   • execution_entity   → آیا گردش‌کار اجرا می‌شود و با چه خطایی؟
# هیچ چیزی تغییر نمی‌دهد؛ فقط می‌خواند.
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_common.sh
source "$HERE/lib_common.sh"

RUN_NOW=false
for arg in "$@"; do
    case "$arg" in
        --run) RUN_NOW=true ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "گزینه ناشناخته: $arg" >&2; exit 2 ;;
    esac
done

dk_detect || { c_bad "docker در دسترس نیست"; exit 1; }
ct_detect >/dev/null 2>&1 || { c_bad "کانتینر PostgreSQL پیدا نشد"; exit 1; }
pg_user_detect >/dev/null 2>&1

if [[ -z "${N8N_CT:-}" ]]; then
    c_bad "کانتینر n8n پیدا نشد"
    exit 1
fi

# ── نام دیتابیس خود n8n (نه دیتابیس برنامه) ────────────────────────────
N8N_DB="$($DK exec -i "$N8N_CT" printenv DB_POSTGRESDB_DATABASE 2>/dev/null | tr -d '\r\n')"
if [[ -z "$N8N_DB" ]]; then
    N8N_DB="$($DK exec -i "$PG_CT" printenv POSTGRES_DB 2>/dev/null | tr -d '\r\n')"
fi
N8N_DB="${N8N_DB:-n8n}"

SYSQ() { pgq "$N8N_DB" -c "$1" 2>/dev/null; }
HAS_TABLE() { [[ "$(SYSQ "SELECT to_regclass('$1') IS NOT NULL")" == "t" ]]; }

if ! HAS_TABLE workflow_entity; then
    c_bad "در دیتابیس «$N8N_DB» جدول workflow_entity نیست"
    c_hint "نام دیتابیس n8n را مشخص کنید: N8N_DB=<name> bash 03_ops/diagnose_n8n.sh"
    exit 1
fi

echo "════ تشخیص n8n ════  (دیتابیس n8n: $N8N_DB · دیتابیس برنامه: $PG_DB)"

# ── ۱) گردش‌کارها ──────────────────────────────────────────────────────
c_head "۱) گردش‌کارهای IEE1405 در دیتابیس n8n"
pgq_pretty "$N8N_DB" -c "
    SELECT left(id, 12) AS id,
           left(name, 34) AS name,
           active,
           (\"activeVersionId\" IS NOT NULL) AS has_version,
           to_char(\"updatedAt\", 'MM-DD HH24:MI') AS updated
      FROM workflow_entity
     WHERE name LIKE 'IEE1405%'
     ORDER BY name" || c_warn "خواندن workflow_entity ناموفق"

WORKFLOW_COUNT="$(SYSQ "SELECT count(*) FROM workflow_entity WHERE name LIKE 'IEE1405%'")"
WORKFLOW_ACTIVE="$(SYSQ "SELECT count(*) FROM workflow_entity WHERE name LIKE 'IEE1405%' AND active AND \"activeVersionId\" IS NOT NULL")"
WF01_ID="$(SYSQ "SELECT id FROM workflow_entity WHERE name LIKE 'IEE1405-01%' ORDER BY 1 LIMIT 1")"

if [[ "${WORKFLOW_ACTIVE:-0}" -ge 1 ]]; then
    c_ok "$WORKFLOW_ACTIVE گردش‌کار واقعاً فعال است (active + نسخه منتشرشده)"
else
    c_bad "هیچ گردش‌کاری هم‌زمان active و دارای نسخه منتشرشده نیست"
    c_hint "bash 03_ops/activate_all.sh"
fi

# ── ۲) اعتبارنامه ──────────────────────────────────────────────────────
c_head "۲) کارت اعتبارنامه PostgreSQL"
if HAS_TABLE credentials_entity; then
    pgq_pretty "$N8N_DB" -c "
        SELECT left(id, 20) AS id, left(name, 30) AS name, type
          FROM credentials_entity
         WHERE type = 'postgres' OR name ILIKE '%xennic%'
         ORDER BY name" || true
    if [[ -n "$(SYSQ "SELECT id FROM credentials_entity WHERE id = 'XENNIC-PG-CREDENTIAL'")" ]]; then
        c_ok "اعتبارنامه XENNIC-PG-CREDENTIAL موجود است"
    else
        c_bad "اعتبارنامه XENNIC-PG-CREDENTIAL در n8n نیست"
        c_hint "گردش‌کارها به همین شناسه ارجاع می‌دهند؛ بدون آن، گره اول PostgreSQL خطا می‌دهد"
        c_hint "bash 03_ops/activate_all.sh   (کارت را می‌سازد)"
    fi
else
    c_warn "جدول credentials_entity نیست"
fi

# ── ۳) اجراها ──────────────────────────────────────────────────────────
c_head "۳) اجراهای اخیر (منبع حقیقت: آیا گردش‌کار اجرا می‌شود؟)"
if HAS_TABLE execution_entity; then
    pgq_pretty "$N8N_DB" -c "
        SELECT e.id,
               left(w.name, 26) AS workflow,
               coalesce(e.status, CASE WHEN e.finished THEN 'success' ELSE 'running' END) AS status,
               e.mode,
               to_char(e.\"startedAt\", 'MM-DD HH24:MI:SS') AS started
          FROM execution_entity e
          LEFT JOIN workflow_entity w ON w.id = e.\"workflowId\"
         WHERE e.\"startedAt\" > now() - interval '3 hours'
         ORDER BY e.id DESC
         LIMIT 8" || true

    if HAS_TABLE execution_data; then
        c_head "۳.۱) خطای آخرین اجراها"
        pgq_pretty "$N8N_DB" -c "
            SELECT e.id, coalesce(e.status, '—') AS status,
                   substring(d.data::text from '\"lastNodeExecuted\":\"([^\"]{0,40})\"') AS last_node,
                   substring(d.data::text from '\"message\":\"([^\"]{0,120})')       AS error
              FROM execution_entity e
              JOIN execution_data d ON d.\"executionId\" = e.id
             WHERE e.\"startedAt\" > now() - interval '3 hours'
               AND d.data::text LIKE '%\"error\"%'
             ORDER BY e.id DESC
             LIMIT 3" 2>/dev/null || c_warn "خواندن متن خطا ممکن نشد (ساختار execution_data متفاوت است)"
    fi

    RECENT="$(SYSQ "SELECT count(*) FROM execution_entity WHERE \"startedAt\" > now() - interval '10 minutes'")"
    ERRORS="$(SYSQ "SELECT count(*) FROM execution_entity WHERE \"startedAt\" > now() - interval '1 hour' AND (status = 'error' OR status = 'crashed')")"
    if [[ "${RECENT:-0}" -eq 0 ]]; then
        c_bad "در ۱۰ دقیقه گذشته هیچ اجرایی ثبت نشده — یعنی زمان‌بند اصلاً اجرا نمی‌شود"
        c_hint "نشانه «فعال در دیتابیس ولی بی‌حرکت»: n8n بعد از انتشار ری‌استارت نشده یا فعال‌سازی خطا داده"
        c_hint "bash 03_ops/activate_all.sh   سپس این اسکریپت را دوباره اجرا کنید"
    else
        c_ok "$RECENT اجرا در ۱۰ دقیقه گذشته"
        [[ "${ERRORS:-0}" -gt 0 ]] && c_bad "$ERRORS اجرای ناموفق در ۱ ساعت گذشته — خطا را در بخش ۳.۱ ببینید"
    fi
else
    c_warn "جدول execution_entity نیست"
fi

# ── ۴) داده ربات ───────────────────────────────────────────────────────
c_head "۴) وضعیت دریافت پیام در دیتابیس برنامه"
pgq_pretty "$PG_DB" -c "
    SELECT key, left(coalesce(value, '—'), 30) AS value
      FROM iee1405.bot_state
     WHERE key IN ('last_poll_at', 'bale_offset', 'last_error', 'poll_enabled')
     ORDER BY key" || true
pgq_pretty "$PG_DB" -c "
    SELECT (SELECT count(*) FROM iee1405.bot_updates) AS updates,
           (SELECT count(*) FROM iee1405.bot_errors)  AS errors" || true

# ── ۵) اجرای دستی برای دیدن خطای واقعی ─────────────────────────────────
if [[ -z "${WF01_ID:-}" ]]; then
    c_head "۵) اجرای دستی"
    c_bad "گردش‌کار IEE1405-01 پیدا نشد — ابتدا ایمپورت کنید"
    c_hint "bash 03_ops/import_workflows.sh import && bash 03_ops/activate_all.sh"
elif [[ "$RUN_NOW" == true ]]; then
    c_head "۵) اجرای دستی IEE1405-01 (خطای واقعی همین‌جا دیده می‌شود)"
    OUT="$($DK exec -i "$N8N_CT" n8n execute --id="$WF01_ID" 2>&1 | tail -40)"
    printf '%s\n' "$OUT" | sed 's/^/     /'
    if printf '%s' "$OUT" | grep -qi "Execution was successful"; then
        c_ok "اجرای دستی موفق بود — پس مشکل فقط در زمان‌بند/فعال‌سازی است"
    else
        c_bad "اجرای دستی ناموفق — علت در چند خط بالا (نام گره و پیام خطا)"
    fi
else
    c_head "۵) گام بعدی"
    c_hint "برای دیدن خطای واقعی: bash 03_ops/diagnose_n8n.sh --run"
fi

echo
echo "════ پایان گزارش ════"
