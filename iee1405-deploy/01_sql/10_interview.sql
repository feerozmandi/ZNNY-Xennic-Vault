-- ═══════════════════════════════════════════════════════════════════════
-- IEE 1405 — مصاحبهٔ کوتاه در غرفه (ثبت همکاری اطلاعاتی)
--
-- خواستهٔ مالک: «دکمه‌ای زیر کارت شرکت برای مصاحبه، تا بر اساس مستندات
-- مصاحبه‌ای ثبت شود در جهت به‌دست‌آوردن همکاری اطلاعاتی؛ اول نام
-- مصاحبه‌شونده و سمتش ثبت شود.»
--
-- اصول (بر پایهٔ PRJ-IEE-012 و R5 در L2-MKT-006):
--   • شرکت نمایشگاه مشتری نیست؛ مصاحبه در اسکیمای iee1405 ذخیره می‌شود و
--     هیچ ردیفی در crm.organizations نمی‌سازد.
--   • شناسهٔ آینه فقط «مرجع» است، بدون کلید خارجی: `DROP SCHEMA barghpa
--     CASCADE` نباید مصاحبه‌ها را بشکند یا پاک کند. نام شرکت هم عکس‌برداری
--     می‌شود تا پس از بازنویسی آینه، مصاحبه بی‌نام نماند.
--   • هر پاسخ سطح `reported` دارد: «آنچه در غرفه گفته شد»، نه واقعیت تأییدشده.
--   • هیچ سؤالی قیمت، تخفیف یا اطلاعات محرمانه نمی‌پرسد؛ همه قابل پاسخ در
--     سه دقیقه‌اند. سؤال بی‌جواب، بدتر از سؤال کم است.
--
-- سؤال‌ها در جدول `iv_bank` می‌نشینند، نه در کد؛ مالک می‌تواند متنشان را با
-- یک UPDATE عوض کند و لازم نیست کسی دوباره استقرار کند.
-- ═══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── ۱) بانک سؤال ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS iee1405.iv_bank (
    code        text PRIMARY KEY,
    ord         int  NOT NULL UNIQUE,
    topic       text NOT NULL,             -- محور: فعالیت | توان | نیاز | همکاری | شاهد | پیگیری
    text_fa     text NOT NULL,             -- متن سؤال، همان‌طور که در بله دیده می‌شود
    why_fa      text,                      -- چرا این را می‌پرسیم (برای مستندسازی)
    ask_default boolean NOT NULL DEFAULT true,   -- در جریان عادی پرسیده شود؟
    added_at    timestamptz NOT NULL DEFAULT now()
);

-- سؤال‌ها فقط یک بار کاشته می‌شوند؛ متن دست‌کاری‌شدهٔ مالک بازنویسی نمی‌شود.
INSERT INTO iee1405.iv_bank (code, ord, topic, text_fa, why_fa, ask_default) VALUES
 ('activity', 1, 'فعالیت',
  'شرکت شما بیشتر در چه حوزه‌ای کار می‌کند و شما چه نقشی در شرکت دارید؟',
  'حوزهٔ فعالیت در فهرست ممکن است ناقص یا کهنه باشد؛ گفتهٔ خودشان معتبرترین منبع است.', true),
 ('offer',    2, 'توان',
  'محصول یا خدمت اصلی که امسال روی آن تمرکز دارید چیست؟',
  'برای تطبیق با نیاز پروژه‌ها، باید بدانیم «چه می‌سازند»، نه «چه می‌فروشند».', true),
 ('capacity', 3, 'توان',
  'بازهٔ توان فنی و ظرفیت تولیدتان کجاست؟ (ولتاژ، تناژ، تعداد در ماه)',
  'عدد، معیار مقایسه است؛ توصیف کلی («خیلی خوب») قابل ارزیابی نیست.', true),
 ('gap',      4, 'نیاز',
  'بزرگ‌ترین گلوگاه این روزها چیست؟ قطعه/مواد اولیه‌ای که وارد می‌کنید یا سخت می‌گیرید؟',
  'گلوگاه، درِ ورود همکاری است: جایی که می‌توان تأمین یا ساخت مشترک پیشنهاد داد.', true),
 ('coop',     5, 'همکاری',
  'چه نوع همکاری برایتان جذاب‌تر است: تأمین قطعه، نمایندگی، پروژه مشترک، یا انتقال دانش فنی؟',
  'بدون این پاسخ، پیگیری بعدی حدس است؛ با این پاسخ، پیشنهاد مشخص می‌شود.', true),
 ('next',     6, 'پیگیری',
  'شخص رابط برای پیگیری بعد از نمایشگاه چه کسی است و بهترین راه تماس چیست؟',
  'تماس‌های فهرست «حدسی» هستند؛ نام و شمارهٔ گفته‌شده در غرفه، مسیر واقعی است.', true),
 ('evidence', 7, 'شاهد',
  'می‌توانم کاتالوگ، دیتاشیت یا لینک صفحهٔ فنی بگیرم؟',
  'شاهد مکتوب، حرف شفاهی را از «reported» به «قابل بررسی» می‌برد.', false),
 ('reference',8, 'شاهد',
  'یک پروژه یا مشتری شاخص سال گذشته که اجازهٔ نام‌بردنش را دارید؟',
  'مرجع، اعتبار ادعا را می‌سنجد؛ اگر اجازه ندادند، همان «اجازه نداد» ثبت می‌شود.', false)
ON CONFLICT (code) DO NOTHING;

COMMENT ON TABLE iee1405.iv_bank IS
'بانک سؤال مصاحبهٔ غرفه؛ متن‌ها با UPDATE قابل تغییرند و در استقرار بازنویسی نمی‌شوند';

-- ── ۲) ثبت مصاحبه ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS iee1405.interviews (
    id               bigserial PRIMARY KEY,
    company_ref      bigint,                 -- شناسهٔ آینه؛ **بدون** کلید خارجی (عمدی)
    company_name     text NOT NULL,          -- عکس نام در لحظهٔ ثبت
    chat_id          bigint,
    actor            text,
    interviewee_name text,
    interviewee_role text,
    answers          jsonb NOT NULL DEFAULT '[]'::jsonb,  -- [{code,q,a,at}]
    cooperation      text,                   -- جمع‌بندی علاقهٔ همکاری
    next_step        text,
    state            text NOT NULL DEFAULT 'partial'
                     CHECK (state IN ('partial','done')),
    started_at       timestamptz NOT NULL DEFAULT now(),
    finished_at      timestamptz
);

CREATE INDEX IF NOT EXISTS interviews_company_idx ON iee1405.interviews (company_ref);
CREATE INDEX IF NOT EXISTS interviews_day_idx     ON iee1405.interviews (started_at DESC);

-- ── ۲.۱) سؤال اختصاصی هر شرکت (اختیاری، از هوش مصنوعی یا خودِ مالک) ──
-- چرا جدول جدا؟ بانک سؤال عمومی برای همه یکی است؛ ولی «این شرکت» معمولاً یک یا
-- دو سؤال اختصاصی دارد (ظرفیت مشخص، پروژهٔ خاص، رقیب). این‌ها اینجا می‌نشینند تا
-- نه بانک عمومی شلوغ شود و نه کسی مجبور شود کد را عوض کند.
-- هیچ سؤالی خودکار ساخته نمی‌شود: چیزی که اینجا نیست، پرسیده نمی‌شود.
CREATE TABLE IF NOT EXISTS iee1405.iv_company_q (
    id          bigserial PRIMARY KEY,
    company_ref bigint NOT NULL,               -- شناسهٔ آینه، بدون کلید خارجی (عمدی)
    question    text   NOT NULL,
    source      text   NOT NULL DEFAULT 'ai'   -- ai | owner | site
                CHECK (source IN ('ai','owner','site')),
    active      boolean NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS iv_company_q_uq
    ON iee1405.iv_company_q (company_ref, question);
CREATE INDEX IF NOT EXISTS iv_company_q_live_idx
    ON iee1405.iv_company_q (company_ref) WHERE active;

COMMENT ON TABLE iee1405.iv_company_q IS
'سؤال‌های اختصاصی هر شرکت؛ در انتهای سؤال‌های بانک و با کد custom پرسیده می‌شوند';

-- شرکت‌هایی که با /new در ربات ثبت می‌شوند شناسهٔ آینه ندارند؛ با کد
-- ORG-… شناخته می‌شوند. ستون جدا (نه پرکردن company_ref با عدد ساختگی) تا
-- هیچ‌وقت مصاحبهٔ یک شرکت به شرکت دیگری نسبت داده نشود.
ALTER TABLE iee1405.interviews ADD COLUMN IF NOT EXISTS org_code text;

CREATE INDEX IF NOT EXISTS interviews_org_idx
    ON iee1405.interviews (org_code) WHERE org_code IS NOT NULL;

COMMENT ON COLUMN iee1405.interviews.org_code IS
'کد شرکت در CRM (ORG-…) برای شرکت‌هایی که در آینهٔ نمایشگاه نیستند؛ بدون کلید خارجی';

COMMENT ON TABLE iee1405.interviews IS
'مصاحبه‌های غرفه؛ سطح داده «reported» است و به CRM چیزی اضافه نمی‌کند';

COMMENT ON COLUMN iee1405.interviews.company_ref IS
'شناسهٔ شرکت در آینهٔ barghpa — بدون کلید خارجی تا DROP SCHEMA barghpa مصاحبه را نشکند';

-- ── ۳) سؤال‌های همین شرکت (با زمینهٔ همان شرکت) ──────────────────────
-- خروجی: فهرست مرتب سؤال‌ها؛ اگر داده‌ای دربارهٔ شرکت در آینه باشد، در انتهای
-- سؤال مربوطه یک جملهٔ زمینه اضافه می‌شود. هیچ جمله‌ای از خودمان ساخته نمی‌شود
-- مگر از فیلدهای موجود آینه.
SELECT iee1405.drop_stale_result('iee1405', 'iv_questions',
       'TABLE(ord integer, code text, q text)');
CREATE OR REPLACE FUNCTION iee1405.iv_questions(p_company bigint)
RETURNS TABLE (ord int, code text, q text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_act     text;
    v_halls   text;
    v_flags   text;
    v_pilot   int;
    v_check   text;
    v_ask_all boolean := COALESCE((SELECT value FROM iee1405.bot_state
                                    WHERE key = 'iv_ask_all'), 'false') = 'true';
BEGIN
    IF to_regclass('barghpa.company') IS NOT NULL THEN
        SELECT c.activity,
               (SELECT string_agg(DISTINCT p.hall, '، ') FROM barghpa.participation p
                 WHERE p.company_id = c.id),
               (SELECT string_agg(f.flag, ',') FROM barghpa.company_flag f
                 WHERE f.company_id = c.id)
          INTO v_act, v_halls, v_flags
          FROM barghpa.company c WHERE c.id = p_company;
        SELECT pi.rank, pi.first_check INTO v_pilot, v_check
          FROM barghpa.pilot pi WHERE pi.company_id = p_company;
    END IF;

    RETURN QUERY
    SELECT b.ord, b.code,
           b.text_fa ||
           CASE b.code
             WHEN 'activity' THEN
                 CASE WHEN v_act IS NOT NULL AND btrim(v_act) <> ''
                      THEN E'\n   (در فهرست: «' || v_act || '» — درست است؟)'
                      ELSE E'\n   (حوزهٔ فعالیت در فهرست خالی است؛ همین را ثبت می‌کنیم)' END
             WHEN 'capacity' THEN
                 CASE WHEN v_flags LIKE '%tavanir_vendor%'
                      THEN E'\n   (در وندور لیست توانیر هستید — کدام گروه کالا؟)'
                      WHEN v_halls IS NOT NULL
                      THEN E'\n   (غرفهٔ شما در سالن ' || v_halls || ' است)'
                      ELSE '' END
             WHEN 'gap' THEN
                 CASE WHEN v_flags LIKE '%daneshbonyan%'
                      THEN E'\n   (دانش‌بنیان — کدام بخش را خودتان تولید می‌کنید و کدام را وارد؟)'
                      ELSE '' END
             WHEN 'next' THEN
                 CASE WHEN v_pilot IS NOT NULL AND v_check IS NOT NULL
                      THEN E'\n   (در فهرست پایلوت: باید تأیید شود «' || v_check || '»)'
                      ELSE '' END
             ELSE '' END
      FROM iee1405.iv_bank b
     WHERE b.ask_default OR v_ask_all
     ORDER BY b.ord;

    -- سؤال‌های اختصاصی همین شرکت، بعد از بانک عمومی (کد یکسان: custom)
    RETURN QUERY
    SELECT (100 + x.rn)::int, 'custom'::text, x.question
      FROM (SELECT q.id, q.question,
                   row_number() OVER (ORDER BY q.id) AS rn
              FROM iee1405.iv_company_q q
             WHERE q.company_ref = p_company AND q.active) x;
END $$;

-- ── ۳.۱) سؤال‌های یک شرکت CRM (که در آینهٔ نمایشگاه نیست) ───────────
-- همان بانک، با زمینه‌ای که در CRM هست: حوزهٔ فعالیت (claim) و سالن/غرفه.
SELECT iee1405.drop_stale_result('iee1405', 'iv_questions_org',
       'TABLE(ord integer, code text, q text)');
CREATE OR REPLACE FUNCTION iee1405.iv_questions_org(p_org text)
RETURNS TABLE (ord int, code text, q text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_act     text;
    v_place   text;
    v_ask_all boolean := COALESCE((SELECT value FROM iee1405.bot_state
                                    WHERE key = 'iv_ask_all'), 'false') = 'true';
    v_id      uuid;
BEGIN
    SELECT o.id INTO v_id FROM crm.organizations o
     WHERE upper(o.code) = upper(btrim(COALESCE(p_org, ''))) AND o.deleted_at IS NULL;

    IF v_id IS NOT NULL THEN
        SELECT cl.value_text INTO v_act
          FROM crm.claims cl
         WHERE cl.subject_type = 'organization' AND cl.subject_id = v_id
           AND cl.is_current AND cl.attribute = 'capability.summary';

        SELECT NULLIF(btrim(COALESCE(p.hall, '') ||
                            CASE WHEN p.booth_number IS NOT NULL
                                 THEN '-' || p.booth_number ELSE '' END), '')
          INTO v_place
          FROM iee1405.participations p
          JOIN iee1405.exhibitions ex ON ex.id = p.exhibition_id
         WHERE p.organization_id = v_id AND ex.code = 'IEE1405'
         LIMIT 1;
    END IF;

    RETURN QUERY
    SELECT b.ord, b.code,
           b.text_fa ||
           CASE b.code
             WHEN 'activity' THEN
                 CASE WHEN v_act IS NOT NULL AND btrim(v_act) <> ''
                      THEN E'\n   (در پرونده: «' || v_act || '» — درست است؟)'
                      ELSE E'\n   (این شرکت در فهرست نمایشگاه نبود؛ حوزهٔ فعالیت را خودتان می‌گویید)'
                 END
             WHEN 'capacity' THEN
                 CASE WHEN v_place IS NOT NULL
                      THEN E'\n   (غرفهٔ ثبت‌شدهٔ شما: ' || v_place || ')'
                      ELSE '' END
             ELSE '' END
      FROM iee1405.iv_bank b
     WHERE b.ask_default OR v_ask_all
     ORDER BY b.ord;
END $$;

COMMENT ON FUNCTION iee1405.iv_questions_org(text) IS
'سؤال‌های مصاحبه برای شرکتی که در CRM ثبت شده (بدون شناسهٔ آینه)';

COMMENT ON FUNCTION iee1405.iv_questions(bigint) IS
'سؤال‌های مصاحبه برای یک شرکت، با جملهٔ زمینه از دادهٔ همان شرکت در آینه';

-- ── ۴) ناوبری سؤال ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION iee1405.iv_nav_markup(p_last boolean)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT jsonb_build_object('inline_keyboard', jsonb_build_array(
        CASE WHEN p_last
             THEN jsonb_build_array(
                    jsonb_build_object('text', '✅ پایان و ثبت', 'callback_data', 'x:e'))
             ELSE jsonb_build_array(
                    jsonb_build_object('text', '⏭ رد کردن', 'callback_data', 'x:s'),
                    jsonb_build_object('text', '✖ پایان زودهنگام', 'callback_data', 'x:e'))
        END))::text
$$;

-- ── ۵) گام بعدی گفت‌وگو ──────────────────────────────────────────────
-- یک تابع، کل جریان: شروع با دکمهٔ «🎤 مصاحبه» → نام → سمت → سؤال‌ها → ثبت.
-- خروجی: متن پاسخ، دکمه‌ها، وضعیت تازهٔ نشست، و بارِ نشست.
-- چرا در یک تابع؟ چون bot_dispatch از قبل بلند است و آزمودن یک تابع خالص
-- («ورودی بده، خروجی بگیر») بسیار ساده‌تر از آزمودن هفت حالت درون آن است.
SELECT iee1405.drop_stale_result('iee1405', 'iv_step',
       'TABLE(reply text, markup text, state text, payload jsonb)');
CREATE OR REPLACE FUNCTION iee1405.iv_step(
    p_chat bigint, p_actor text, p_text text, p_state text, p_payload jsonb)
RETURNS TABLE (reply text, markup text, state text, payload jsonb)
LANGUAGE plpgsql AS $$
DECLARE
    v_text    text := btrim(COALESCE(p_text, ''));
    v_state   text := COALESCE(p_state, 'idle');
    v_p       jsonb := COALESCE(p_payload, '{}'::jsonb);
    v_co      bigint;
    v_name    text;
    v_qs      jsonb;
    v_idx     int;
    v_item    jsonb;
    v_answers jsonb;
    v_reply   text;
    v_markup  text;
    v_iv_id   bigint;
    v_parts   text;
    v_org     text;      -- کد CRM، اگر مصاحبه برای شرکت ثبت‌شده در ربات باشد
BEGIN
    -- ── گام ۱: شروع با دکمهٔ کارت ──
    --   i:<id>        شرکت آینهٔ نمایشگاه
    --   i:ORG-000123  شرکت ثبت‌شده در ربات (CRM) — گزارش مالک: «با فراخوانی
    --                 شرکت‌های جدید، کلید مصاحبه ظاهر نمی‌شود».
    IF v_text ~ '^i:(ORG-[0-9]+|[0-9]+)$' THEN
        IF upper(substring(v_text FROM 3)) LIKE 'ORG-%' THEN
            v_org := upper(substring(v_text FROM 3));
            SELECT COALESCE(NULLIF(btrim(o.display_name), ''), o.legal_name)
              INTO v_name
              FROM crm.organizations o
             WHERE upper(o.code) = v_org AND o.deleted_at IS NULL;
            IF v_name IS NULL THEN
                RETURN QUERY SELECT 'شرکتی با کد ' || v_org || ' در ربات ثبت نشده. /list',
                                    NULL::text, 'idle'::text, '{}'::jsonb;
                RETURN;
            END IF;
            RETURN QUERY SELECT
                '🎤 مصاحبه با «' || v_name || '»' || E'\n' ||
                'چند سؤال کوتاه (۲–۳ دقیقه). هر جا خواستید «✖ پایان» را بزنید؛' ||
                ' نیمه‌کاره هم ثبت می‌شود.' || E'\n\n' ||
                '۱) نام مصاحبه‌شونده؟',
                iee1405.iv_nav_markup(false),
                'iv_name'::text,
                jsonb_build_object('org', v_org, 'company_name', v_name);
            RETURN;
        END IF;

        v_co := substring(v_text FROM 3)::bigint;
        SELECT c.name_fa INTO v_name FROM barghpa.company c WHERE c.id = v_co;
        IF v_name IS NULL THEN
            RETURN QUERY SELECT 'شرکت با این شناسه در آینه نیست. فهرست: /list',
                                NULL::text, 'idle'::text, '{}'::jsonb;
            RETURN;
        END IF;
        RETURN QUERY SELECT
            '🎤 مصاحبه با «' || v_name || '»' || E'\n' ||
            'چند سؤال کوتاه (۲–۳ دقیقه). هر جا خواستید «✖ پایان» را بزنید؛' ||
            ' نیمه‌کاره هم ثبت می‌شود.' || E'\n\n' ||
            '۱) نام مصاحبه‌شونده؟',
            iee1405.iv_nav_markup(false),
            'iv_name'::text,
            jsonb_build_object('company', v_co, 'company_name', v_name);
        RETURN;
    END IF;

    -- ── گام ۲: نام مصاحبه‌شونده ──
    IF v_state = 'iv_name' THEN
        IF v_text = 'x:e' OR v_text = '' THEN
            RETURN QUERY SELECT 'مصاحبه لغو شد؛ چیزی ثبت نشد.', NULL::text,
                                'idle'::text, '{}'::jsonb;
            RETURN;
        END IF;
        RETURN QUERY SELECT
            '۲) سمت ایشان در شرکت؟' || E'\n' ||
            '   (مثال: مدیر فروش، کارشناس فنی، مدیرعامل)',
            iee1405.iv_nav_markup(false),
            'iv_role'::text,
            v_p || jsonb_build_object('interviewee_name', v_text);
        RETURN;
    END IF;

    -- ── گام ۳: سمت → فهرست سؤال‌ها در نشست ذخیره می‌شود ──
    IF v_state = 'iv_role' THEN
        IF v_text = 'x:e' OR v_text = '' THEN
            RETURN QUERY SELECT 'مصاحبه لغو شد؛ چیزی ثبت نشد.', NULL::text,
                                'idle'::text, '{}'::jsonb;
            RETURN;
        END IF;
        IF v_p ? 'org' THEN
            SELECT jsonb_agg(jsonb_build_object('code', q.code, 'q', q.q) ORDER BY q.ord)
              INTO v_qs
              FROM iee1405.iv_questions_org(v_p ->> 'org') q;
        ELSE
            SELECT jsonb_agg(jsonb_build_object('code', q.code, 'q', q.q) ORDER BY q.ord)
              INTO v_qs
              FROM iee1405.iv_questions((v_p ->> 'company')::bigint) q;
        END IF;

        v_p := v_p || jsonb_build_object('interviewee_role', v_text,
                                          'qs', COALESCE(v_qs, '[]'::jsonb),
                                          'idx', 0, 'answers', '[]'::jsonb);

        IF v_qs IS NULL OR jsonb_array_length(v_qs) = 0 THEN
            RETURN QUERY SELECT 'بانک سؤال خالی است. روی سرور: bash 03_ops/deploy_sql.sh',
                                NULL::text, 'idle'::text, '{}'::jsonb;
            RETURN;
        END IF;

        v_item := v_qs -> 0;
        RETURN QUERY SELECT
            'سؤال ۱ از ' || iee1405.fa_out(jsonb_array_length(v_qs)::text) ||
            E'\n\n' || (v_item ->> 'q'),
            iee1405.iv_nav_markup(false),
            'iv_q'::text, v_p;
        RETURN;
    END IF;

    -- ── گام ۴: پاسخ‌ها ──
    IF v_state = 'iv_q' THEN
        v_qs      := COALESCE(v_p -> 'qs', '[]'::jsonb);
        v_idx     := COALESCE((v_p ->> 'idx')::int, 0);
        v_answers := COALESCE(v_p -> 'answers', '[]'::jsonb);
        v_item    := v_qs -> v_idx;

        IF v_text = 'x:e' THEN
            -- پایان زودهنگام: هر چه هست ثبت می‌شود، نه دور ریخته
            v_org := v_p ->> 'org';
            IF v_org IS NULL THEN
                SELECT c.id INTO v_co FROM barghpa.company c
                 WHERE c.id = (v_p ->> 'company')::bigint;
            END IF;
            INSERT INTO iee1405.interviews
                (company_ref, org_code, company_name, chat_id, actor,
                 interviewee_name, interviewee_role, answers, state, finished_at)
            VALUES (v_co, v_org, COALESCE(v_p ->> 'company_name', '—'), p_chat, p_actor,
                    v_p ->> 'interviewee_name', v_p ->> 'interviewee_role',
                    v_answers, 'partial', clock_timestamp())
            RETURNING id INTO v_iv_id;

            RETURN QUERY SELECT
                '✅ ثبت شد — مصاحبهٔ #' || v_iv_id || ' (نیمه‌کاره، ' ||
                iee1405.fa_out(jsonb_array_length(v_answers)::text) || ' پاسخ)' || E'\n' ||
                'بعداً در کارت شرکت دیده می‌شود. ادامه: دوباره «🎤 مصاحبه».',
                iee1405.iv_back_markup(v_org, (v_p ->> 'company')::bigint),
                'idle'::text, '{}'::jsonb;
            RETURN;
        END IF;

        IF v_text <> 'x:s' AND v_text <> '' THEN
            v_answers := v_answers || jsonb_build_array(jsonb_build_object(
                'code', v_item ->> 'code',
                'q',    v_item ->> 'q',
                'a',    v_text,
                'at',   to_char(clock_timestamp() AT TIME ZONE 'Asia/Tehran',
                                'YYYY-MM-DD HH24:MI')));
        END IF;

        v_idx := v_idx + 1;
        v_p   := v_p || jsonb_build_object('idx', v_idx, 'answers', v_answers);

        IF v_idx < jsonb_array_length(v_qs) THEN
            v_item := v_qs -> v_idx;
            v_reply := 'سؤال ' || iee1405.fa_out((v_idx + 1)::text) || ' از ' ||
                       iee1405.fa_out(jsonb_array_length(v_qs)::text) || E'\n\n' ||
                       (v_item ->> 'q');
            v_markup := iee1405.iv_nav_markup(v_idx = jsonb_array_length(v_qs) - 1);
            RETURN QUERY SELECT v_reply, v_markup, 'iv_q'::text, v_p;
            RETURN;
        END IF;

        -- آخرین سؤال: ثبت کامل
        v_org := v_p ->> 'org';
        IF v_org IS NULL THEN
            SELECT c.id INTO v_co FROM barghpa.company c
             WHERE c.id = (v_p ->> 'company')::bigint;
        END IF;

        -- جمع‌بندی همکاری از پاسخ‌های «coop» و «next» (اگر داده شده باشند)
        SELECT string_agg(x ->> 'a', E' · ') INTO v_parts
          FROM jsonb_array_elements(v_answers) x
         WHERE x ->> 'code' = 'coop';

        INSERT INTO iee1405.interviews
            (company_ref, org_code, company_name, chat_id, actor,
             interviewee_name, interviewee_role, answers, cooperation, state, finished_at)
        VALUES (v_co, v_org, COALESCE(v_p ->> 'company_name', '—'), p_chat, p_actor,
                v_p ->> 'interviewee_name', v_p ->> 'interviewee_role',
                v_answers, v_parts, 'done', clock_timestamp())
        RETURNING id INTO v_iv_id;

        RETURN QUERY SELECT
            '✅ مصاحبهٔ #' || v_iv_id || ' ثبت شد' || E'\n' ||
            'شرکت: ' || COALESCE(v_p ->> 'company_name', '—') || E'\n' ||
            'مصاحبه‌شونده: ' || COALESCE(v_p ->> 'interviewee_name', '—') ||
            ' — ' || COALESCE(v_p ->> 'interviewee_role', '—') || E'\n' ||
            'پاسخ‌ها: ' || iee1405.fa_out(jsonb_array_length(v_answers)::text) || ' از ' ||
            iee1405.fa_out(jsonb_array_length(v_qs)::text) || E'\n' ||
            'سطح داده: reported (گفتهٔ غرفه، نه تأییدشده)',
            iee1405.iv_back_markup(v_org, (v_p ->> 'company')::bigint),
            'idle'::text, '{}'::jsonb;
        RETURN;
    END IF;

    -- حالت نامعلوم: به حالت عادی برگرد
    RETURN QUERY SELECT NULL::text, NULL::text, 'idle'::text, '{}'::jsonb;
END $$;

COMMENT ON FUNCTION iee1405.iv_step IS
'جریان کامل مصاحبهٔ غرفه: شروع → نام → سمت → سؤال‌ها → ثبت (با امکان پایان زودهنگام)';

-- ── ۶) خلاصهٔ مصاحبه‌های یک شرکت (برای کارت) ─────────────────────────
CREATE OR REPLACE FUNCTION iee1405.iv_summary(p_company bigint)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN count(*) = 0 THEN NULL
                ELSE '🎤 مصاحبه‌ها: ' || count(*) || ' مورد · آخرین: ' ||
                     COALESCE(max(interviewee_name), '—') ||
                     CASE WHEN max(state) = 'done' THEN '' ELSE ' (نیمه‌کاره)' END
           END
      FROM iee1405.interviews
     WHERE company_ref = p_company
$$;

-- ── ۶.۱) دکمهٔ بازگشت پس از مصاحبه (آینه یا CRM) ────────────────────
CREATE OR REPLACE FUNCTION iee1405.iv_back_markup(p_org text, p_company bigint)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE v_m text;
BEGIN
    IF p_org IS NOT NULL
       AND to_regprocedure('iee1405.co_org_card(text)') IS NOT NULL THEN
        SELECT c.markup INTO v_m FROM iee1405.co_org_card(p_org) c;
        IF v_m IS NOT NULL THEN RETURN v_m; END IF;
    END IF;
    IF p_company IS NOT NULL THEN
        RETURN iee1405.co_keyboard(ARRAY[p_company], 1, 1, false);
    END IF;
    RETURN jsonb_build_object('inline_keyboard', jsonb_build_array(
        jsonb_build_array(jsonb_build_object('text', '↩ بازگشت به فهرست',
                                             'callback_data', 'l:1'))))::text;
END $$;

COMMENT ON FUNCTION iee1405.iv_back_markup(text, bigint) IS
'دکمه‌های بازگشت پس از مصاحبه: کارت شرکت CRM یا فهرست';

-- ── ۶.۲) خلاصهٔ مصاحبه‌های یک شرکت CRM ───────────────────────────────
CREATE OR REPLACE FUNCTION iee1405.iv_summary_org(p_org text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN count(*) = 0 THEN NULL
                ELSE '🎤 مصاحبه‌ها: ' || iee1405.fa_out(count(*)::text) ||
                     ' مورد · آخرین: ' || COALESCE(max(interviewee_name), '—') ||
                     CASE WHEN max(state) = 'done' THEN '' ELSE ' (نیمه‌کاره)' END
           END
      FROM iee1405.interviews
     WHERE upper(COALESCE(org_code, '')) = upper(COALESCE(p_org, ''))
$$;

COMMENT ON FUNCTION iee1405.iv_summary_org(text) IS
'خلاصهٔ مصاحبه‌های یک شرکت ثبت‌شده در ربات (کلید: ORG-code)';

-- ── ۷) گرنت نقش ربات ─────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iee_app') THEN
        EXECUTE 'GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA iee1405 TO iee_app';
        EXECUTE 'GRANT SELECT, INSERT ON iee1405.interviews TO iee_app';
        EXECUTE 'GRANT SELECT ON iee1405.iv_bank TO iee_app';
        EXECUTE 'GRANT SELECT, INSERT ON iee1405.iv_company_q TO iee_app';
        EXECUTE 'GRANT USAGE, SELECT ON SEQUENCE iee1405.iv_company_q_id_seq TO iee_app';
        EXECUTE 'GRANT USAGE, SELECT ON SEQUENCE iee1405.interviews_id_seq TO iee_app';
    END IF;
END $$;

-- ── ۸) خودآزمایی ─────────────────────────────────────────────────────
DO $$
DECLARE
    s record;
    n int;
    n_total int;
    q1 text;
BEGIN
    SELECT count(*) INTO n FROM iee1405.iv_bank WHERE ask_default;
    SELECT count(*) INTO n_total FROM iee1405.iv_bank;
    IF n < 5 THEN
        RAISE EXCEPTION 'بانک سؤال ناقص است (% سؤال پیش‌فرض)', n;
    END IF;

    IF to_regclass('barghpa.company') IS NOT NULL
       AND EXISTS (SELECT 1 FROM barghpa.company) THEN
        SELECT count(*) INTO n FROM iee1405.iv_questions((SELECT min(id) FROM barghpa.company));
        IF n < 5 THEN
            RAISE EXCEPTION 'سؤال‌های شرکت ساخته نشد (% ردیف)', n;
        END IF;
        -- سؤال اختصاصی باید در انتهای فهرست همین شرکت ظاهر شود
        INSERT INTO iee1405.iv_company_q (company_ref, question, source)
        VALUES ((SELECT min(id) FROM barghpa.company), 'آزمون: ظرفیت ماهانهٔ تابلوی MV؟', 'owner')
        ON CONFLICT DO NOTHING;
        SELECT q INTO q1 FROM iee1405.iv_questions((SELECT min(id) FROM barghpa.company))
         WHERE code = 'custom' LIMIT 1;
        IF q1 IS NULL THEN
            RAISE EXCEPTION 'سؤال اختصاصی شرکت در فهرست نیامد';
        END IF;
        DELETE FROM iee1405.iv_company_q
         WHERE question = 'آزمون: ظرفیت ماهانهٔ تابلوی MV؟' AND source = 'owner';

        SELECT q INTO q1 FROM iee1405.iv_questions((SELECT min(id) FROM barghpa.company)) LIMIT 1;
        IF q1 IS NULL OR q1 NOT LIKE '%حوزه%' THEN
            RAISE EXCEPTION 'اولین سؤال باید تأیید حوزهٔ فعالیت باشد، شد: %', q1;
        END IF;
    END IF;

    -- جریان: شروع → نام → سمت → یک سؤال (فقط اگر آینه داده داشته باشد،
    -- وگرنه «شرکت با این شناسه نیست» پاسخ درست است و آزمون نباید بشکند)
    IF to_regclass('barghpa.company') IS NOT NULL
       AND EXISTS (SELECT 1 FROM barghpa.company) THEN
        SELECT * INTO s FROM iee1405.iv_step(0, 'selftest', 'i:' ||
                 (SELECT min(id)::text FROM barghpa.company), 'idle', '{}'::jsonb);
        IF s.state <> 'iv_name' THEN
            RAISE EXCEPTION 'شروع مصاحبه وضعیت درست نداد: %', s.state;
        END IF;
        SELECT * INTO s FROM iee1405.iv_step(0, 'selftest', 'علی رضایی',
                 'iv_name', '{"company": 1, "company_name": "آزمون"}'::jsonb);
        IF s.state <> 'iv_role' THEN
            RAISE EXCEPTION 'گام نام مصاحبه‌شونده وضعیت درست نداد: %', s.state;
        END IF;
        RAISE NOTICE '✅ بانک سؤال (% سؤال، % پیش‌فرض) و جریان مصاحبه سالم است', n_total, n;
    ELSE
        RAISE NOTICE '✅ بانک سؤال ساخته شد (% سؤال، % پیش‌فرض) — آزمون جریان پس از بارگذاری آینه اجرا می‌شود', n_total, n;
    END IF;
END $$;
