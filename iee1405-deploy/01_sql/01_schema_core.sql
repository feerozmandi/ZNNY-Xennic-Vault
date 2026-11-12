-- ═══════════════════════════════════════════════════════════════════════
-- IEE 1405 — Field Data Core Schema
-- پروژه: PRJ-IEE-004 / PRJ-IEE-015
-- هدف: ساخت پایگاه‌داده دائمی (نه موقت نمایشگاهی) برای شرکت‌ها، مخاطبان،
--       محصولات، ادعاها، تعاملات، وظایف و داده‌های نمایشگاه.
-- قواعد: idempotent است — اجرای دوباره خطا نمی‌دهد و داده را پاک نمی‌کند.
-- اجرا:  psql -v ON_ERROR_STOP=1 -f 01_schema_core.sql
-- ═══════════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS crm;
CREATE SCHEMA IF NOT EXISTS iee1405;

-- ─────────────────────────────────────────────────────────────────────
-- نگهبان امضای توابع
--   CREATE OR REPLACE FUNCTION فقط وقتی کار می‌کند که نوع خروجی یکی باشد.
--   اگر نسخهٔ نصب‌شده ستون‌های دیگری برگرداند، کل استقرار با این خطا می‌ایستد:
--     ERROR: cannot change return type of existing function
--   و چون هر فایل با ON_ERROR_STOP اجرا می‌شود، **بقیهٔ همان فایل اجرا نمی‌شود**
--   — یعنی ممکن است اصلاح تازه هرگز نصب نشود. این اتفاق دو بار روی سرور افتاد
--   (bot_dispatch_json و pending_replies).
--   این تابع، نسخهٔ کهنه را فقط وقتی حذف می‌کند که امضایش با کد یکی نباشد؛
--   در حالت عادی هیچ کاری نمی‌کند و پنجرهٔ «تابع وجود ندارد» باز نمی‌شود.
--   اجرا: SELECT iee1405.drop_stale_result('اسکیما', 'نام', 'TABLE(ستون نوع, …)');
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION iee1405.drop_stale_result(p_schema text, p_name text, p_expected text)
RETURNS boolean LANGUAGE plpgsql AS $guard$
DECLARE
    -- نرمال‌سازی: int ≡ integer، فاصله/خط تازه بی‌اثر، حروف کوچک
    v_norm text := btrim(regexp_replace(replace(lower(p_expected), 'integer', 'int'),
                                        '\s+', ' ', 'g'));
    r record;
    v_dropped boolean := false;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig,
               pg_get_function_result(p.oid) AS res,
               pg_get_function_identity_arguments(p.oid) AS args
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = p_schema
           AND p.proname = p_name
           AND btrim(regexp_replace(replace(lower(pg_get_function_result(p.oid)),
                                            'integer', 'int'), '\s+', ' ', 'g')) <> v_norm
    LOOP
        EXECUTE format('DROP FUNCTION %s', r.sig);
        -- نام تابع را دستی می‌سازیم: regprocedure اگر اسکیما در search_path
        -- نباشد، به‌جای نام، OID چاپ می‌کند و پیام بی‌معنا می‌شود.
        RAISE NOTICE 'امضای کهنه حذف شد: %.%(%) — نوع پیشین: %',
                     p_schema, p_name, r.args, r.res;
        v_dropped := true;
    END LOOP;
    RETURN v_dropped;
END $guard$;

COMMENT ON FUNCTION iee1405.drop_stale_result(text, text, text) IS
'حذف نسخهٔ تابع فقط وقتی نوع خروجی‌اش با کد یکی نیست؛ رفع «cannot change return type»';

-- افزونه‌ها (در صورت نبود دسترسی، اجرای آن‌ها اختیاری است)
DO $$
BEGIN
    BEGIN
        CREATE EXTENSION IF NOT EXISTS pgcrypto;
    EXCEPTION WHEN insufficient_privilege OR feature_not_supported THEN
        RAISE NOTICE 'pgcrypto نصب نشد — gen_random_uuid در PostgreSQL 13+ به‌صورت داخلی موجود است.';
    END;
    BEGIN
        CREATE EXTENSION IF NOT EXISTS pg_trgm;
    EXCEPTION WHEN insufficient_privilege OR feature_not_supported OR undefined_file THEN
        RAISE NOTICE 'pg_trgm نصب نشد — جست‌وجو با ILIKE انجام می‌شود.';
    END;
END $$;

COMMENT ON SCHEMA crm IS 'موجودیت‌های دائمی کسب‌وکار: شرکت، مخاطب، محصول، ادعا، تعامل، فرصت، وظیفه';
COMMENT ON SCHEMA iee1405 IS 'رخداد نمایشگاه ۱۴۰۵: حضور، غرفه، بازدید، یادداشت میدانی، ربات';

-- ─────────────────────────────────────────────────────────────────────
-- 1) انواع شمارشی
-- ─────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                   WHERE n.nspname = 'crm' AND t.typname = 'epistemic_status') THEN
        CREATE TYPE crm.epistemic_status AS ENUM ('verified', 'reported', 'observed', 'inferred');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                   WHERE n.nspname = 'crm' AND t.typname = 'org_type') THEN
        CREATE TYPE crm.org_type AS ENUM ('manufacturer', 'supplier', 'contractor', 'consultant',
                                          'trader', 'software', 'utility', 'other');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                   WHERE n.nspname = 'crm' AND t.typname = 'interaction_kind') THEN
        CREATE TYPE crm.interaction_kind AS ENUM ('visit', 'meeting', 'call', 'demo',
                                                  'negotiation', 'note', 'correction');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                   WHERE n.nspname = 'crm' AND t.typname = 'priority_group') THEN
        CREATE TYPE crm.priority_group AS ENUM ('A', 'B', 'C', 'watch', 'unknown');
    END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 2) توابع عمومی
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION crm.set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END $$;

-- افزایش خودکار نسخه در هر ویرایش (کنترل تعارض خوش‌بینانه)
CREATE OR REPLACE FUNCTION crm.bump_version() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.version := COALESCE(OLD.version, 0) + 1;
    NEW.updated_at := now();
    RETURN NEW;
END $$;

-- جلوگیری از تغییر/حذف رکوردهای فقط‌افزودنی
CREATE OR REPLACE FUNCTION crm.forbid_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'این جدول فقط افزودنی است: % مجاز نیست', TG_OP
        USING ERRCODE = 'insufficient_privilege',
              HINT = 'برای اصلاح، رکورد جدید (correction) ثبت کنید.';
END $$;

-- نرمال‌سازی متن فارسی/عربی برای مقایسه و جست‌وجو
CREATE OR REPLACE FUNCTION crm.norm_text(p text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT btrim(
             regexp_replace(
               translate(COALESCE(p, ''),
                         E'\u064A\u0643\u0629\u0649\u06CC\u06A9\u200C\u200D\u0640',
                         E'\u06CC\u06A9\u0647\u06CC\u06CC\u06A9   '),
               '\s+', ' ', 'g'))
$$;

COMMENT ON FUNCTION crm.norm_text(text) IS
'یکسان‌سازی ی/ک عربی-فارسی، نیم‌فاصله و کشیده، و فشرده‌سازی فاصله‌ها.

نیم‌فاصله (U+200C) به فاصله تبدیل می‌شود چون در کاتالوگ‌ها و فایل‌های اکسل،
یک شرکت هم با نیم‌فاصله و هم با فاصله نوشته می‌شود («برق‌آوران» / «برق آوران»)
و بدون این یکسان‌سازی، جست‌وجو و تطبیق نام، شرکت را پیدا نمی‌کند و ایمپورت
نسخه تکراری می‌سازد.';

-- تاریخ شمسی کوتاه برای متن پیام‌ها (فقط نمایش؛ مرجع ذخیره UTC است)
CREATE OR REPLACE FUNCTION crm.fa_date(p_ts timestamptz) RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT to_char(p_ts AT TIME ZONE 'Asia/Tehran', 'YYYY-MM-DD')
$$;

-- ─────────────────────────────────────────────────────────────────────
-- یکسان‌سازی ورودی برای تشخیص دستور ربات
--   چرا جدا از norm_text؟ چون دکمه‌های بله متن را با نویسه‌های جهت‌دهی و
--   نامرئی (U+200E/200F، U+202A–E، U+2066–9) و گاهی اعداد فارسی می‌فرستند.
--   نتیجهٔ واقعی روی سرور: دکمه‌ای که «/c» می‌فرستد به «دستور ناشناخته»
--   می‌رسید و کاربر فقط «برای شروع: /new …» می‌دید.
--   این تابع فقط برای **تشخیص** است؛ متن اصلی پیام دست‌نخورده ذخیره می‌شود.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION crm.cmd_text(p text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT btrim(regexp_replace(
             translate(
               translate(COALESCE(p, ''),
                         '۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩',
                         '01234567890123456789'),
               E'\u064A\u0643\u200C\u200D\u0640',
               E'\u06CC\u06A9   '),
             '[' || E'\u200B\u200E\u200F\u202A-\u202E\u2066-\u2069\uFEFF\u00A0'
                   || E'\t\n\r]' || '+', ' ', 'g'))
$$;

COMMENT ON FUNCTION crm.cmd_text(text) IS
'یکسان‌سازی ورودی برای تشخیص دستور: حذف نویسه‌های نامرئی/جهت‌دهی، ارقام فارسی،
ی/ک عربی و نیم‌فاصله. متن اصلی پیام تغییر نمی‌کند.';

-- ─────────────────────────────────────────────────────────────────────
-- 3) کاربران سامانه
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS crm.users (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    username      text NOT NULL UNIQUE,
    display_name  text,
    role          text NOT NULL DEFAULT 'field_agent'
                  CHECK (role IN ('owner', 'analyst', 'field_agent', 'viewer', 'service')),
    bale_chat_id  bigint UNIQUE,
    phone         text,
    is_active     boolean NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    last_seen_at  timestamptz
);

COMMENT ON TABLE crm.users IS 'کاربران انسانی و سرویس‌ها؛ هویت عامل در همه رویدادها';

-- ─────────────────────────────────────────────────────────────────────
-- 4) شرکت‌ها
-- ─────────────────────────────────────────────────────────────────────
CREATE SEQUENCE IF NOT EXISTS crm.organizations_code_seq;

CREATE TABLE IF NOT EXISTS crm.organizations (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code             text NOT NULL UNIQUE
                     DEFAULT ('ORG-' || lpad(nextval('crm.organizations_code_seq')::text, 6, '0')),
    client_uuid      uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    legal_name       text NOT NULL,
    display_name     text,
    name_norm        text GENERATED ALWAYS AS (crm.norm_text(legal_name)) STORED,
    legal_form       text,
    country          text NOT NULL DEFAULT 'IR',
    city             text,
    website          text,
    phone_main       text,
    email_main       text,
    org_type         crm.org_type NOT NULL DEFAULT 'other',
    initial_group    crm.priority_group,
    effective_group  crm.priority_group,
    score            numeric(5,2) CHECK (score IS NULL OR (score >= 0 AND score <= 100)),
    score_breakdown  jsonb,
    override_reason  text,
    status           text NOT NULL DEFAULT 'active'
                     CHECK (status IN ('active', 'watch', 'out', 'archived')),
    notes_general    text,
    version          integer NOT NULL DEFAULT 1,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    created_by       text NOT NULL DEFAULT 'system',
    updated_by       text NOT NULL DEFAULT 'system',
    deleted_at       timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS organizations_website_uq
    ON crm.organizations (lower(website)) WHERE website IS NOT NULL AND deleted_at IS NULL;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm') THEN
        CREATE INDEX IF NOT EXISTS organizations_name_trgm
            ON crm.organizations USING gin (name_norm gin_trgm_ops);
    ELSE
        CREATE INDEX IF NOT EXISTS organizations_name_idx
            ON crm.organizations (name_norm);
    END IF;
END $$;
CREATE INDEX IF NOT EXISTS organizations_group_idx
    ON crm.organizations (effective_group) WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS organizations_bump ON crm.organizations;
CREATE TRIGGER organizations_bump BEFORE UPDATE ON crm.organizations
    FOR EACH ROW EXECUTE FUNCTION crm.bump_version();

COMMENT ON TABLE crm.organizations IS 'شرکت/سازنده/تأمین‌کننده — دائمی و مستقل از نمایشگاه';

-- ─────────────────────────────────────────────────────────────────────
-- 5) مخاطبان
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS crm.contacts (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    client_uuid      uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    organization_id  uuid NOT NULL REFERENCES crm.organizations(id) ON DELETE CASCADE,
    full_name        text NOT NULL,
    role_title       text,
    role_type        text CHECK (role_type IN ('manager', 'sales', 'technical', 'procurement', 'other')),
    mobile           text,
    phone            text,
    email            text,
    messenger        text,
    preferred_channel text,
    is_primary       boolean NOT NULL DEFAULT false,
    consent_note     text,
    version          integer NOT NULL DEFAULT 1,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    created_by       text NOT NULL DEFAULT 'system',
    updated_by       text NOT NULL DEFAULT 'system',
    deleted_at       timestamptz
);

CREATE INDEX IF NOT EXISTS contacts_org_idx ON crm.contacts (organization_id) WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS contacts_bump ON crm.contacts;
CREATE TRIGGER contacts_bump BEFORE UPDATE ON crm.contacts
    FOR EACH ROW EXECUTE FUNCTION crm.bump_version();

-- ─────────────────────────────────────────────────────────────────────
-- 6) دسته‌بندی و محصول
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS crm.product_categories (
    code        text PRIMARY KEY,
    title_fa    text NOT NULL,
    title_en    text,
    parent_code text REFERENCES crm.product_categories(code),
    sort_order  integer NOT NULL DEFAULT 100
);

CREATE SEQUENCE IF NOT EXISTS crm.products_code_seq;

CREATE TABLE IF NOT EXISTS crm.products (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    client_uuid      uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    code             text NOT NULL UNIQUE
                     DEFAULT ('PRD-' || lpad(nextval('crm.products_code_seq')::text, 6, '0')),
    organization_id  uuid NOT NULL REFERENCES crm.organizations(id) ON DELETE CASCADE,
    category_code    text REFERENCES crm.product_categories(code),
    name             text NOT NULL,
    model_code       text,
    key_specs        jsonb NOT NULL DEFAULT '{}'::jsonb,
    standards        text[] NOT NULL DEFAULT '{}',
    availability     text,
    version          integer NOT NULL DEFAULT 1,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    created_by       text NOT NULL DEFAULT 'system',
    updated_by       text NOT NULL DEFAULT 'system',
    deleted_at       timestamptz
);

CREATE INDEX IF NOT EXISTS products_org_idx ON crm.products (organization_id) WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS products_bump ON crm.products;
CREATE TRIGGER products_bump BEFORE UPDATE ON crm.products
    FOR EACH ROW EXECUTE FUNCTION crm.bump_version();

-- ─────────────────────────────────────────────────────────────────────
-- 7) منابع و ادعاها (هسته صداقت داده)
-- ─────────────────────────────────────────────────────────────────────
CREATE SEQUENCE IF NOT EXISTS crm.sources_code_seq;

CREATE TABLE IF NOT EXISTS crm.sources (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code         text NOT NULL UNIQUE
                 DEFAULT ('SRC-' || lpad(nextval('crm.sources_code_seq')::text, 6, '0')),
    source_type  text NOT NULL CHECK (source_type IN
                 ('catalog', 'website', 'business_card', 'verbal', 'photo', 'audio',
                  'official_list', 'third_party', 'field_note', 'bot_message')),
    title        text NOT NULL,
    uri          text,
    attachment_id uuid,
    captured_by  text NOT NULL DEFAULT 'system',
    captured_at  timestamptz NOT NULL DEFAULT now(),
    reliability  smallint NOT NULL DEFAULT 3 CHECK (reliability BETWEEN 1 AND 5)
);

CREATE TABLE IF NOT EXISTS crm.claims (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    client_uuid       uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    subject_type      text NOT NULL CHECK (subject_type IN ('organization', 'contact', 'product')),
    subject_id        uuid NOT NULL,
    attribute         text NOT NULL,
    value_text        text,
    value_number      numeric,
    value_unit        text,
    value_json        jsonb,
    epistemic_status  crm.epistemic_status NOT NULL,
    source_id         uuid REFERENCES crm.sources(id),
    asserted_by       text,
    observed_at       timestamptz NOT NULL DEFAULT now(),
    reviewed_at       timestamptz,
    confidence        smallint CHECK (confidence IS NULL OR confidence BETWEEN 1 AND 5),
    superseded_by     uuid REFERENCES crm.claims(id),
    is_current        boolean NOT NULL DEFAULT true,
    created_by        text NOT NULL DEFAULT 'system',
    created_at        timestamptz NOT NULL DEFAULT now(),
    -- قواعد ساختاری سطح اعتبار
    CONSTRAINT claims_verified_needs_source
        CHECK (epistemic_status <> 'verified' OR source_id IS NOT NULL),
    CONSTRAINT claims_reported_needs_asserter
        CHECK (epistemic_status <> 'reported' OR (asserted_by IS NOT NULL AND length(btrim(asserted_by)) > 0)),
    CONSTRAINT claims_inferred_needs_confidence
        CHECK (epistemic_status <> 'inferred' OR confidence IS NOT NULL)
);

-- فقط یک ادعای جاری برای هر (موضوع، مشخصه)
CREATE UNIQUE INDEX IF NOT EXISTS claims_current_uq
    ON crm.claims (subject_type, subject_id, attribute) WHERE is_current;
CREATE INDEX IF NOT EXISTS claims_subject_idx ON crm.claims (subject_type, subject_id);

-- ─────────────────────────────────────────────────────────────────────
-- 8) تعاملات، فرصت‌ها، وظایف
-- ─────────────────────────────────────────────────────────────────────
CREATE SEQUENCE IF NOT EXISTS crm.interactions_code_seq;

CREATE TABLE IF NOT EXISTS crm.interactions (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code               text NOT NULL UNIQUE
                       DEFAULT ('INT-' || lpad(nextval('crm.interactions_code_seq')::text, 6, '0')),
    client_uuid        uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    organization_id    uuid NOT NULL REFERENCES crm.organizations(id) ON DELETE CASCADE,
    contact_id         uuid REFERENCES crm.contacts(id),
    kind               crm.interaction_kind NOT NULL DEFAULT 'meeting',
    occurred_at        timestamptz NOT NULL DEFAULT now(),
    channel            text NOT NULL DEFAULT 'bale',
    summary            text NOT NULL,
    detail             text,
    our_commitments    text,
    their_commitments  text,
    sentiment          smallint CHECK (sentiment IS NULL OR sentiment BETWEEN 0 AND 5),
    next_action        text,
    next_action_due    date,
    recorded_by        text NOT NULL DEFAULT 'system',
    created_at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS interactions_org_idx
    ON crm.interactions (organization_id, occurred_at DESC);

DROP TRIGGER IF EXISTS interactions_immutable ON crm.interactions;
CREATE TRIGGER interactions_immutable BEFORE UPDATE OR DELETE ON crm.interactions
    FOR EACH ROW EXECUTE FUNCTION crm.forbid_mutation();

CREATE SEQUENCE IF NOT EXISTS crm.opportunities_code_seq;

CREATE TABLE IF NOT EXISTS crm.opportunities (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code             text NOT NULL UNIQUE
                     DEFAULT ('OPP-' || lpad(nextval('crm.opportunities_code_seq')::text, 6, '0')),
    organization_id  uuid NOT NULL REFERENCES crm.organizations(id) ON DELETE CASCADE,
    title            text NOT NULL,
    type             text NOT NULL DEFAULT 'supply'
                     CHECK (type IN ('supply', 'project', 'agency', 'tech_partner', 'resale', 'out_of_scope')),
    stage            text NOT NULL DEFAULT 'idea'
                     CHECK (stage IN ('idea', 'qualified', 'contacted', 'negotiating', 'won', 'lost', 'hold')),
    value_estimate   numeric(18,2),
    currency         text DEFAULT 'IRR',
    probability      smallint CHECK (probability IS NULL OR probability BETWEEN 0 AND 100),
    owner            text,
    next_step        text,
    closed_at        timestamptz,
    version          integer NOT NULL DEFAULT 1,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    created_by       text NOT NULL DEFAULT 'system',
    updated_by       text NOT NULL DEFAULT 'system'
);

DROP TRIGGER IF EXISTS opportunities_bump ON crm.opportunities;
CREATE TRIGGER opportunities_bump BEFORE UPDATE ON crm.opportunities
    FOR EACH ROW EXECUTE FUNCTION crm.bump_version();

CREATE SEQUENCE IF NOT EXISTS crm.tasks_code_seq;

CREATE TABLE IF NOT EXISTS crm.tasks (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code                  text NOT NULL UNIQUE
                          DEFAULT ('TSK-' || lpad(nextval('crm.tasks_code_seq')::text, 6, '0')),
    organization_id       uuid REFERENCES crm.organizations(id) ON DELETE CASCADE,
    opportunity_id        uuid REFERENCES crm.opportunities(id) ON DELETE SET NULL,
    source_interaction_id uuid REFERENCES crm.interactions(id),
    title                 text NOT NULL,
    due_date              date NOT NULL,
    priority              text NOT NULL DEFAULT 'medium'
                          CHECK (priority IN ('high', 'medium', 'low')),
    assignee              text NOT NULL DEFAULT 'ahmad',
    status                text NOT NULL DEFAULT 'open'
                          CHECK (status IN ('open', 'done', 'cancelled')),
    completed_at          timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS tasks_open_idx ON crm.tasks (due_date) WHERE status = 'open';

-- ─────────────────────────────────────────────────────────────────────
-- 9) فایل‌ها و پیشنهادهای هوش مصنوعی
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS crm.attachments (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sha256        text NOT NULL UNIQUE,
    kind          text NOT NULL CHECK (kind IN ('photo', 'audio', 'catalog', 'scan', 'other')),
    mime          text NOT NULL,
    size_bytes    bigint NOT NULL,
    storage_path  text NOT NULL,
    duration_sec  integer,
    linked_entity text,
    linked_id     uuid,
    privacy_flag  text[] NOT NULL DEFAULT '{}',
    captured_at   timestamptz,
    uploaded_by   text NOT NULL DEFAULT 'system',
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS attachments_link_idx ON crm.attachments (linked_entity, linked_id);

CREATE TABLE IF NOT EXISTS crm.ai_suggestions (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    target_entity    text NOT NULL,
    target_id        uuid,
    suggestion_type  text NOT NULL,
    payload          jsonb NOT NULL,
    model            text,
    model_version    text,
    prompt_hash      text,
    status           text NOT NULL DEFAULT 'proposed'
                     CHECK (status IN ('proposed', 'accepted', 'rejected')),
    reviewed_by      text,
    reviewed_at      timestamptz,
    created_at       timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE crm.ai_suggestions IS 'خروجی AI فقط پیشنهاد است؛ هرگز مستقیم به فیلد قطعی تبدیل نمی‌شود';

-- ─────────────────────────────────────────────────────────────────────
-- 10) گزارش رویدادها (فقط افزودنی)
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS crm.audit_events (
    id           bigserial PRIMARY KEY,
    occurred_at  timestamptz NOT NULL DEFAULT now(),
    actor        text NOT NULL,
    action       text NOT NULL,
    entity       text NOT NULL,
    entity_id    uuid,
    diff         jsonb,
    meta         jsonb,
    request_id   text,
    ip_hash      text
);

CREATE INDEX IF NOT EXISTS audit_events_time_idx ON crm.audit_events (occurred_at DESC);
CREATE INDEX IF NOT EXISTS audit_events_entity_idx ON crm.audit_events (entity, entity_id);

DROP TRIGGER IF EXISTS audit_events_immutable ON crm.audit_events;
CREATE TRIGGER audit_events_immutable BEFORE UPDATE OR DELETE ON crm.audit_events
    FOR EACH ROW EXECUTE FUNCTION crm.forbid_mutation();

CREATE OR REPLACE FUNCTION crm.audit(
    p_actor text, p_action text, p_entity text, p_entity_id uuid,
    p_diff jsonb DEFAULT NULL, p_meta jsonb DEFAULT NULL, p_request_id text DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE v_id bigint;
BEGIN
    INSERT INTO crm.audit_events (actor, action, entity, entity_id, diff, meta, request_id)
    VALUES (COALESCE(p_actor, 'system'), p_action, p_entity, p_entity_id, p_diff, p_meta, p_request_id)
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 11) جداول نمایشگاه
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS iee1405.exhibitions (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code              text NOT NULL UNIQUE,
    title             text NOT NULL,
    start_date        date NOT NULL,
    end_date          date NOT NULL,
    venue             text,
    city              text,
    official_source_id uuid REFERENCES crm.sources(id),
    verified_at       timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS iee1405.booths (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    exhibition_id  uuid NOT NULL REFERENCES iee1405.exhibitions(id) ON DELETE CASCADE,
    hall           text,
    number         text NOT NULL,
    location_note  text,
    UNIQUE (exhibition_id, hall, number)
);

CREATE TABLE IF NOT EXISTS iee1405.participations (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id    uuid NOT NULL REFERENCES crm.organizations(id) ON DELETE CASCADE,
    exhibition_id      uuid NOT NULL REFERENCES iee1405.exhibitions(id) ON DELETE CASCADE,
    hall               text,
    booth_number       text,
    participation_type text NOT NULL DEFAULT 'exhibitor'
                       CHECK (participation_type IN ('exhibitor', 'visitor', 'both')),
    brands_shown       text[] NOT NULL DEFAULT '{}',
    confirmed          boolean NOT NULL DEFAULT false,
    created_at         timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, exhibition_id)
);

CREATE INDEX IF NOT EXISTS participations_booth_idx
    ON iee1405.participations (exhibition_id, hall, booth_number);

CREATE SEQUENCE IF NOT EXISTS iee1405.visits_code_seq;

CREATE TABLE IF NOT EXISTS iee1405.visits (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    client_uuid      uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    code             text NOT NULL UNIQUE
                     DEFAULT ('VIS-' || lpad(nextval('iee1405.visits_code_seq')::text, 6, '0')),
    organization_id  uuid NOT NULL REFERENCES crm.organizations(id) ON DELETE CASCADE,
    exhibition_id    uuid NOT NULL REFERENCES iee1405.exhibitions(id) ON DELETE CASCADE,
    visited_at       timestamptz NOT NULL DEFAULT now(),
    by_user          text NOT NULL,
    duration_min     integer,
    outcome          text NOT NULL DEFAULT 'data_only'
                     CHECK (outcome IN ('data_only', 'follow_up', 'meeting_set', 'not_relevant')),
    created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS visits_exhibition_idx
    ON iee1405.visits (exhibition_id, visited_at DESC);

CREATE TABLE IF NOT EXISTS iee1405.field_notes (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    client_uuid      uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    organization_id  uuid REFERENCES crm.organizations(id) ON DELETE CASCADE,
    raw_text         text,
    transcript       text,
    language         text DEFAULT 'fa',
    device           text,
    sync_state       text NOT NULL DEFAULT 'synced'
                     CHECK (sync_state IN ('local_only', 'synced')),
    captured_at      timestamptz NOT NULL DEFAULT now(),
    synced_at        timestamptz,
    created_by       text NOT NULL DEFAULT 'system'
);

-- لاگ خام پیام‌های ربات + Idempotency بر اساس update_id
CREATE TABLE IF NOT EXISTS iee1405.bot_updates (
    update_id    bigint PRIMARY KEY,
    chat_id      bigint,
    actor        text,
    raw          jsonb NOT NULL,
    command      text,
    status       text NOT NULL DEFAULT 'received'
                 CHECK (status IN ('received', 'processed', 'skipped', 'error')),
    reply_text   text,
    error        text,
    received_at  timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz
);

CREATE TABLE IF NOT EXISTS iee1405.bot_errors (
    id          bigserial PRIMARY KEY,
    update_id   bigint,
    chat_id     bigint,
    stage       text,
    message     text NOT NULL,
    detail      text,
    occurred_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE iee1405.bot_updates IS 'لاگ کامل آپدیت‌های بله + جلوگیری از پردازش دوباره (Idempotency)';

-- ─────────────────────────────────────────────────────────────────────
-- 12) وضعیت گفت‌وگوی ربات (پایدار، نه در حافظه)
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS iee1405.bot_sessions (
    chat_id    bigint PRIMARY KEY,
    actor      text,
    state      text NOT NULL DEFAULT 'idle',
    payload    jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL DEFAULT (now() + interval '30 minutes')
);

COMMENT ON TABLE iee1405.bot_sessions IS 'وضعیت جریان گفت‌وگوی هر کاربر؛ با ری‌استارت سرویس از دست نمی‌رود';
