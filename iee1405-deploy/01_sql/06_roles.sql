-- ═══════════════════════════════════════════════════════════════════════
-- IEE 1405 — نقش‌ها و دسترسی‌ها (اصل حداقل دسترسی)
-- اجرا: با کاربر superuser (postgres) روی همان دیتابیس
--   psql -v ON_ERROR_STOP=1 -v app_password='...' -f 06_roles.sql
--
-- نقش‌ها:
--   iee_app   → n8n و ربات: اجرای توابع + خواندن نماها. بدون DDL، بدون DELETE.
--   iee_panel → WordPress (فاز بعد): فقط نماها و توابع API
--   iee_report→ فقط SELECT روی نماها (برای ابزار گزارش‌گیری)
--
-- رمز از متغیر می‌آید و در فایل ذخیره نمی‌شود:
--   psql -v app_password="$(openssl rand -base64 24)" ...
-- ═══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── نقش n8n / ربات ────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iee_app') THEN
        CREATE ROLE iee_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iee_panel') THEN
        CREATE ROLE iee_panel LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iee_report') THEN
        CREATE ROLE iee_report LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    END IF;
END $$;

-- رمز فقط اگر داده شده باشد (در فایل نوشته نمی‌شود)
\if :{?app_password}
    ALTER ROLE iee_app   PASSWORD :'app_password';
    ALTER ROLE iee_panel PASSWORD :'app_password';
\endif

-- ── دسترسی پایه ───────────────────────────────────────────────────────
REVOKE ALL ON SCHEMA crm      FROM PUBLIC;
REVOKE ALL ON SCHEMA iee1405  FROM PUBLIC;

GRANT USAGE ON SCHEMA crm, iee1405 TO iee_app, iee_panel, iee_report;

-- n8n/ربات: اجرای همه توابع، خواندن نماها، بدون DDL/DELETE
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA crm     TO iee_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA iee1405 TO iee_app;

GRANT SELECT ON ALL TABLES    IN SCHEMA crm     TO iee_app, iee_panel, iee_report;
GRANT SELECT ON ALL TABLES    IN SCHEMA iee1405 TO iee_app, iee_panel, iee_report;
GRANT INSERT, UPDATE ON crm.organizations, crm.contacts, crm.products, crm.sources,
                         crm.claims, crm.interactions, crm.opportunities, crm.tasks,
                         crm.attachments, crm.ai_suggestions,
                         iee1405.booths, iee1405.participations, iee1405.visits,
                         iee1405.field_notes, iee1405.bot_updates, iee1405.bot_errors,
                         iee1405.bot_sessions, iee1405.bot_state
    TO iee_app;

-- ── نوشتن‌های ستونی و ممیزی ───────────────────────────────────────────
-- ربات فقط «آخرین بازدید» کاربر را به‌روز می‌کند؛ UPDATE کل جدول کاربران
-- نمی‌دهیم تا نقش ربات نتواند نقش/وضعیت کاربر را عوض کند.
-- (خطای واقعی: permission denied for table users)
GRANT UPDATE (last_seen_at, bale_chat_id) ON crm.users TO iee_app;

-- هر تغییری که ربات ثبت می‌کند باید در ممیزی هم بنشیند (crm.audit).
-- بدون INSERT این‌جا، ثبت داده بی‌ممیزی می‌شود یا کلاً شکست می‌خورد.
GRANT INSERT ON crm.audit_events TO iee_app;

-- ── سیکوئنس‌ها: محل خطای واقعی ─────────────────────────────────────────
-- جدول‌ها شناسه‌هایی دارند که با nextval ساخته می‌شوند (bot_errors.id،
-- crm.organizations.code، crm.tasks.code و …). INSERT بدون USAGE روی
-- سیکوئنس شکست می‌خورد: «permission denied for sequence bot_errors_id_seq».
-- GRANT INSERT روی جدول این را نمی‌دهد؛ سیکوئنس دسترسی جدا دارد.
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA crm     TO iee_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA iee1405 TO iee_app;

-- سیکوئنس‌هایی که در استقرارهای بعدی ساخته می‌شوند هم همین دسترسی را بگیرند
ALTER DEFAULT PRIVILEGES IN SCHEMA crm
    GRANT USAGE, SELECT ON SEQUENCES TO iee_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA iee1405
    GRANT USAGE, SELECT ON SEQUENCES TO iee_app;

-- پنل WordPress: فقط نوشتن از طریق توابع/نماها (فاز ۲)
GRANT SELECT ON ALL TABLES IN SCHEMA crm TO iee_panel;

-- ── آینهٔ فهرست نمایشگاه (اسکیمای barghpa) ─────────────────────────────
-- چرا این بلوک لازم است: `deploy_sql.sh` فایل 08 (که آینه را می‌سازد) را
-- **پیش از** این فایل اجرا می‌کند، پس بلوک گرنت داخل 08 نقش هنوز موجود نیست
-- و بی‌صدا رد می‌شود؛ نتیجه: ربات با «permission denied for schema barghpa»
-- می‌افتد. اینجا نقش‌ها قطعاً ساخته شده‌اند.
-- آینه فقط‌خواندنی است: هیچ INSERT/UPDATE/DELETE به هیچ نقشی داده نمی‌شود.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'barghpa') THEN
        EXECUTE 'REVOKE ALL ON SCHEMA barghpa FROM PUBLIC';
        EXECUTE 'GRANT USAGE ON SCHEMA barghpa TO iee_app, iee_panel, iee_report';
        EXECUTE 'GRANT SELECT ON ALL TABLES IN SCHEMA barghpa TO iee_app, iee_panel, iee_report';
        EXECUTE 'GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA barghpa TO iee_app, iee_report';
        EXECUTE 'REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA barghpa '
                'FROM iee_app, iee_panel, iee_report';
        EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA barghpa '
                'GRANT SELECT ON TABLES TO iee_app, iee_panel, iee_report';
    ELSE
        RAISE NOTICE 'اسکیمای barghpa وجود ندارد؛ گرنت آینه رد شد (آینه اختیاری است)';
    END IF;
END $$;

-- نقش‌های آینده هم همین دسترسی را بگیرند
ALTER DEFAULT PRIVILEGES IN SCHEMA crm
    GRANT SELECT ON TABLES TO iee_app, iee_panel, iee_report;
ALTER DEFAULT PRIVILEGES IN SCHEMA iee1405
    GRANT SELECT ON TABLES TO iee_app, iee_panel, iee_report;

-- محدودیت منابع برای جلوگیری از پرس‌وجوهای سنگین
ALTER ROLE iee_app    SET statement_timeout = '30s';
ALTER ROLE iee_app    SET idle_in_transaction_session_timeout = '60s';
ALTER ROLE iee_panel  SET statement_timeout = '15s';
ALTER ROLE iee_report SET statement_timeout = '60s';

-- هیچ‌کدام نمی‌توانند ساختار را تغییر دهند یا داده را حذف کنند
REVOKE CREATE ON SCHEMA public FROM iee_app, iee_panel, iee_report;

-- ── بازبینی: هر چیزی که iee_app نمی‌تواند بسازد/بنویسد، همین‌جا دیده شود ──
-- بدون این، کمبود دسترسی فقط وقتی معلوم می‌شود که ربات در نیمه‌شب کار نکند.
CREATE OR REPLACE FUNCTION iee1405.privilege_gaps()
RETURNS TABLE (kind text, object_name text, needed text)
LANGUAGE sql STABLE AS $$
    -- سیکوئنس‌هایی که iee_app روی آن‌ها USAGE ندارد
    -- زیرپرس‌وجو لازم است: اگر شرط relkind در همان SELECT باشد، ممکن است
    -- has_sequence_privilege روی ایندکس‌های TOAST هم صدا زده شود و خطا بدهد.
    -- MATERIALIZED لازم است: بدون آن، برنامه‌ریز شرط relkind را جابه‌جا می‌کند و
    -- has_sequence_privilege روی ایندکس‌های TOAST صدا زده می‌شود → خطا.
    SELECT 'sequence', format('%s.%s', s.nspname, s.relname), 'USAGE'
      FROM (SELECT c.oid, c.relname, n.nspname
              FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE c.relkind = 'S' AND n.nspname IN ('crm', 'iee1405')
             OFFSET 0) s
     WHERE NOT has_sequence_privilege('iee_app', s.oid, 'USAGE')
    UNION ALL
    -- ستون‌هایی که ربات به‌روز می‌کند
    SELECT 'column', 'crm.users.last_seen_at', 'UPDATE'
     WHERE NOT has_column_privilege('iee_app', 'crm.users', 'last_seen_at', 'UPDATE')
    UNION ALL
    SELECT 'table', 'crm.audit_events', 'INSERT'
     WHERE NOT has_table_privilege('iee_app', 'crm.audit_events', 'INSERT')
    UNION ALL
    -- جدول‌هایی که ربات باید در آن‌ها بنویسد ولی INSERT ندارد
    SELECT 'table', format('%s.%s', n.nspname, c.relname), 'INSERT'
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relkind = 'r' AND n.nspname = 'iee1405'
       AND c.relname IN ('bot_updates', 'bot_errors', 'bot_state', 'bot_sessions')
       AND NOT has_table_privilege('iee_app', c.oid, 'INSERT')
$$;

COMMENT ON FUNCTION iee1405.privilege_gaps IS 'کمبود دسترسی نقش iee_app؛ خروجی خالی = سالم';

\echo '✅ نقش‌ها ساخته شد: iee_app (n8n/ربات) · iee_panel (WordPress) · iee_report (گزارش)'
\echo '   بازبینی دسترسی: SELECT * FROM iee1405.privilege_gaps();'
