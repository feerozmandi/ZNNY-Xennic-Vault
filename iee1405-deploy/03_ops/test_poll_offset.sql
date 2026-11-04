-- ═══════════════════════════════════════════════════════════════════════
-- آزمون offset دریافت بله — روی کلاستر محلی
-- اجرا: python3 03_ops/psqlrun.py 03_ops/test_poll_offset.sql
--        یا: psql -d <db> -v ON_ERROR_STOP=1 -f 03_ops/test_poll_offset.sql
--
-- چه چیزی را ثابت می‌کند؟
--   T1  دستهٔ تازه: offset تا بزرگ‌ترین شناسهٔ همان دسته جلو می‌رود
--   T2  دستهٔ خالی: offset تکان نمی‌خورد
--   T3  ردیف دستی با شناسهٔ غول‌آسا offset را مسموم نمی‌کند (باگ واقعی سرور)
--   T4  همان ردیف یک‌بار در bot_errors با stage='offset_guard' ثبت می‌شود
--   T5  poll_reset همه‌چیز را صفر می‌کند
-- همه‌چیز داخل تراکنش است و با ROLLBACK برمی‌گردد.
-- ═══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

BEGIN;

DELETE FROM iee1405.bot_errors WHERE stage IN ('offset_guard', 'test');
SELECT iee1405.poll_reset(0);

-- ── T1: دستهٔ ۹۷ و ۹۹ ────────────────────────────────────────────────
SELECT iee1405.poll_watch('{"ok":true,"result":[{"update_id":97},{"update_id":99}]}'::jsonb);
SELECT 'T1' AS t, iee1405.poll_advance() AS offset_after_batch;   -- انتظار: 99

-- ── T2: دستهٔ خالی ───────────────────────────────────────────────────
SELECT iee1405.poll_watch('{"ok":true,"result":[]}'::jsonb);
SELECT 'T2' AS t, iee1405.poll_advance() AS offset_after_empty;   -- انتظار: 99

-- ── T3: ردیف دستی با شناسهٔ غول‌آسا (همان چیزی که سرور را خواباند) ──
INSERT INTO iee1405.bot_updates (update_id, chat_id, raw, command, status, reply_text)
VALUES (17938002402, 389570094, '{}'::jsonb, '/c', 'processed', 'ردیف آزمایشی');
SELECT iee1405.poll_watch('{"ok":true,"result":[]}'::jsonb);
SELECT 'T3' AS t, iee1405.poll_advance() AS offset_after_poison;  -- انتظار: 99 نه ۱۷٫۹ میلیارد
SELECT 'T3b' AS t, iee1405.poll_offset() AS stored_offset;         -- انتظار: 99

-- ── T4: هشدار یک‌باره در bot_errors ─────────────────────────────────
SELECT 'T4' AS t, count(*) AS guard_rows
  FROM iee1405.bot_errors WHERE stage = 'offset_guard' AND update_id = 17938002402;
-- انتظار: 1 (و با اجرای دوبارهٔ poll_advance باز هم 1 بماند)
SELECT iee1405.poll_advance();
SELECT 'T4b' AS t, count(*) AS guard_rows_again
  FROM iee1405.bot_errors WHERE stage = 'offset_guard' AND update_id = 17938002402;

-- ── T5: بازنشانی ────────────────────────────────────────────────────
SELECT 'T5' AS t, iee1405.poll_reset(0) AS after_reset;            -- انتظار: 0

ROLLBACK;
