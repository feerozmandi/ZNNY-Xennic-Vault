#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — «چرا جواب ربات دیر می‌رسد؟»
#
# گزارش مالک: «جواب کلیدها خیلی با تاخیر می‌باشد». تاخیر سه جای مختلف می‌تواند
# باشد و درمان هر سه فرق می‌کند؛ این اسکریپت جای دقیق را نشان می‌دهد:
#
#   ۱) بله → پایگاه : فاصلهٔ زمان پیام در بله تا ثبت آن در bot_updates
#      ⇒ مشکل در «دریافت» (زمان‌بند گردش‌کار، صف اجراهای n8n)
#   ۲) پایگاه → ارسال : فاصلهٔ ثبت تا delivered_at
#      ⇒ مشکل در «ارسال» (کندی sendMessage بله یا شلوغی صف)
#   ۳) صف مانده : پاسخ‌هایی که هنوز ارسال نشده‌اند
#      ⇒ یعنی اجراها عقب افتاده‌اند
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

# ── ۰) پیش‌نیاز: آیا چیزی برای سنجیدن هست؟ ───────────────────────────
n="$(pgq "$PG_DB" -c "SELECT count(*) FROM iee1405.bot_updates
                       WHERE received_at > now() - interval '24 hours'" 2>/dev/null || echo "?")"
if [[ "$n" == "?" || -z "$n" ]]; then
    c_bad "خواندن bot_updates ممکن نشد"
    exit 1
fi
echo "پیام‌های ۲۴ ساعت گذشته: $n"
if [[ "$n" == "0" ]]; then
    c_warn "در ۲۴ ساعت گذشته پیامی ثبت نشده؛ در بله یک /start بزنید و دوباره اجرا کنید"
fi
echo

# ── ۱) آخرین ۱۰ پیام: دو فاصله، جدا از هم ──────────────────────────
c_head "۱) آخرین ۱۰ پیام — تاخیر «بله→پایگاه» در برابر «پایگاه→ارسال»"
pgq_pretty "$PG_DB" -c "
WITH m AS (
    SELECT u.update_id, u.chat_id, u.delivered_at,
           to_timestamp(NULLIF(u.raw #>> '{message,date}', '')::bigint) AS bale_at,
           u.received_at
      FROM iee1405.bot_updates u
     WHERE u.raw #>> '{message,date}' IS NOT NULL
       -- ردیف‌هایی که «تاریخ بله»‌شان با ثبت ما نمی‌خواند (دادهٔ آزمایشی با
       -- تاریخ ساختگی) میانه را بی‌معنا می‌کنند؛ کنار گذاشته می‌شوند.
       AND to_timestamp(NULLIF(u.raw #>> '{message,date}', '')::bigint)
           BETWEEN u.received_at - interval '10 minutes'
               AND u.received_at + interval '5 minutes'
     ORDER BY u.update_id DESC
     LIMIT 10
)
SELECT m.update_id                                AS \"شناسه\",
       to_char(m.bale_at AT TIME ZONE 'Asia/Tehran', 'HH24:MI:SS')  AS \"زمان بله\",
       round(EXTRACT(epoch FROM (m.received_at - m.bale_at))::numeric, 1)
                                                  AS \"بله→پایگاه (ث)\",
       round(EXTRACT(epoch FROM (m.delivered_at - m.received_at))::numeric, 1)
                                                  AS \"پایگاه→ارسال (ث)\",
       CASE WHEN m.delivered_at IS NULL THEN 'ارسال نشده' ELSE 'رسید' END AS \"وضعیت\"
  FROM m
 ORDER BY m.update_id DESC;"
echo

# ── ۲) میانه و بیشینه در ۲۴ ساعت ─────────────────────────────────────
c_head "۲) میانه/بیشینه در ۲۴ ساعت (فقط پیام‌های ارسال‌شده)"
pgq_pretty "$PG_DB" -c "
WITH m AS (
    SELECT to_timestamp(NULLIF(u.raw #>> '{message,date}', '')::bigint) AS bale_at,
           u.received_at, u.delivered_at
      FROM iee1405.bot_updates u
     WHERE u.received_at > now() - interval '24 hours'
       AND u.raw #>> '{message,date}' IS NOT NULL
       AND u.delivered_at IS NOT NULL
       AND to_timestamp(NULLIF(u.raw #>> '{message,date}', '')::bigint)
           BETWEEN u.received_at - interval '10 minutes'
               AND u.received_at + interval '5 minutes'
)
SELECT count(*)                                                          AS \"تعداد\",
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM received_at - bale_at))::numeric, 1)
                                                                         AS \"میانه بله→پایگاه\",
       round(max(EXTRACT(epoch FROM received_at - bale_at))::numeric, 1)  AS \"بیشینه بله→پایگاه\",
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM delivered_at - received_at))::numeric, 1)
                                                                         AS \"میانه پایگاه→ارسال\",
       round(max(EXTRACT(epoch FROM delivered_at - received_at))::numeric, 1) AS \"بیشینه پایگاه→ارسال\",
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM delivered_at - bale_at))::numeric, 1)
                                                                         AS \"میانه کل\"
  FROM m;"
echo

# ── ۳) صف مانده و تازگی دریافت ──────────────────────────────────────
c_head "۳) صف ارسال و تازگی دریافت"
pgq_pretty "$PG_DB" -c "
SELECT (SELECT count(*) FROM iee1405.pending_replies(100))            AS \"در صف\",
       (SELECT count(*) FROM iee1405.bot_updates
         WHERE reply_text IS NOT NULL AND delivered_at IS NULL
           AND received_at > now() - interval '24 hours')             AS \"در صف (۲۴س)\",
       (SELECT round(max(EXTRACT(epoch FROM (now() - received_at)))::numeric, 0)
          FROM iee1405.bot_updates
         WHERE reply_text IS NOT NULL AND delivered_at IS NULL)       AS \"سنِ قدیمی‌ترین (ث)\",
       (SELECT round(EXTRACT(epoch FROM (now() - value::timestamptz))::numeric, 1)
          FROM iee1405.bot_state WHERE key = 'last_poll_at')          AS \"از آخرین دریافت (ث)\";"
echo

# ── ۴) خودِ n8n: فاصلهٔ بین اجراها و مدت هر اجرا ───────────────────
c_head "۴) اجراهای گردش‌کار در n8n (فاصله و مدت)"
if pgq n8n -c "SELECT 1 FROM execution_entity LIMIT 1" >/dev/null 2>&1; then
    pgq_pretty n8n -c "
    WITH e AS (
        SELECT e.id, e.\"startedAt\", e.\"stoppedAt\",
               EXTRACT(epoch FROM (e.\"stoppedAt\" - e.\"startedAt\")) AS dur
          FROM execution_entity e
         WHERE e.\"workflowId\" IN (SELECT id FROM workflow_entity WHERE name LIKE 'IEE1405-01%')
           AND e.\"startedAt\" > now() - interval '2 hours'
    )
    SELECT count(*)                                                  AS \"اجرا (۲س)\",
           round(percentile_cont(0.5) WITHIN GROUP (ORDER BY dur)::numeric, 1) AS \"میانه مدت (ث)\",
           round(max(dur)::numeric, 1)                               AS \"بیشینه مدت (ث)\",
           round(percentile_cont(0.5) WITHIN GROUP (
                 ORDER BY EXTRACT(epoch FROM (\"startedAt\" - lag(\"startedAt\")
                              OVER (ORDER BY \"startedAt\"))))::numeric, 1) AS \"میانه فاصله (ث)\",
           round(max(EXTRACT(epoch FROM (\"startedAt\" - lag(\"startedAt\")
                       OVER (ORDER BY \"startedAt\"))))::numeric, 1)    AS \"بیشینه فاصله (ث)\"
      FROM e;"
    echo
    pgq_pretty n8n -c "
    SELECT count(*) FILTER (WHERE status = 'success')  AS \"موفق\",
           count(*) FILTER (WHERE status = 'error')    AS \"خطا\",
           count(*) FILTER (WHERE status = 'running')  AS \"در حال اجرا\",
           count(*) FILTER (WHERE status = 'waiting')  AS \"در انتظار\"
      FROM execution_entity
     WHERE \"startedAt\" > now() - interval '2 hours';"
else
    c_warn "پایگاه n8n خوانده نشد؛ بخش ۵ را دستی ببینید"
fi
echo

# ── ۵) حکم: کدام مرحله کند است؟ ────────────────────────────────────
c_head "۵) حکم"
me_in="$(pgq "$PG_DB" -c "
    WITH m AS (SELECT to_timestamp(NULLIF(raw #>> '{message,date}', '')::bigint) AS b,
                      received_at
                 FROM iee1405.bot_updates
                WHERE received_at > now() - interval '24 hours'
                  AND raw #>> '{message,date}' IS NOT NULL
                  AND to_timestamp(NULLIF(raw #>> '{message,date}', '')::bigint)
                      BETWEEN received_at - interval '10 minutes'
                          AND received_at + interval '5 minutes')
    SELECT COALESCE(round(percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM received_at - b))::numeric, 1)::text, '—')
      FROM m" 2>/dev/null || echo "—")"
me_out="$(pgq "$PG_DB" -c "
    WITH m AS (SELECT received_at, delivered_at FROM iee1405.bot_updates
                WHERE received_at > now() - interval '24 hours' AND delivered_at IS NOT NULL)
    SELECT COALESCE(round(percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM delivered_at - received_at))::numeric, 1)::text, '—')
      FROM m" 2>/dev/null || echo "—")"
echo "  میانهٔ «بله→پایگاه»: $me_in ثانیه   ·   میانهٔ «پایگاه→ارسال»: $me_out ثانیه"

if [[ "$me_in" != "—" ]] && awk -v a="$me_in" 'BEGIN{exit !(a > 6)}'; then
    echo "  ← تاخیر عمدتاً در **دریافت** است: زمان‌بند گردش‌کار یا صف اجراهای n8n."
    echo "     از نسخهٔ ۰.۱.۳۸ زمان‌بند ۵ ثانیه است و getUpdates «long-poll ۴ ثانیه» دارد؛"
    echo "     اگر هنوز بالا است، بخش ۴ را ببینید: مدت اجرا باید کوچک باشد و فاصله ≈ ۵ ثانیه."
elif [[ "$me_out" != "—" ]] && awk -v a="$me_out" 'BEGIN{exit !(a > 6)}'; then
    echo "  ← تاخیر عمدتاً در **ارسال** است: خودِ بله کند جواب می‌دهد یا صف ارسال شلوغ است."
    echo "     اگر «در صف» بالا و ثابت است، اجراها عقب‌اند؛ اگر صفر است، کندی از سمت بله است."
else
    echo "  ← هر دو مرحله سریع‌اند (زیر ۶ ثانیه). اگر در گوشی هنوز دیر می‌رسد،"
    echo "     کندی از سمت خودِ بله است؛ عددهای بالا را برای مقایسه نگه دارید."
fi
echo
echo "  برای اثبات زنده: در بله یک دکمه بزنید، ۱۵ ثانیه صبر کنید، و همین دستور را"
echo "  دوباره اجرا کنید — ردیف تازه با دو ستون تاخیر باید ظاهر شود."
