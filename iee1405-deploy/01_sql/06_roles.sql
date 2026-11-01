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

-- پنل WordPress: فقط نوشتن از طریق توابع/نماها (فاز ۲)
GRANT SELECT ON ALL TABLES IN SCHEMA crm TO iee_panel;

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

\echo '✅ نقش‌ها ساخته شد: iee_app (n8n/ربات) · iee_panel (WordPress) · iee_report (گزارش)'
