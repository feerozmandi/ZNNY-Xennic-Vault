#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — «چرا جواب ربات دیر می‌رسد؟»
#
# گزارش مالک: «جواب کلیدها خیلی با تاخیر می‌باشد». تاخیر در سه جای مختلف
# می‌تواند باشد و درمان هر سه فرق می‌کند؛ این اسکریپت جای دقیق را نشان می‌دهد:
#
#   ۱) بله → پایگاه : فاصلهٔ زمان پیام در بله تا ثبت در bot_updates
#      ⇒ مشکل در «دریافت» (زمان‌بند گردش‌کار یا صف اجراهای n8n)
#   ۲) پایگاه → ارسال : فاصلهٔ ثبت تا delivered_at
#      ⇒ مشکل در «ارسال» (کندی sendMessage یا شلوغی صف)
#   ۳) اجراهای گیرکرده : ردیف‌های running در n8n که هرگز تمام نشدند
#      ⇒ صف را شلوغ می‌کنند و اجرای تازه را عقب می‌اندازند
#
# فقط می‌خواند؛ هیچ چیزی نمی‌نویسد.
#   bash 03_ops/latency_report.sh
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/03_ops/lib_common.sh"

PG_DB="${PG_DB:-xennic}"

if [[ -n "${PG_DIRECT_PSQL:-}" ]]; then
    dk_detect() { return 0; }
    ct_detect() { return 0; }
    pg_user_detect() { PG_USER="${PG_USER:-postgres}"; }
    pgq()        { local db="$1"; shift; $PG_DIRECT_PSQL -X -t -A -d "$db" "$@"; }
    pgq_pretty() { local db="$1"; shift; $PG_DIRECT_PSQL -X -P pager=off -d "$db" "$@"; }
fi

echo "════════════════════════════════════════════════"
echo " گزارش تاخیر ربات بله"
echo " پایگاه: $PG_DB"
echo "════════════════════════════════════════════════"

# ردیف‌های با «تاریخ بله» ساختگی (دادهٔ آزمایشی) میانه را بی‌معنا می‌کنند؛
# در همهٔ کوئری‌ها فقط ردیف‌هایی می‌مانند که تاریخ بله‌شان نزدیک ثبت ماست.
FILTER_TS="to_timestamp(NULLIF(u.raw #>> '{message,date}', '')::bigint)
             BETWEEN u.received_at - interval '10 minutes'
                 AND u.received_at + interval '5 minutes'"

# ── ۰) پیش‌نیاز: آیا چیزی برای سنجیدن هست؟ ───────────────────────────
n="$(pgq "$PG_DB" -c "SELECT count(*) FROM iee1405.bot_updates
                       WHERE received_at > now() - interval '24 hours'" 2>/dev/null || echo "?")"
if [[ "$n" == "?" || -z "$n" ]]; then
    c_bad "خواندن bot_updates ممکن نشد"
    exit 1
fi
echo "پیام‌های ۲۴ ساعت گذشته: $n"
if [[ "$n" == "0" ]]; then
    c_warn "در ۲۴ ساعت گذشته پیامی ثبت نشده؛ در بله یک دکمه بزنید و دوباره اجرا کنید"
fi
echo

# ── ۱) آخرین ۱۰ پیام: دو فاصله، جدا از هم ──────────────────────────
c_head "۱) آخرین ۱۰ پیام — تاخیر «بله→پایگاه» در برابر «پایگاه→ارسال»"
Q1=$(cat <<SQL
WITH m AS (
    SELECT u.update_id, u.chat_id, u.delivered_at,
           to_timestamp(NULLIF(u.raw #>> '{message,date}', '')::bigint) AS bale_at,
           u.received_at
      FROM iee1405.bot_updates u
     WHERE u.raw #>> '{message,date}' IS NOT NULL
       AND $FILTER_TS
     ORDER BY u.update_id DESC
     LIMIT 10
)
SELECT m.update_id                                AS "شناسه",
       to_char(m.bale_at AT TIME ZONE 'Asia/Tehran', 'HH24:MI:SS')  AS "زمان بله",
       round(EXTRACT(epoch FROM (m.received_at - m.bale_at))::numeric, 1)
                                                  AS "بله→پایگاه (ث)",
       round(EXTRACT(epoch FROM (m.delivered_at - m.received_at))::numeric, 1)
                                                  AS "پایگاه→ارسال (ث)",
       CASE WHEN m.delivered_at IS NULL THEN 'ارسال نشده' ELSE 'رسید' END AS "وضعیت"
  FROM m
 ORDER BY m.update_id DESC;
SQL
)
pgq_pretty "$PG_DB" -c "$Q1"
echo

# ── ۲) میانه: «۱۰ پیام آخر» جدا از «۲۴ ساعت» ────────────────────────
# چرا جدا؟ میانهٔ ۲۴ ساعته، ردیف‌های **پیش از** تغییر زمان‌بند (۲۰ ثانیه) را هم
# قاطی می‌کند و عدد بالا نشان می‌دهد، در حالی که پیام‌های تازه ۰٫۳ ثانیه‌اند.
# عدد صادق، «حالا» است — نه میانگین با دیروز.
c_head "۲) میانه — ۱۰ پیام آخر (حالا) در برابر ۲۴ ساعت (شامل قبل)"
Q2=$(cat <<SQL
WITH m AS (
    SELECT u.update_id,
           to_timestamp(NULLIF(u.raw #>> '{message,date}', '')::bigint) AS bale_at,
           u.received_at, u.delivered_at
      FROM iee1405.bot_updates u
     WHERE u.raw #>> '{message,date}' IS NOT NULL
       AND u.delivered_at IS NOT NULL
       AND $FILTER_TS
), recent AS (SELECT * FROM m ORDER BY update_id DESC LIMIT 10)
SELECT '۱۰ پیام آخر' AS "بازه",
       count(*) AS "تعداد",
       round(percentile_cont(0.5) WITHIN GROUP (
             ORDER BY EXTRACT(epoch FROM received_at - bale_at))::numeric, 1) AS "میانه بله→پایگاه",
       round(max(EXTRACT(epoch FROM received_at - bale_at))::numeric, 1)      AS "بیشینه",
       round(percentile_cont(0.5) WITHIN GROUP (
             ORDER BY EXTRACT(epoch FROM delivered_at - received_at))::numeric, 1) AS "میانه پایگاه→ارسال"
  FROM recent
UNION ALL
SELECT '۲۴ ساعت (شامل قبل)',
       count(*),
       round(percentile_cont(0.5) WITHIN GROUP (
             ORDER BY EXTRACT(epoch FROM received_at - bale_at))::numeric, 1),
       round(max(EXTRACT(epoch FROM received_at - bale_at))::numeric, 1),
       round(percentile_cont(0.5) WITHIN GROUP (
             ORDER BY EXTRACT(epoch FROM delivered_at - received_at))::numeric, 1)
  FROM m
 WHERE received_at > now() - interval '24 hours';
SQL
)
pgq_pretty "$PG_DB" -c "$Q2"
echo

# ── ۳) صف مانده و تازگی دریافت ──────────────────────────────────────
c_head "۳) صف ارسال و تازگی دریافت"
Q3=$(cat <<'SQL'
SELECT (SELECT count(*) FROM iee1405.pending_replies(100))            AS "در صف",
       (SELECT count(*) FROM iee1405.bot_updates
         WHERE reply_text IS NOT NULL AND delivered_at IS NULL
           AND received_at > now() - interval '24 hours')             AS "در صف (۲۴س)",
       (SELECT round(max(EXTRACT(epoch FROM (now() - received_at)))::numeric, 0)
          FROM iee1405.bot_updates
         WHERE reply_text IS NOT NULL AND delivered_at IS NULL)       AS "سنِ قدیمی‌ترین (ث)",
       (SELECT round(EXTRACT(epoch FROM (now() - value::timestamptz))::numeric, 1)
          FROM iee1405.bot_state WHERE key = 'last_poll_at')          AS "از آخرین دریافت (ث)";
SQL
)
pgq_pretty "$PG_DB" -c "$Q3"
echo

# ── ۴) خودِ n8n: فاصله، مدت، و اجراهای گیرکرده ─────────────────────
c_head "۴) اجراهای گردش‌کار در n8n (فاصله، مدت، گیرکرده)"
if pgq n8n -c "SELECT 1 FROM execution_entity LIMIT 1" >/dev/null 2>&1; then
    # نکتهٔ فنی: پنجره (lag) داخل aggregate مجاز نیست — یک بار همین‌جا خطای
    # «aggregate function calls cannot contain window function calls» داد.
    # پنجره در CTE جدا و تجمیع بیرون از آن انجام می‌شود.
    Q4=$(cat <<'SQL'
WITH e AS (
    SELECT e.id, e."startedAt", e."stoppedAt", e.status,
           EXTRACT(epoch FROM (e."stoppedAt" - e."startedAt")) AS dur
      FROM execution_entity e
     WHERE e."workflowId" IN (SELECT id FROM workflow_entity WHERE name LIKE 'IEE1405-01%')
       AND e."startedAt" > now() - interval '2 hours'
), with_gap AS (
    SELECT e.*,
           EXTRACT(epoch FROM (e."startedAt"
                 - lag(e."startedAt") OVER (ORDER BY e."startedAt"))) AS gap
      FROM e
)
SELECT count(*) FILTER (WHERE status = 'success')                       AS "موفق",
       count(*) FILTER (WHERE status = 'error')                         AS "خطا",
       count(*) FILTER (WHERE status = 'running')                       AS "گیرکرده",
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY dur)
             FILTER (WHERE dur IS NOT NULL)::numeric, 1)                AS "میانه مدت (ث)",
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY gap)
             FILTER (WHERE gap IS NOT NULL)::numeric, 1)                AS "میانه فاصله (ث)",
       round(max(gap) FILTER (WHERE gap IS NOT NULL)::numeric, 1)       AS "بیشینه فاصله (ث)"
  FROM with_gap;
SQL
)
    pgq_pretty n8n -c "$Q4"
    echo
    STUCK="$(pgq n8n -c "SELECT count(*) FROM execution_entity
                          WHERE status = 'running'
                            AND \"startedAt\" < now() - interval '10 minutes'" 2>/dev/null || echo 0)"
    OLDEST="$(pgq n8n -c "SELECT COALESCE(round(max(EXTRACT(epoch FROM (now() - \"startedAt\")) / 60)::numeric, 0)::text, '0')
                            FROM execution_entity WHERE status = 'running'" 2>/dev/null || echo 0)"
    echo "  اجراهای گیرکرده (بیش از ۱۰ دقیقه): ${STUCK:-0} · قدیمی‌ترین: ${OLDEST:-0} دقیقه"
    if [[ "${STUCK:-0}" != "0" && -n "${STUCK:-}" ]]; then
        c_warn "این‌ها ردیف‌های مردهٔ n8n هستند (اجرایی که هرگز تمام نشد) و صف را شلوغ می‌کنند"
        c_hint "bash 03_ops/clean_executions.sh"
    fi
else
    c_warn "پایگاه n8n خوانده نشد (دسترسی به دیتابیس n8n لازم است)؛ بخش ۱ تا ۳ معیارند"
fi
echo

# ── ۵) حکم: کدام مرحله کند است؟ ────────────────────────────────────
c_head "۵) حکم"
Q_IN=$(cat <<SQL
WITH m AS (
    SELECT to_timestamp(NULLIF(u.raw #>> '{message,date}', '')::bigint) AS b,
           u.received_at, u.update_id
      FROM iee1405.bot_updates u
     WHERE u.raw #>> '{message,date}' IS NOT NULL
       AND $FILTER_TS
     ORDER BY u.update_id DESC
     LIMIT 10
)
SELECT COALESCE(round(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY EXTRACT(epoch FROM received_at - b))::numeric, 1)::text, '—')
  FROM m;
SQL
)
Q_OUT=$(cat <<'SQL'
WITH m AS (
    SELECT received_at, delivered_at, update_id FROM iee1405.bot_updates
     WHERE delivered_at IS NOT NULL
     ORDER BY update_id DESC LIMIT 10
)
SELECT COALESCE(round(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY EXTRACT(epoch FROM delivered_at - received_at))::numeric, 1)::text, '—')
  FROM m;
SQL
)
me_in="$(pgq "$PG_DB" -c "$Q_IN" 2>/dev/null || echo '—')"
me_out="$(pgq "$PG_DB" -c "$Q_OUT" 2>/dev/null || echo '—')"
echo "  میانهٔ «بله→پایگاه» (۱۰ پیام آخر): ${me_in} ثانیه   ·   میانهٔ «پایگاه→ارسال»: ${me_out} ثانیه"

if [[ "$me_in" == "—" || "$me_out" == "—" ]]; then
    echo "  ← دادهٔ کافی نیست: هیچ پیام تازه‌ای با «تاریخ بله» ثبت نشده."
    echo "     در بله یک دکمه بزنید، ۱۵ ثانیه صبر کنید و دوباره اجرا کنید."
elif awk -v a="$me_in" 'BEGIN{exit !(a > 6)}'; then
    echo "  ← تاخیر عمدتاً در **دریافت** است: زمان‌بند گردش‌کار یا صف اجراهای n8n."
    echo "     زمان‌بند باید ۵ ثانیه باشد و getUpdates «long-poll ۴ ثانیه»؛ اگر بالاست:"
    echo "     bash 03_ops/import_workflows.sh import && bash 03_ops/import_workflows.sh activate"
elif awk -v a="$me_out" 'BEGIN{exit !(a > 6)}'; then
    echo "  ← تاخیر عمدتاً در **ارسال** است: خودِ بله کند جواب می‌دهد یا صف شلوغ است."
else
    echo "  ← هر دو مرحله سریع‌اند (زیر ۶ ثانیه). اگر در گوشی هنوز دیر می‌رسد،"
    echo "     کندی از سمت خودِ بله است؛ عددهای بالا را برای مقایسه نگه دارید."
fi
echo
echo "  برای اثبات زنده: در بله یک دکمه بزنید، ۱۵ ثانیه صبر کنید، و همین دستور را"
echo "  دوباره اجرا کنید — ردیف تازه با دو ستون تاخیر باید ظاهر شود."
