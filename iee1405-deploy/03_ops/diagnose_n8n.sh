#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — تشخیص: چرا گردش‌کار اجرا نمی‌شود؟
#
#   bash 03_ops/diagnose_n8n.sh          # گزارش کامل (فقط خواندن)
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

for arg in "$@"; do
    case "$arg" in
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
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
        c_head "۳.۱) خطای واقعی آخرین اجرای ناموفق (رمزگشایی‌شده)"
        LAST_ERR_ID="$(SYSQ "SELECT id FROM execution_entity
                              WHERE status IN ('error','crashed')
                              ORDER BY id DESC LIMIT 1")"
        if [[ -n "${LAST_ERR_ID:-}" ]]; then
            RAW_DATA="$(pgq "$N8N_DB" -c "SELECT data FROM execution_data
                                           WHERE \"executionId\" = $LAST_ERR_ID
                                           ORDER BY id DESC LIMIT 1" 2>/dev/null)"
            if [[ -n "${RAW_DATA:-}" ]]; then
                printf '%s' "$RAW_DATA" | python3 "$HERE/decode_execution.py" 2>&1 | sed 's/^/     /'
            else
                c_warn "متن اجرای $LAST_ERR_ID در execution_data نیست (پاک‌شده یا هرس‌شده)"
            fi
        else
            c_ok "اجرای ناموفقی ثبت نشده"
        fi
    fi

    STUCK="$(SYSQ "SELECT count(*) FROM execution_entity
                    WHERE status = 'running'
                      AND \"startedAt\" < now() - interval '2 minutes'")"
    if [[ -n "${STUCK:-}" && "${STUCK:-0}" -gt 0 ]]; then
        c_bad "$STUCK اجرای «در حال اجرا» بیش از ۲ دقیقه — درخواست HTTP معلق مانده"
        c_hint "گره HTTP باید timeout داشته باشد (در این نسخه: ۲۰ ثانیه) و n8n ری‌استارت شود"
        c_hint "bash 03_ops/import_workflows.sh import && bash 03_ops/activate_all.sh"
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
c_head "۳.۲) اجرای گیرکرده تا کدام گره رسیده؟"
# با saveExecutionProgress=true، n8n داده را مرحله‌به‌مرحله ذخیره می‌کند.
# پس می‌توان دید یک اجرای تمام‌نشده کجا ایستاده است.
if HAS_TABLE execution_data; then
    RUN_ID="$(SYSQ "SELECT id FROM execution_entity WHERE status = 'running' ORDER BY id DESC LIMIT 1")"
    if [[ -n "${RUN_ID:-}" ]]; then
        RUN_RAW="$(pgq "$N8N_DB" -c "SELECT data FROM execution_data
                                      WHERE \"executionId\" = $RUN_ID
                                      ORDER BY id DESC LIMIT 1" 2>/dev/null)"
        if [[ -n "${RUN_RAW:-}" ]]; then
            echo "     اجرای $RUN_ID:"
            printf '%s' "$RUN_RAW" | python3 "$HERE/decode_execution.py" 2>&1 | sed 's/^/       /'
            echo "     ↑ گره‌ای که وضعیتش ثبت نشده، همان‌جایی است که اجرا منتظر مانده"
        else
            c_warn "برای اجرای $RUN_ID هنوز داده‌ای ذخیره نشده (saveExecutionProgress)"
            c_hint "اگر این پیام تکرار شد، نسخه تازه گردش‌کار ایمپورت نشده است:"
            c_hint "bash 03_ops/import_workflows.sh import && bash 03_ops/activate_all.sh"
        fi
    else
        c_ok "اجرای در حال اجرایی وجود ندارد"
    fi
fi

c_head "۳.۵) دسترسی n8n به متغیرهای محیطی (علت رایج شکست گره HTTP)"
BLOCK_FLAG="$($DK exec -i "$N8N_CT" printenv N8N_BLOCK_ENV_ACCESS_IN_NODE 2>/dev/null | tr -d '\r\n')"
if [[ "$BLOCK_FLAG" == "false" ]]; then
    c_ok "N8N_BLOCK_ENV_ACCESS_IN_NODE=false (دسترسی \$env آزاد است)"
else
    c_bad "N8N_BLOCK_ENV_ACCESS_IN_NODE=${BLOCK_FLAG:-<تنظیم نشده>} — گردش‌کار به \$env دسترسی ندارد"
    c_hint "گردش‌کار آدرس بله را از \$env.BALE_API_URL می‌خواند؛ بدون آن گره HTTP شکست می‌خورد"
    c_hint "bash 03_ops/setup_env.sh && bash 03_ops/activate_all.sh"
fi
if $DK exec -i "$N8N_CT" sh -c 'test -n "$BALE_API_URL"' 2>/dev/null; then
    c_ok "BALE_API_URL داخل کانتینر n8n تعریف شده است (مقدار چاپ نمی‌شود)"
else
    c_bad "BALE_API_URL داخل کانتینر n8n تعریف نشده است"
    c_hint "bash 03_ops/setup_env.sh   # از BALE_TOKEN_BOT در .env می‌سازد"
fi
if $DK exec -i "$PG_CT" psql -U "$PG_USER" -d "$PG_DB" -X -t -A -c 'SELECT 1' >/dev/null 2>&1; then
    c_ok "دیتابیس $PG_DB از طریق psql داخل کانتینر در دسترس است"
fi

c_head "۳.۶) دسترسی کانتینر n8n به tapi.bale.ai"
CONTAINER_NET="$($DK exec -i "$N8N_CT" node -e '
const t = AbortSignal.timeout(8000);
fetch("https://tapi.bale.ai", {signal: t})
  .then(r => { console.log("HTTP " + r.status); process.exit(0); })
  .catch(e => { console.log("ERR " + (e.name || "") + " " + (e.message || "")); process.exit(1); });
' 2>&1 | tail -1)"
case "$CONTAINER_NET" in
    HTTP*)
        c_ok "از داخل کانتینر n8n، tapi.bale.ai پاسخ داد ($CONTAINER_NET)" ;;
    *timeout*|*Timeout*|*abort*|*Abort*)
        c_bad "اتصال از داخل کانتینر به tapi.bale.ai زمان‌بندی شد (timeout)"
        c_hint "یعنی درخواست getUpdates هرگز پاسخ نمی‌گیرد؛ خطای شبکه/VPN/فیلتر را بررسی کنید"
        c_hint "تست میزبان: curl -s -m 10 -o /dev/null -w '%{http_code}\\n' https://tapi.bale.ai" ;;
    *)
        c_warn "پاسخ غیرمنتظره از داخل کانتینر: $CONTAINER_NET" ;;
esac

c_head "۳.۷) آزمون زنده getUpdates از داخل کانتینر n8n"
# توجه: ایمیج n8n «curl» ندارد (آلپاین) — پس با node آزموده می‌شود که خودش هم
# همان runtime واقعی گره‌هاست. توکن چاپ نمی‌شود؛ فقط کد، زمان و بدنه ماسک‌شده.
# offset واقعی از دیتابیس برنامه: همان عددی که گره «📥 دریافت پیام‌ها» می‌فرستد
PROBE_OFFSET="$(pgq "$PG_DB" -c "SELECT iee1405.poll_offset() + 1" 2>/dev/null | tr -d '[:space:]')"
PROBE_OFFSET="${PROBE_OFFSET:-1}"
PROBE="$($DK exec -i -e "PROBE_OFFSET=$PROBE_OFFSET" "$N8N_CT" node -e '
const url = process.env.BALE_API_URL;
if (!url) { console.log("NORURL"); process.exit(0); }
const mask = (s) => (s || "").replace(/bot[0-9]+:[A-Za-z0-9_-]+/g, "bot***").slice(0, 220);
const run = async (label, target) => {
  const t0 = Date.now();
  try {
    const r = await fetch(target, { signal: AbortSignal.timeout(15000) });
    const body = await r.text();
    console.log(`${label} CODE=${r.status} MS=${Date.now() - t0} BODY=${mask(body)}`);
  } catch (e) {
    console.log(`${label} CODE=000 MS=${Date.now() - t0} ERR=${(e.name || "")}: ${(e.message || "")}`);
  }
};
(async () => {
  const off = process.env.PROBE_OFFSET || "1";
  // BAREPROBE: خط پایه (شبکه/توکن) — PROBE: دقیقاً همان URLی که گره تولید می‌سازد
  await run("BAREPROBE", url + "/getUpdates");
  await run("PROBE", url + "/getUpdates?offset=" + encodeURIComponent(off) + "&limit=50&timeout=0");
})();
' 2>&1 | tail -2)"

CODE="$(printf '%s' "$PROBE" | sed -n 's/^PROBE CODE=\([^ ]*\).*/\1/p')"
BARECODE="$(printf '%s' "$PROBE" | sed -n 's/^BAREPROBE CODE=\([^ ]*\).*/\1/p')"
MS="$(printf '%s' "$PROBE" | sed -n 's/^PROBE .* MS=\([0-9]*\).*/\1/p')"
BODY="$(printf '%s' "$PROBE" | sed -n 's/^PROBE .* BODY=//p' | head -c 220)"
ERRTXT="$(printf '%s' "$PROBE" | sed -n 's/^PROBE .* ERR=//p' | head -c 200)"

if printf '%s' "$PROBE" | grep -q NORURL; then
    c_bad "متغیر BALE_API_URL داخل کانتینر n8n نیست"
    c_hint "bash 03_ops/setup_env.sh"
else
    echo "     آدرس آزمون: /getUpdates?offset=$PROBE_OFFSET&limit=50&timeout=0  (همان شکل تولید)"
    echo "     خط پایه (بدون پارامتر): ${BARECODE:-?} · پاسخ شکل تولید: ${CODE:-?} · زمان: ${MS:-?} میلی‌ثانیه"
    [[ -n "$BODY" ]] && echo "     بدنه: $BODY"
    [[ -n "$ERRTXT" ]] && echo "     خطا: $ERRTXT"

    case "$CODE" in
        400)
            c_bad "بله درخواست را رد کرد: 400 (malformed request)"
            if [[ "$BARECODE" == "200" ]]; then
                c_hint "خط پایه ۲۰۰ است: شبکه و توکن سالم‌اند، پس **پارامترها** مقصرند"
                c_hint "رایج‌ترین علت: offset خالی یا NaN — گره HTTP فیلدی را می‌خواند که گره بالادستی نمی‌دهد"
                c_hint "گردش‌کار تازه را ایمپورت کنید: bash 03_ops/import_workflows.sh import && bash 03_ops/activate_all.sh"
                c_hint "اعتبارسنجی هم این را می‌گیرد: python3 02_n8n/validate_workflows.py"
            else
                c_hint "خط پایه هم ۲۰۰ نیست — اول توکن و BALE_API_URL را ببینید (بخش ۳.۵)"
            fi
            ;;
        200)
            if printf '%s' "$BODY" | grep -q '"ok":false'; then
                c_bad "بله پاسخ ۲۰۰ داد اما ok=false — این خطا باید در bot_errors دیده شود"
                c_hint "bash 03_ops/smoke_test.sh   # بخش ۵"
            else
                c_ok "getUpdates سالم است: ۲۰۰ در ${MS} میلی‌ثانیه"
            fi
            if [[ "${MS:-0}" -gt 5000 ]] 2>/dev/null; then
                c_warn "پاسخ کند است (بیش از ۵ ثانیه) — با بازه ۲۰ ثانیه‌ای اجراها روی هم می‌افتند"
            fi
            ;;
        000)
            c_bad "درخواست کامل نشد: $ERRTXT"
            c_hint "اگر AbortError/timeout است، بله از این سرور پاسخ نمی‌دهد (شبکه/فیلتر)"
            c_hint "اگر ENOTFOUND است، DNS کانتینر مشکل دارد"
            ;;
        401|403)
            c_bad "توکن رد شد ($CODE)"
            ;;
        404)
            c_bad "مسیر اشتباه (404) — BALE_API_URL باید به /bot<TOKEN> ختم شود"
            ;;
        *)
            c_warn "پاسخ غیرمنتظره: $CODE"
            ;;
    esac
fi

c_head "۳.۸) دسترسی نقش ربات (iee_app) — منبع خطاهای permission denied"
# n8n با iee_app کار می‌کند، نه با postgres. کمبود دسترسی فقط در لحظه اجرا
# دیده می‌شود؛ پس این‌جا مستقیم آزموده و گزارش می‌شود.
GAPS="$(pgq "$PG_DB" -c "SELECT count(*) FROM iee1405.privilege_gaps()" 2>/dev/null | tr -d '[:space:]')"
if [[ "$GAPS" == "0" ]]; then
    c_ok "کمبود دسترسی ندارد"
elif [[ -z "$GAPS" ]]; then
    c_warn "تابع بازبینی ساخته نشده — 06_roles.sql اجرا نشده است"
    c_hint "bash 03_ops/fix_grants.sh"
else
    c_bad "کمبود دسترسی: $GAPS مورد"
    pgq_pretty "$PG_DB" -c "SELECT kind, object_name, needed FROM iee1405.privilege_gaps()" |
        sed 's/^/     /'
    c_hint "bash 03_ops/fix_grants.sh"
fi

WRITE_TEST="$(pgq "$PG_DB" -c "
BEGIN;
SET ROLE iee_app;
INSERT INTO iee1405.bot_errors (stage, message) VALUES ('diag', 'x');
SELECT 'OK-WRITE';
ROLLBACK;" 2>&1)"
if printf '%s' "$WRITE_TEST" | grep -q 'OK-WRITE'; then
    c_ok "نوشتن در bot_errors با نقش iee_app مجاز است"
else
    c_bad "نوشتن با نقش iee_app شکست می‌خورد:"
    printf '%s\n' "$WRITE_TEST" | grep -E "ERROR|denied" | head -2 | sed 's/^/     /'
    c_hint "bash 03_ops/fix_grants.sh"
fi

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
c_head "۵) گام بعدی"
if [[ -z "${WF01_ID:-}" ]]; then
    c_bad "گردش‌کار IEE1405-01 پیدا نشد — ابتدا ایمپورت کنید"
    c_hint "bash 03_ops/import_workflows.sh import && bash 03_ops/activate_all.sh"
elif [[ "${STUCK:-0}" -gt 0 ]]; then
    c_hint "اجراها در «running» گیر کرده‌اند: درخواست HTTP پاسخ نگرفته و timeout ندارد"
    c_hint "پس از ایمپورت/انتشار نسخه اصلاح‌شده و ری‌استارت، این وضعیت باید برطرف شود:"
    c_hint "bash 03_ops/import_workflows.sh import && bash 03_ops/activate_all.sh"
elif [[ "${ERRORS:-0}" -gt 0 ]]; then
    c_hint "خطای گره در بخش ۳.۱ دیده می‌شود؛ اگر متن خام ناخوانا بود،"
    c_hint "لاگ زنده کانتینر را ببینید: docker logs --since 5m \"$N8N_CT\" 2>&1 | grep -i -m5 error"
else
    c_hint "همه‌چیز مرتب است: در بله به ربات /start بفرستید و smoke_test.sh را اجرا کنید"
fi

echo
echo "════ پایان گزارش ════"
