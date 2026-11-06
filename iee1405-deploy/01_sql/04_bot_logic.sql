-- ═══════════════════════════════════════════════════════════════════════
-- IEE 1405 — منطق ربات میدانی (Bot Logic)
-- پروژه: PRJ-IEE-015
--
-- طراحی: تمام منطق گفت‌وگو، اعتبارسنجی، مجوز و نوشتن داده در PostgreSQL است
--        تا (۱) در یک جا و قابل تست باشد، (۲) n8n فقط «لوله» باشد،
--        (۳) Field API و پنل بعداً همین توابع را صدا بزنند.
--
-- تابع اصلی: iee1405.bot_dispatch(update_id, chat_id, text, raw)
-- idempotent: IF NOT EXISTS / ON CONFLICT / CREATE OR REPLACE
-- اجرا: psql -v ON_ERROR_STOP=1 -f 04_bot_logic.sql
-- ═══════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────
-- 1) جدول متن پیام‌ها (تغییر متن = UPDATE، بدون استقرار مجدد کد)
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS iee1405.bot_messages (
    key         text PRIMARY KEY,
    template    text NOT NULL,
    description text,
    updated_at  timestamptz NOT NULL DEFAULT now()
);

INSERT INTO iee1405.bot_messages (key, template, description) VALUES
 ('help',
  E'راهنمای ربات میدانی Xennic\n\n'
  '/new — ثبت شرکت جدید\n'
  '/find نام — جست‌وجو در CRM\n'
  '/c نام|شناسه|سالن — شرکت از فهرست نمایشگاه\n'
  '/org ORG-000123 — پرونده شرکت\n'
  '/log ORG-000123 | خلاصه | اقدام بعدی — ثبت مذاکره\n'
  '/cap ORG-000123 | متن توانمندی — ثبت توانمندی (reported)\n'
  '/visit ORG-000123 [نتیجه] — ثبت بازدید\n'
  '/task ORG-000123 | عنوان | روز — پیگیری\n'
  '/today — خلاصه امروز\n'
  '/cancel — لغو جریان جاری\n\n'
  'میان‌بر: ن / ج / م / پ / و',
  'متن راهنما'),
 ('unauthorized',
  E'این حساب مجاز نیست.\nشناسه گفت‌وگوی شما: {chat_id}\nاین شناسه را به مدیر سامانه بدهید تا دسترسی فعال شود.',
  'کاربر ناشناس'),
 ('new_ask_name',
  E'ثبت شرکت جدید.\nنام شرکت یا برند را بنویسید:',
  'گام ۱ /new'),
 ('new_ask_category',
  E'✅ ثبت شد: {code}\nنام: {name}\n\nدسته محصول را با شماره انتخاب کنید:\n{category_list}',
  'گام ۲ /new'),
 ('new_ask_booth',
  E'دسته: {category}\n\nسالن و شماره غرفه؟ (مثال: 38-12)\nاگر غرفه ندارد، بنویسید: ندارد',
  'گام ۳ /new'),
 ('new_done',
  E'✅ پرونده حداقلی کامل شد\n{code} — {name}\nدسته: {category}\nغرفه: {booth}\n\n[ثبت مذاکره: /log {code} | خلاصه | اقدام]',
  'پایان /new'),
 ('name_duplicate',
  E'⚠️ شرکت مشابه از قبل ثبت شده است: {code} — {name}\n'
  'برای جلوگیری از تکرار، همان پرونده استفاده می‌شود.\n'
  'ادامه ثبت دسته/غرفه با همین پرونده؟ برای ادامه شماره دسته را بفرستید، یا /cancel.',
  'تشخیص تکرار نام'),
 ('cat_invalid',
  E'شماره دسته معتبر نیست. یکی از شماره‌های زیر را بفرستید:\n{category_list}',
  'دسته نامعتبر'),
 ('find_none',
  E'چیزی پیدا نشد.\nبا بخش کوتاه‌تری از نام جست‌وجو کنید، یا /new برای ثبت جدید.',
  'نتیجه خالی جست‌وجو'),
 ('find_header',
  E'نتایج جست‌وجو («{q}»):\n{list}\n\nشماره را بفرستید تا پرونده باز شود.',
  'فهرست نتایج'),
 ('org_card',
  E'🏢 {code} — {name}\n'
  'نوع: {org_type} · گروه: {group} · امتیاز: {score}\n'
  '📍 غرفه: {booth}\n'
  '👤 مخاطب: {contacts}\n'
  '🧾 توانمندی: {capability}\n'
  '💬 آخرین تعامل: {last_interaction}\n'
  '✅ پیگیری باز: {open_tasks}\n\n'
  '[مذاکره: /log {code} | خلاصه] [پیگیری: /task {code} | عنوان | 3]',
  'کارت پرونده شرکت'),
 ('org_notfound',
  E'شرکتی با کد {code} پیدا نشد.',
  'کد شرکت نامعتبر'),
 ('log_usage',
  E'قالب درست:\n/log ORG-000123 | خلاصه مذاکره | اقدام بعدی\n'
  'بخش سوم اختیاری است؛ اگر نیامد، وظیفه‌ای ساخته نمی‌شود.',
  'راهنمای /log'),
 ('log_done',
  E'✅ مذاکره ثبت شد: {code}\nشرکت: {name}\nخلاصه: {summary}\n{vars}',
  'ثبت مذاکره'),
 ('cap_done',
  E'✅ توانمندی ثبت شد (سطح: reported — اعلامی)\n{code} — {name}\nمتن: {value}\n'
  'برای ارتقا به «verified»، منبع (کاتالوگ/گواهی) لازم است.',
  'ثبت ادعای توانمندی'),
 ('visit_done',
  E'✅ بازدید ثبت شد: {code} — {name}\nنتیجه: {outcome}',
  'ثبت بازدید'),
 ('task_done',
  E'✅ پیگیری ثبت شد: {code}\n{title}\nسررسید: {due} ({days} روز)',
  'ثبت وظیفه'),
 ('today',
  E'📊 خلاصه امروز\n'
  'شرکت جدید: {orgs_today}\n'
  'مذاکره: {interactions_today}\n'
  'پیگیری جدید: {tasks_today}\n'
  'فایل: {files_today}\n'
  'مجموع شرکت‌ها: {orgs_total}',
  'خلاصه روز'),
 ('unknown',
  E'دستور شناخته نشد.\n/help برای فهرست دستورها.',
  'دستور ناشناخته'),
 ('cancelled',
  E'جریان جاری لغو شد.',
  'لغو جلسه'),
 ('idle_hint',
  E'برای شروع: /new (ثبت شرکت) یا /find نام (جست‌وجو).\nراهنما: /help',
  'راهنمای حالت عادی'),
 ('find_need_q',
  E'نام شرکت را بعد از دستور بنویسید. مثال:\n/find ترانسفو\nیا مستقیم نام را بفرستید.',
  'درخواست عبارت جست‌وجو'),
 ('cmd_unknown',
  E'دستور «{text}» را نمی‌شناسم.\nراهنما: /help\nجست‌وجوی نمایشگاه: /c نام شرکت',
  'دستور ناشناخته — متن ورودی بازگفت می‌شود تا عیب‌یابی دکمه‌ها ممکن باشد'),
 ('not_understood',
  E'متوجه نشدم: «{text}»\nنام شرکت را بفرستید، یا /c برای فهرست نمایشگاه، یا /help.',
  'متن نامفهوم — با بازگفت متن، برای تشخیص برچسب دکمه'),
 ('empty_reply',
  E'پاسخی برای این درخواست ساخته نشد (متن خالی بود، پس فرستاده نشد).\n'
  'دوباره امتحان کنید؛ اگر تکرار شد: /help',
  'جایگزین پاسخ خالی — «سکوت» خرابی است، نه رفتار')
-- قالب‌ها را دست نزن (اپراتور می‌تواند متن را بدون استقرار عوض کند)، اما
-- قالب خالی/سفید را ترمیم کن؛ وگرنه ربات بی‌صدا پاسخی خالی می‌فرستد.
ON CONFLICT (key) DO UPDATE
    SET template    = EXCLUDED.template,
        description = EXCLUDED.description,
        updated_at  = now()
    WHERE iee1405.bot_messages.template IS NULL
       OR btrim(iee1405.bot_messages.template) = '';

COMMENT ON TABLE iee1405.bot_messages IS 'متن پیام‌های ربات؛ تغییر بدون تغییر کد یا استقرار مجدد';

-- ─────────────────────────────────────────────────────────────────────
-- 2) جای‌گذاری متغیر در قالب
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION iee1405.tpl(p_template text, p_vars jsonb DEFAULT '{}'::jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_out text := COALESCE(p_template, '');
    kv    record;
BEGIN
    IF p_vars IS NULL THEN RETURN v_out; END IF;
    FOR kv IN SELECT key, value FROM jsonb_each_text(p_vars) LOOP
        v_out := replace(v_out, '{' || kv.key || '}', COALESCE(kv.value, ''));
    END LOOP;
    RETURN v_out;
END $$;

CREATE OR REPLACE FUNCTION iee1405.msg(p_key text, p_vars jsonb DEFAULT '{}'::jsonb)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE v_tpl text;
BEGIN
    SELECT template INTO v_tpl FROM iee1405.bot_messages WHERE key = p_key;
    IF v_tpl IS NULL THEN
        RETURN 'پیام «' || p_key || '» تعریف نشده است.';
    END IF;
    RETURN iee1405.tpl(v_tpl, p_vars);
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 3) توابع کمکی
-- ─────────────────────────────────────────────────────────────────────

-- فهرست شماره‌دار دسته‌های محصول
CREATE OR REPLACE FUNCTION iee1405.category_list()
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT string_agg(rn::text || ') ' || title_fa || ' (' || code || ')',
                      E'\n' ORDER BY rn)
    FROM (SELECT code, title_fa,
                 row_number() OVER (ORDER BY sort_order, code) AS rn
            FROM crm.product_categories) t
$$;

-- تبدیل ورودی کاربر (شماره یا کد) به کد دسته
CREATE OR REPLACE FUNCTION iee1405.resolve_category(p_input text)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE v text := btrim(COALESCE(p_input, '')); v_code text;
BEGIN
    IF v ~ '^[0-9]+$' THEN
        SELECT code INTO v_code FROM (
            SELECT code, row_number() OVER (ORDER BY sort_order, code) AS rn
            FROM crm.product_categories) t
        WHERE t.rn = v::int;
        RETURN v_code;
    END IF;
    SELECT code INTO v_code FROM crm.product_categories WHERE upper(code) = upper(v);
    IF v_code IS NOT NULL THEN RETURN v_code; END IF;
    -- تطبیق نسبی با نام فارسی
    SELECT code INTO v_code FROM crm.product_categories
     WHERE crm.norm_text(title_fa) ILIKE '%' || crm.norm_text(v) || '%'
     ORDER BY sort_order LIMIT 1;
    RETURN v_code;
END $$;

-- استخراج کد شرکت از متن
CREATE OR REPLACE FUNCTION iee1405.parse_org_code(p_text text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT upper((regexp_match(COALESCE(p_text, ''), '(ORG-[0-9]{6})', 'i'))[1])
$$;

-- پارس «سالن-غرفه» → (hall, number)
DROP FUNCTION IF EXISTS iee1405.parse_booth(text);

CREATE OR REPLACE FUNCTION iee1405.parse_booth(p_text text, OUT hall text, OUT number text)
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v text := btrim(COALESCE(p_text, '')); parts text[];
BEGIN
    IF v = '' OR crm.norm_text(v) IN ('ندارد', 'بدون غرفه', '-') THEN
        hall := NULL; number := NULL; RETURN;
    END IF;
    v := regexp_replace(v, '\s*[-–—/]\s*', '-', 'g');
    IF v ~ '^[^-]+-[^-]+$' THEN
        parts  := string_to_array(v, '-');
        hall   := btrim(parts[1]);
        number := btrim(parts[2]);
    ELSE
        hall := NULL; number := btrim(v);
    END IF;
END $$;

-- جست‌وجوی شرکت (کد، نام، غرفه) — حداکثر ۸ نتیجه
SELECT iee1405.drop_stale_result('iee1405', 'search_orgs',
       'TABLE(code text, legal_name text, booth text)');
CREATE OR REPLACE FUNCTION iee1405.search_orgs(p_q text, p_limit int DEFAULT 8)
RETURNS TABLE (code text, legal_name text, booth text) LANGUAGE sql STABLE AS $$
    WITH ex AS (SELECT id FROM iee1405.exhibitions WHERE code = 'IEE1405')
    SELECT o.code, o.legal_name,
           coalesce(nullif(p.hall, '') || '-', '') || coalesce(p.booth_number, '')
    FROM crm.organizations o
    LEFT JOIN iee1405.participations p
           ON p.organization_id = o.id AND p.exhibition_id = (SELECT id FROM ex)
    WHERE o.deleted_at IS NULL
      AND (
            o.code ILIKE '%' || btrim(p_q) || '%'
         OR crm.norm_text(o.legal_name) ILIKE '%' || crm.norm_text(p_q) || '%'
         OR crm.norm_text(coalesce(o.display_name, '')) ILIKE '%' || crm.norm_text(p_q) || '%'
         OR p.booth_number = btrim(p_q)
          )
    ORDER BY
      CASE WHEN o.code ILIKE btrim(p_q) THEN 0
           WHEN p.booth_number = btrim(p_q) THEN 1
           WHEN crm.norm_text(o.legal_name) ILIKE crm.norm_text(p_q) || '%' THEN 2
           ELSE 3 END,
      o.updated_at DESC
    LIMIT p_limit
$$;

-- ثبت ادعا با مدیریت «ادعای جاری» (نسخه قبلی حفظ و جایگزین می‌شود)
CREATE OR REPLACE FUNCTION iee1405.add_claim(
    p_subject_type text, p_subject_id uuid, p_attribute text,
    p_value_text text, p_status crm.epistemic_status,
    p_source_id uuid DEFAULT NULL, p_asserted_by text DEFAULT NULL,
    p_confidence smallint DEFAULT NULL, p_actor text DEFAULT 'system'
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_new uuid;
BEGIN
    -- بستن ادعای جاری قبلی
    UPDATE crm.claims SET is_current = false
     WHERE subject_type = p_subject_type AND subject_id = p_subject_id
       AND attribute = p_attribute AND is_current;

    INSERT INTO crm.claims (subject_type, subject_id, attribute, value_text,
                            epistemic_status, source_id, asserted_by, confidence, created_by)
    VALUES (p_subject_type, p_subject_id, p_attribute, p_value_text,
            p_status, p_source_id, p_asserted_by, p_confidence, p_actor)
    RETURNING id INTO v_new;

    PERFORM crm.audit(p_actor, 'claim_add', 'claim', v_new,
                      jsonb_build_object('attribute', p_attribute,
                                         'status', p_status,
                                         'value', left(p_value_text, 200)));
    RETURN v_new;
END $$;

-- کارت پرونده شرکت
CREATE OR REPLACE FUNCTION iee1405.org_card(p_org_id uuid)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE
    o        record;
    v_booth  text;
    v_cont   text;
    v_cap    text;
    v_last   text;
    v_tasks  int;
BEGIN
    SELECT * INTO o FROM crm.organizations WHERE id = p_org_id AND deleted_at IS NULL;
    IF o.id IS NULL THEN RETURN NULL; END IF;

    SELECT coalesce(nullif(p.hall, '') || '-', '') || coalesce(p.booth_number, 'ثبت‌نشده')
      INTO v_booth
      FROM iee1405.participations p
      JOIN iee1405.exhibitions ex ON ex.id = p.exhibition_id
     WHERE p.organization_id = o.id AND ex.code = 'IEE1405'
     LIMIT 1;

    SELECT string_agg(c.full_name || coalesce(' (' || c.role_title || ')', ''), ' / ')
      INTO v_cont FROM crm.contacts c
     WHERE c.organization_id = o.id AND c.deleted_at IS NULL;

    SELECT cl.value_text INTO v_cap FROM crm.claims cl
     WHERE cl.subject_type = 'organization' AND cl.subject_id = o.id
       AND cl.is_current AND cl.attribute = 'capability.summary';
    IF v_cap IS NULL THEN
        SELECT cl.value_text INTO v_cap FROM crm.claims cl
         WHERE cl.subject_type = 'organization' AND cl.subject_id = o.id
           AND cl.is_current AND cl.attribute = 'capability.category';
        IF v_cap IS NOT NULL THEN
            SELECT 'دسته ' || pc.title_fa INTO v_cap
              FROM crm.product_categories pc WHERE pc.code = v_cap;
        END IF;
    END IF;

    SELECT to_char(max(i.occurred_at) AT TIME ZONE 'Asia/Tehran', 'MM-DD HH24:MI')
      INTO v_last FROM crm.interactions i WHERE i.organization_id = o.id;

    SELECT count(*) INTO v_tasks FROM crm.tasks t
     WHERE t.organization_id = o.id AND t.status = 'open';

    RETURN iee1405.msg('org_card', jsonb_build_object(
        'code', o.code,
        'name', coalesce(o.display_name, o.legal_name),
        'org_type', o.org_type,
        'group', coalesce(o.effective_group::text, 'ارزیابی‌نشده'),
        'score', coalesce(o.score::text, '—'),
        'booth', coalesce(v_booth, 'ثبت‌نشده'),
        'contacts', coalesce(v_cont, 'ثبت‌نشده'),
        'capability', coalesce(v_cap, 'ثبت‌نشده'),
        'last_interaction', coalesce(v_last, 'ندارد'),
        'open_tasks', v_tasks::text));
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 4) مدیریت جلسه
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION iee1405.session_set(
    p_chat_id bigint, p_actor text, p_state text, p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO iee1405.bot_sessions (chat_id, actor, state, payload, updated_at, expires_at)
    VALUES (p_chat_id, p_actor, p_state, p_payload, now(), now() + interval '30 minutes')
    ON CONFLICT (chat_id) DO UPDATE
       SET actor = EXCLUDED.actor, state = EXCLUDED.state,
           payload = EXCLUDED.payload, updated_at = now(),
           expires_at = EXCLUDED.expires_at
$$;

SELECT iee1405.drop_stale_result('iee1405', 'session_get',
       'TABLE(state text, payload jsonb)');
CREATE OR REPLACE FUNCTION iee1405.session_get(p_chat_id bigint)
RETURNS TABLE (state text, payload jsonb) LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN s.expires_at < now() THEN 'idle' ELSE s.state END,
           CASE WHEN s.expires_at < now() THEN '{}'::jsonb ELSE s.payload END
    FROM iee1405.bot_sessions s WHERE s.chat_id = p_chat_id
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 5) تابع اصلی: پردازش یک آپدیت بله
--    ورودی: update_id, chat_id, text, raw update
--    خروجی: status, reply_text, org_code
--    idempotent: هر update_id فقط یک بار پردازش می‌شود
-- ─────────────────────────────────────────────────────────────────────
-- اگر امضای تابع تغییر کرده باشد، بازسازی لازم است
DROP FUNCTION IF EXISTS iee1405.bot_dispatch(bigint, bigint, text, jsonb);
DROP FUNCTION IF EXISTS iee1405.bot_dispatch(bigint, bigint, text, jsonb, bigint);

-- آیا آینهٔ فهرست نمایشگاه آماده است؟
--   چرا تابع جدا؟ چون در plpgsql نمی‌توان «EXISTS (SELECT … FROM barghpa.company)»
--   را با to_regclass کوتاه‌مدار کرد: عبارت یک‌جا پارس می‌شود و اگر اسکیما نبود،
--   خطای «relation does not exist» می‌دهد (همین باگ در آزمون دیده شد).
--   VOLATILE لازم است: EXECUTE در تابع STABLE مجاز نیست.
CREATE OR REPLACE FUNCTION iee1405.mirror_ready() RETURNS boolean
LANGUAGE plpgsql VOLATILE AS $$
DECLARE v boolean;
BEGIN
    IF to_regclass('barghpa.company') IS NULL THEN
        RETURN false;
    END IF;
    EXECUTE 'SELECT EXISTS (SELECT 1 FROM barghpa.company)' INTO v;
    RETURN COALESCE(v, false);
END $$;

COMMENT ON FUNCTION iee1405.mirror_ready() IS
'آیا اسکیمای آینهٔ barghpa ساخته و بارگذاری شده است؟ (بدون خطا وقتی نیست)';

CREATE OR REPLACE FUNCTION iee1405.bot_dispatch(
    p_update_id bigint,
    p_chat_id   bigint,
    p_text      text,
    p_raw       jsonb DEFAULT '{}'::jsonb,
    -- اگر پاسخ به یک دکمهٔ شیشه‌ای است: شناسهٔ همان پیام. خروجی در ستون
    -- edit_message_id می‌نشیند و گرهٔ ارسال به‌جای sendMessage، editMessageText
    -- می‌زند تا پیام تازه ساخته نشود.
    p_edit_message_id bigint DEFAULT NULL
) RETURNS TABLE (chat_id bigint, status text, reply_text text, org_code text)
LANGUAGE plpgsql AS $$
DECLARE
    v_text      text := btrim(COALESCE(p_text, ''));
    v_key       text;   -- نسخهٔ یکسان‌شدهٔ متن برای تشخیص دستور
    v_lbl       text;   -- همان متن، بدون ایموجی/نشانهٔ ابتدایی (برای برچسب دکمه)
    v_dedupe_s  int;    -- پنجرهٔ ضدتکرار راهنما (ثانیه)
    v_cmd       text;
    v_arg       text;
    v_actor     text;
    v_role      text;
    v_inserted  bigint;
    v_state     text := 'idle';
    v_payload   jsonb := '{}'::jsonb;
    v_org_id    uuid;
    v_org_code  text;
    v_org_name  text;
    v_cat       text;
    v_hall      text;
    v_number    text;
    v_parts     text[];
    v_summary   text;
    v_next      text;
    v_title     text;
    v_days      int;
    v_count     int;
    v_list      text;
    v_codes     jsonb;
    v_reply     text;
    v_markup    jsonb;  -- دکمه‌های شیشه‌ای همین پاسخ (اگر داشته باشد)
    v_page      int;    -- صفحهٔ فهرست شرکت‌ها
    v_pages     int;
    v_ids       bigint[]; -- شناسه‌های همین صفحه (برای انتخاب با شماره)
    v_sids      bigint[]; -- همهٔ شناسه‌های نتیجهٔ جست‌وجو (برای صفحهٔ بعد)
    v_cid       bigint;   -- شناسهٔ شرکتی که دکمه‌اش زده شده
    v_mirror    boolean;
    v_code_in   text;
    v_inter_id  uuid;
    v_task_id   uuid;
    v_visit_id  uuid;
    v_due       date;
    d           record;
BEGIN
    -- ۵.۱) Idempotency: ثبت آپدیت؛ اگر قبلاً آمده باشد، خروجی خالی
    INSERT INTO iee1405.bot_updates (update_id, chat_id, raw, command)
    VALUES (p_update_id, p_chat_id, COALESCE(p_raw, '{}'::jsonb), left(v_text, 60))
    ON CONFLICT (update_id) DO NOTHING
    RETURNING update_id INTO v_inserted;

    IF v_inserted IS NULL THEN
        RETURN QUERY SELECT p_chat_id, 'duplicate'::text, NULL::text, NULL::text;
        RETURN;
    END IF;

    -- ۵.۲) احراز هویت
    SELECT u.username, u.role INTO v_actor, v_role
      FROM crm.users u
     WHERE u.bale_chat_id = p_chat_id AND u.is_active = true;

    IF v_actor IS NULL THEN
        v_reply := iee1405.msg('unauthorized', jsonb_build_object('chat_id', p_chat_id));
        UPDATE iee1405.bot_updates
           SET status = 'skipped', reply_text = v_reply, processed_at = now()
         WHERE update_id = p_update_id;
        RETURN QUERY SELECT p_chat_id, 'unauthorized'::text, v_reply, NULL::text;
        RETURN;
    END IF;

    UPDATE crm.users SET last_seen_at = now() WHERE username = v_actor;

    -- ۵.۳) تفکیک دستور و آرگومان
    -- ⚠️ ورودی **قبل از هر تصمیمی** یکسان می‌شود. چرا؟ دکمه‌های بله متن را با
    -- نویسه‌های جهت‌دهی/نامرئی می‌فرستند (U+200E/200F، U+202A–E، U+2066–9)،
    -- گاهی با «@نام‌ربات» و گاهی با ارقام فارسی. نتیجهٔ واقعی روی سرور: هر دکمه
    -- به «برای شروع: /new …» می‌رسید چون هیچ شرطی با متن آلوده جور درنمی‌آمد.
    v_key := crm.cmd_text(v_text);

    -- برچسب دکمه‌ها معمولاً ایموجی دارند («📊 امروز»). برای تطبیق واژهٔ فارسی،
    -- نشانه‌های ابتدای متن حذف می‌شوند. عمداً روی متغیر جداگانه: اگر روی v_key
    -- انجام شود، «/c 38B» هم اسلش ابتدایش حذف می‌شد و دستور از دست می‌رفت.
    v_lbl := btrim(regexp_replace(v_key, '^[^a-zA-Z0-9آ-یءأإؤئ۰-۹]+', ''));

    -- نخستین نشانهٔ «/دستور» در متن، هرجای متن که باشد (برچسب دکمه‌ها ممکن است
    -- با ایموجی یا متن فارسی شروع شوند: «📊 امروز /today»)
    IF v_key LIKE '%/%' THEN
        v_cmd := lower(substring(v_key FROM '/[^[:space:]]+'));
        IF v_cmd IS NOT NULL THEN
            v_cmd := split_part(v_cmd, '@', 1);        -- /start@xennicnotifierbot
            v_arg := btrim(substr(v_key,
                                  strpos(v_key, substring(v_key FROM '/[^[:space:]]+')) +
                                  length(substring(v_key FROM '/[^[:space:]]+'))));
        END IF;
    END IF;

    -- میان‌برهای یک‌حرفی و واژه‌های فارسی (برچسب دکمه‌های بدون اسلش)
    IF v_cmd IS NULL THEN
        v_cmd := CASE v_lbl
                    WHEN 'ن' THEN '/new'
                    WHEN 'ج' THEN '/find'
                    WHEN 'م' THEN '/log'
                    WHEN 'پ' THEN '/task'
                    WHEN 'و' THEN '/visit'
                    WHEN 'ر' THEN '/help'
                    WHEN 'ش' THEN '/c'
                    WHEN 'س' THEN '/hall'
                    WHEN 'ف' THEN '/list'
                    WHEN 'شروع' THEN '/start'
                    WHEN 'استارت' THEN '/start'
                    WHEN 'راهنما' THEN '/help'
                    WHEN 'کمک' THEN '/help'
                    WHEN 'دستورها' THEN '/help'
                    WHEN 'جستجو' THEN '/find'
                    WHEN 'جست وجو' THEN '/search'
                    WHEN 'جستجوی شرکت' THEN '/find'
                    WHEN 'پیدا' THEN '/find'
                    WHEN 'لغو' THEN '/cancel'
                    WHEN 'انصراف' THEN '/cancel'
                    WHEN 'سالن' THEN '/hall'
                    WHEN 'شرکت' THEN '/c'
                    -- برچسب دکمه‌های منوی ثابت (iee1405.menu_keyboard)
                    -- نیم‌فاصله پیش از این‌جا به فاصله تبدیل شده
                    -- («شرکت‌ها» → «شرکت ها»)، پس هر دو شکل نوشته می‌شود.
                    WHEN 'لیست شرکت ها' THEN '/list'
                    WHEN 'لیست شرکت‌ها' THEN '/list'
                    WHEN 'فهرست شرکت ها' THEN '/list'
                    WHEN 'فهرست شرکت‌ها' THEN '/list'
                    WHEN 'امروز' THEN '/today'
                    WHEN 'آمار نمایشگاه' THEN '/c'
                    WHEN 'فهرست نمایشگاه' THEN '/c'
                    WHEN 'شرکت جدید' THEN '/new'
                    WHEN 'ثبت شرکت' THEN '/new'
                    WHEN 'سالن ها' THEN '/c'
                    ELSE NULL END;
        IF v_cmd IS NOT NULL THEN v_arg := ''; END IF;
    END IF;
    -- میان‌بر با آرگومان: «ج تابلو»
    IF v_cmd IS NULL AND v_lbl ~ '^(ن|ج|م|پ|و|ش|س)[[:space:]]' THEN
        v_cmd := CASE left(v_lbl, 1)
                    WHEN 'ن' THEN '/new' WHEN 'ج' THEN '/search'
                    WHEN 'ف' THEN '/list'
                    WHEN 'م' THEN '/log' WHEN 'پ' THEN '/task'
                    WHEN 'و' THEN '/visit'
                    WHEN 'ش' THEN '/c' WHEN 'س' THEN '/hall' END;
        v_arg := btrim(substr(v_lbl, 2));
    END IF;

    SELECT s.state, s.payload INTO v_state, v_payload
      FROM iee1405.session_get(p_chat_id) s;
    v_state   := COALESCE(v_state, 'idle');
    v_payload := COALESCE(v_payload, '{}'::jsonb);

    -- ۵.۳.۸) مصاحبهٔ غرفه
    -- کل جریان در iee1405.iv_step است (شروع → نام → سمت → سؤال‌ها → ثبت)، چون
    -- آزمودن یک تابع خالص ساده‌تر از آزمودن هفت حالت درون این تابع بلند است.
    -- اگر تابع نصب نشده باشد (استقرار ناقص)، هیچ‌چیز نمی‌شکند و پیام عادی می‌آید.
    IF to_regprocedure('iee1405.iv_step(bigint, text, text, text, jsonb)') IS NOT NULL
       AND (v_state LIKE 'iv!_%' ESCAPE '!'
            OR v_text ~ '^(i|x):') THEN
        SELECT s.reply, s.markup, s.state, s.payload
          INTO v_reply, v_markup, v_state, v_payload
          FROM iee1405.iv_step(p_chat_id, v_actor, v_text, v_state, v_payload) s;

        PERFORM iee1405.session_set(p_chat_id, v_actor, v_state, v_payload);

        UPDATE iee1405.bot_updates
           SET status = 'processed', reply_text = v_reply, actor = v_actor,
               processed_at = now(), reply_markup = v_markup,
               edit_message_id = COALESCE(p_edit_message_id, edit_message_id)
         WHERE update_id = p_update_id;

        RETURN QUERY SELECT p_chat_id, 'ok'::text, v_reply, NULL::text;
        RETURN;
    END IF;

    -- ۵.۳.۸.۵) کارت شرکتی که در ربات ثبت شده (دکمهٔ o:<ORG-code>)
    -- این دکمه از بخش «ثبت‌شده در ربات» فهرست/جست‌وجو می‌آید (فایل ۰۹). چرا
    -- شاخهٔ جدا؟ چون به آینهٔ نمایشگاه وابسته نیست: شرکتی که با /new ثبت شده
    -- باید همیشه کارت داشته باشد، حتی اگر آینه خالی باشد.
    IF v_text LIKE 'o:%' THEN
        v_code_in := iee1405.parse_org_code(substring(v_text FROM 3));
        IF v_code_in IS NULL THEN
            v_reply := iee1405.msg('org_notfound',
                                   jsonb_build_object('code', substring(v_text FROM 3)));
        ELSE
            SELECT o.id, o.code INTO v_org_id, v_org_code
              FROM crm.organizations o
             WHERE o.code = v_code_in AND o.deleted_at IS NULL;
        END IF;

        IF v_reply IS NULL THEN
            IF v_org_id IS NULL THEN
                v_reply := iee1405.msg('org_notfound', jsonb_build_object('code', v_code_in));
            ELSE
                v_reply  := iee1405.org_card(v_org_id);
                v_markup := jsonb_build_object('inline_keyboard', jsonb_build_array(
                    jsonb_build_array(
                        jsonb_build_object('text', '↩ بازگشت به فهرست',
                                           'callback_data', 'l:1'),
                        jsonb_build_object('text', '🔎 جست‌وجوی دیگر',
                                           'callback_data', 's:0')
                    )));
            END IF;
        END IF;

        UPDATE iee1405.bot_updates
           SET status = 'processed', reply_text = v_reply, actor = v_actor,
               processed_at = now(), reply_markup = v_markup,
               edit_message_id = COALESCE(p_edit_message_id, edit_message_id)
         WHERE update_id = p_update_id;

        RETURN QUERY SELECT p_chat_id, 'ok'::text, v_reply, v_org_code;
        RETURN;
    END IF;

    -- ۵.۳.۹) دکمه‌های شیشه‌ای (callback_query)
    -- بله دادهٔ دکمه را در `callback_query.data` می‌فرستد و bot_dispatch_json آن را
    -- به‌جای متن می‌گذارد. سه پیشوند:
    --   c:<id>    کارت یک شرکت
    --   l:<page>  صفحهٔ فهرست شرکت‌ها
    --   s:<page>  صفحهٔ نتیجهٔ جست‌وجو (شناسه‌ها در نشست همین چت)
    -- اگر بله روزی callback_query را تحویل نداد، همین کارها با شماره و /list
    -- انجام می‌شود؛ برای همین متن هر صفحه شماره‌گذاری‌شده است.
    IF v_text ~ '^[cls]:' THEN
        v_mirror := to_regprocedure('iee1405.co_page(integer, integer)') IS NOT NULL
                    AND iee1405.mirror_ready();

        IF NOT v_mirror THEN
            v_reply := 'فهرست شرکت‌های نمایشگاه روی این سرور آماده نیست. ' ||
                       'روی سرور: bash 03_ops/load_exhibitors.sh';

        ELSIF v_text LIKE 'c:%' THEN
            v_cid := NULLIF(substring(v_text FROM 3), '')::bigint;
            SELECT b.text_body, b.markup::jsonb INTO v_reply, v_markup
              FROM iee1405.co_card(v_cid, COALESCE((v_payload ->> 'page')::int, 1)) b;

        ELSIF v_text LIKE 'l:%' THEN
            SELECT b.text_body, b.markup::jsonb, b.page, b.pages, b.ids
              INTO v_reply, v_markup, v_page, v_pages, v_ids
              FROM iee1405.co_page(COALESCE(NULLIF(substring(v_text FROM 3), '')::int, 1)) b;
            PERFORM iee1405.session_set(p_chat_id, v_actor, 'co_list',
                        jsonb_build_object('ids', to_jsonb(v_ids),
                                           'page', v_page, 'pages', v_pages));

        ELSE   -- s:<page> صفحهٔ نتیجهٔ جست‌وجو
            v_sids := ARRAY(SELECT jsonb_array_elements_text(v_payload -> 'all'))::bigint[];
            IF v_sids IS NULL OR array_length(v_sids, 1) IS NULL THEN
                v_reply  := 'فهرست کامل شرکت‌های نمایشگاه: /list';
                v_markup := iee1405.co_keyboard(ARRAY[]::bigint[], 1, 1, false)::jsonb;
            ELSE
                SELECT b.text_body, b.markup::jsonb, b.page, b.pages, b.ids
                  INTO v_reply, v_markup, v_page, v_pages, v_ids
                  FROM iee1405.co_page_of(
                        v_sids,
                        '🔎 نتیجهٔ جست‌وجو: «' || COALESCE(v_payload ->> 'q', '') || '»',
                        CASE WHEN substring(v_text FROM 3) ~ '^[0-9]+$'
                             THEN substring(v_text FROM 3)::int ELSE 1 END) b;
                PERFORM iee1405.session_set(p_chat_id, v_actor, 'co_results',
                            jsonb_build_object('all', to_jsonb(v_sids), 'ids', to_jsonb(v_ids),
                                               'q', COALESCE(v_payload ->> 'q', ''),
                                               'page', v_page, 'pages', v_pages));
            END IF;
        END IF;

    -- ۵.۴) دستورها
    ELSIF v_cmd IN ('/start', '/help') THEN
        v_reply := iee1405.msg('help');

    ELSIF v_cmd = '/cancel' THEN
        PERFORM iee1405.session_set(p_chat_id, v_actor, 'idle', '{}'::jsonb);
        v_reply := iee1405.msg('cancelled');

    ELSIF v_cmd = '/new' THEN
        PERFORM iee1405.session_set(p_chat_id, v_actor, 'new_name', '{}'::jsonb);
        v_reply := iee1405.msg('new_ask_name');

    ELSIF v_cmd = '/find' THEN
        IF v_arg = '' THEN
            v_reply := iee1405.msg('find_need_q');
        ELSE
            SELECT string_agg((rn)::text || ') ' || code || ' — ' || legal_name ||
                              CASE WHEN booth <> '' THEN ' [' || booth || ']' ELSE '' END,
                              E'\n'),
                   jsonb_agg(code ORDER BY rn)
              INTO v_list, v_codes
              FROM (SELECT code, legal_name, booth,
                           row_number() OVER () AS rn
                      FROM iee1405.search_orgs(v_arg, 8)) t;
            IF v_list IS NULL THEN
                v_reply := iee1405.msg('find_none');
            ELSE
                PERFORM iee1405.session_set(p_chat_id, v_actor, 'pick_org',
                                            jsonb_build_object('codes', v_codes));
                v_reply := iee1405.msg('find_header',
                                       jsonb_build_object('q', v_arg, 'list', v_list));
            END IF;
        END IF;

    ELSIF v_cmd IN ('/c', '/company', '/شرکت', '/hall') THEN
        -- فهرست نمایشگاه در اسکیمای آینهٔ `barghpa` است، نه در CRM.
        -- اگر آن اسکیما هنوز بارگذاری نشده باشد، پیام روشن می‌دهیم نه خطا.
        IF to_regclass('barghpa.company') IS NULL THEN
            v_reply := 'آینهٔ فهرست نمایشگاه ساخته نشده است. روی سرور: ' ||
                       'bash 03_ops/load_exhibitors.sh';
        ELSIF NOT iee1405.mirror_ready() THEN
            v_reply := 'آینهٔ فهرست نمایشگاه خالی است. روی سرور: ' ||
                       'bash 03_ops/load_exhibitors.sh';
        ELSE
            v_reply := barghpa.bot_reply(CASE WHEN v_cmd = '/hall'
                                              THEN COALESCE(nullif(v_arg, ''), '')
                                              ELSE v_arg END);
        END IF;

    ELSIF v_cmd = '/list' THEN
        -- فهرست دکمه‌ای شرکت‌ها؛ `/list 3` مستقیم به صفحهٔ ۳ می‌رود
        IF to_regprocedure('iee1405.co_page(integer, integer)') IS NULL
           OR NOT iee1405.mirror_ready() THEN
            v_reply := 'فهرست شرکت‌های نمایشگاه روی این سرور آماده نیست. ' ||
                       'روی سرور: bash 03_ops/load_exhibitors.sh';
        ELSE
            SELECT b.text_body, b.markup::jsonb, b.page, b.pages, b.ids
              INTO v_reply, v_markup, v_page, v_pages, v_ids
              FROM iee1405.co_page(CASE WHEN v_arg ~ '^[0-9]+$' THEN v_arg::int ELSE 1 END) b;
            PERFORM iee1405.session_set(p_chat_id, v_actor, 'co_list',
                        jsonb_build_object('ids', to_jsonb(v_ids),
                                           'page', v_page, 'pages', v_pages));
        END IF;

    ELSIF v_cmd = '/search' THEN
        -- جست‌وجوی شرکت‌های نمایشگاه با نتیجهٔ دکمه‌ای.
        -- `/find` برای CRM جدا ماند؛ این یکی فقط آینه را می‌گردد چون در نمایشگاه
        -- ۹۹٪ جست‌وجوها «کدام شرکت، کدام سالن» است.
        IF NOT iee1405.mirror_ready() THEN
            v_reply := 'آینهٔ فهرست نمایشگاه آماده نیست. روی سرور: bash 03_ops/load_exhibitors.sh';
        ELSIF v_arg = '' THEN
            PERFORM iee1405.session_set(p_chat_id, v_actor, 'co_search', '{}'::jsonb);
            v_reply := '🔎 نام شرکت (یا بخشی از آن) را بنویسید.' || E'\n' ||
                       'مثال: ترانسفو · یا ارقام فارسی؛ نیازی به / نیست.' || E'\n' ||
                       'فهرست کامل: /list';
        ELSE
            v_sids := ARRAY(SELECT s.company_id FROM barghpa.search(v_arg, 24) s);
            IF v_sids IS NULL OR array_length(v_sids, 1) IS NULL THEN
                v_reply  := '🔎 «' || v_arg || '» → شرکتی پیدا نشد.' || E'\n' ||
                            'بخشی از نام را بنویسید، یا فهرست کامل: /list';
                v_markup := iee1405.co_keyboard(ARRAY[]::bigint[], 1, 1, false)::jsonb;
            ELSE
                SELECT b.text_body, b.markup::jsonb, b.page, b.pages, b.ids
                  INTO v_reply, v_markup, v_page, v_pages, v_ids
                  FROM iee1405.co_page_of(v_sids, '🔎 نتیجهٔ جست‌وجو: «' || v_arg || '»', 1) b;
                PERFORM iee1405.session_set(p_chat_id, v_actor, 'co_results',
                            jsonb_build_object('all', to_jsonb(v_sids), 'ids', to_jsonb(v_ids),
                                               'q', v_arg, 'page', v_page, 'pages', v_pages));
            END IF;
        END IF;

    ELSIF v_cmd = '/org' THEN
        v_code_in := iee1405.parse_org_code(v_arg);
        IF v_code_in IS NULL THEN
            v_reply := iee1405.msg('org_notfound', jsonb_build_object('code', coalesce(v_arg, '-')));
        ELSE
            SELECT id, code INTO v_org_id, v_org_code FROM crm.organizations
             WHERE code = v_code_in AND deleted_at IS NULL;
            IF v_org_id IS NULL THEN
                v_reply := iee1405.msg('org_notfound', jsonb_build_object('code', v_code_in));
            ELSE
                v_reply := iee1405.org_card(v_org_id);
            END IF;
        END IF;

    ELSIF v_cmd = '/log' THEN
        v_code_in := iee1405.parse_org_code(v_arg);
        v_parts   := string_to_array(v_arg, '|');
        IF v_code_in IS NULL OR array_length(v_parts, 1) < 2 THEN
            v_reply := iee1405.msg('log_usage');
        ELSE
            SELECT id, code, coalesce(display_name, legal_name)
              INTO v_org_id, v_org_code, v_org_name
              FROM crm.organizations WHERE code = v_code_in AND deleted_at IS NULL;

            IF v_org_id IS NULL THEN
                v_reply := iee1405.msg('org_notfound', jsonb_build_object('code', v_code_in));
            ELSE
                v_summary := btrim(v_parts[2]);
                v_next    := CASE WHEN array_length(v_parts, 1) >= 3
                                  THEN nullif(btrim(v_parts[3]), '') END;

                INSERT INTO crm.interactions
                    (organization_id, kind, occurred_at, channel, summary,
                     next_action, next_action_due, recorded_by)
                VALUES (v_org_id, 'meeting', now(), 'bale', v_summary,
                        v_next, CASE WHEN v_next IS NOT NULL THEN current_date + 7 END, v_actor)
                RETURNING id INTO v_inter_id;

                PERFORM crm.audit(v_actor, 'create', 'interaction', v_inter_id,
                                  jsonb_build_object('org', v_org_code, 'summary', left(v_summary, 120)));

                IF v_next IS NOT NULL THEN
                    INSERT INTO crm.tasks
                        (organization_id, source_interaction_id, title, due_date, assignee)
                    VALUES (v_org_id, v_inter_id, v_next, current_date + 7, v_actor)
                    RETURNING id INTO v_task_id;
                    PERFORM crm.audit(v_actor, 'create', 'task', v_task_id,
                                      jsonb_build_object('org', v_org_code));
                    v_reply := iee1405.msg('log_done', jsonb_build_object(
                        'code', v_org_code, 'name', v_org_name, 'summary', v_summary,
                        'vars', E'\nپیگیری: ' || v_next || E'\nسررسید: ' ||
                                to_char(current_date + 7, 'YYYY-MM-DD')));
                ELSE
                    v_reply := iee1405.msg('log_done', jsonb_build_object(
                        'code', v_org_code, 'name', v_org_name, 'summary', v_summary,
                        'vars', ''));
                END IF;
            END IF;
        END IF;

    ELSIF v_cmd = '/cap' THEN
        v_code_in := iee1405.parse_org_code(v_arg);
        v_parts   := string_to_array(v_arg, '|');
        IF v_code_in IS NULL OR array_length(v_parts, 1) < 2 THEN
            v_reply := iee1405.msg('log_usage');
        ELSE
            SELECT id, code, coalesce(display_name, legal_name)
              INTO v_org_id, v_org_code, v_org_name
              FROM crm.organizations WHERE code = v_code_in AND deleted_at IS NULL;
            IF v_org_id IS NULL THEN
                v_reply := iee1405.msg('org_notfound', jsonb_build_object('code', v_code_in));
            ELSE
                PERFORM iee1405.add_claim('organization', v_org_id, 'capability.summary',
                                          btrim(v_parts[2]), 'reported',
                                          NULL, v_actor, NULL, v_actor);
                v_reply := iee1405.msg('cap_done', jsonb_build_object(
                    'code', v_org_code, 'name', v_org_name, 'value', btrim(v_parts[2])));
            END IF;
        END IF;

    ELSIF v_cmd = '/visit' THEN
        v_code_in := iee1405.parse_org_code(v_arg);
        IF v_code_in IS NULL THEN
            v_reply := iee1405.msg('org_notfound', jsonb_build_object('code', coalesce(v_arg, '-')));
        ELSE
            SELECT id, code, coalesce(display_name, legal_name)
              INTO v_org_id, v_org_code, v_org_name
              FROM crm.organizations WHERE code = v_code_in AND deleted_at IS NULL;
            IF v_org_id IS NULL THEN
                v_reply := iee1405.msg('org_notfound', jsonb_build_object('code', v_code_in));
            ELSE
                INSERT INTO iee1405.visits (organization_id, exhibition_id, by_user, outcome)
                SELECT v_org_id, ex.id, v_actor, 'data_only'
                  FROM iee1405.exhibitions ex WHERE ex.code = 'IEE1405'
                RETURNING id INTO v_visit_id;
                PERFORM crm.audit(v_actor, 'create', 'visit', v_visit_id,
                                  jsonb_build_object('org', v_org_code));
                v_reply := iee1405.msg('visit_done', jsonb_build_object(
                    'code', v_org_code, 'name', v_org_name, 'outcome', 'ثبت سریع'));
            END IF;
        END IF;

    ELSIF v_cmd = '/task' THEN
        v_code_in := iee1405.parse_org_code(v_arg);
        v_parts   := string_to_array(v_arg, '|');
        IF v_code_in IS NULL OR array_length(v_parts, 1) < 2 THEN
            v_reply := iee1405.msg('log_usage');
        ELSE
            SELECT id, code INTO v_org_id, v_org_code
              FROM crm.organizations WHERE code = v_code_in AND deleted_at IS NULL;
            IF v_org_id IS NULL THEN
                v_reply := iee1405.msg('org_notfound', jsonb_build_object('code', v_code_in));
            ELSE
                v_title := btrim(v_parts[2]);
                v_days  := CASE WHEN array_length(v_parts, 1) >= 3 AND btrim(v_parts[3]) ~ '^[0-9]{1,3}$'
                                THEN btrim(v_parts[3])::int ELSE 3 END;
                v_due   := current_date + v_days;
                INSERT INTO crm.tasks (organization_id, title, due_date, assignee)
                VALUES (v_org_id, v_title, v_due, v_actor)
                RETURNING id INTO v_task_id;
                PERFORM crm.audit(v_actor, 'create', 'task', v_task_id,
                                  jsonb_build_object('org', v_org_code, 'due', v_due));
                v_reply := iee1405.msg('task_done', jsonb_build_object(
                    'code', v_org_code, 'title', v_title,
                    'due', to_char(v_due, 'YYYY-MM-DD'), 'days', v_days::text));
            END IF;
        END IF;

    ELSIF v_cmd = '/today' THEN
        SELECT * INTO d FROM iee1405.v_today_digest;
        v_reply := iee1405.msg('today', jsonb_build_object(
            'orgs_today', d.orgs_today, 'interactions_today', d.interactions_today,
            'tasks_today', d.tasks_today, 'files_today', d.files_today,
            'orgs_total', d.orgs_total));

    ELSE
        -- ۵.۵) حالت‌های جلسه (متن آزاد)
        IF v_state = 'new_name' THEN
            -- تشخیص تکراری
            SELECT id, code, coalesce(display_name, legal_name)
              INTO v_org_id, v_org_code, v_org_name
              FROM crm.organizations
             WHERE deleted_at IS NULL AND crm.norm_text(legal_name) = crm.norm_text(v_text)
             LIMIT 1;

            IF v_org_id IS NOT NULL THEN
                PERFORM iee1405.session_set(p_chat_id, v_actor, 'new_category',
                                            jsonb_build_object('org_id', v_org_id, 'code', v_org_code));
                v_reply := iee1405.msg('name_duplicate', jsonb_build_object(
                              'code', v_org_code, 'name', v_org_name)) || E'\n\n' ||
                           iee1405.category_list();
            ELSE
                INSERT INTO crm.organizations (legal_name, display_name, org_type, created_by, updated_by)
                VALUES (v_text, v_text, 'other', v_actor, v_actor)
                RETURNING id, code INTO v_org_id, v_org_code;

                PERFORM crm.audit(v_actor, 'create', 'organization', v_org_id,
                                  jsonb_build_object('name', v_text, 'via', 'bale'));

                PERFORM iee1405.session_set(p_chat_id, v_actor, 'new_category',
                                            jsonb_build_object('org_id', v_org_id, 'code', v_org_code));
                v_reply := iee1405.msg('new_ask_category', jsonb_build_object(
                              'code', v_org_code, 'name', v_text,
                              'category_list', iee1405.category_list()));
            END IF;
            v_org_code := v_org_code;

        ELSIF v_state = 'new_category' THEN
            v_cat := iee1405.resolve_category(v_text);
            IF v_cat IS NULL THEN
                v_reply := iee1405.msg('cat_invalid',
                              jsonb_build_object('category_list', iee1405.category_list()));
            ELSE
                v_org_id   := (v_payload ->> 'org_id')::uuid;
                v_org_code := v_payload ->> 'code';
                PERFORM iee1405.add_claim('organization', v_org_id, 'capability.category',
                                          v_cat, 'reported', NULL, v_actor, NULL, v_actor);
                PERFORM iee1405.session_set(p_chat_id, v_actor, 'new_booth',
                                            jsonb_build_object('org_id', v_org_id,
                                                               'code', v_org_code,
                                                               'category', v_cat));
                SELECT title_fa INTO v_title FROM crm.product_categories WHERE code = v_cat;
                v_reply := iee1405.msg('new_ask_booth', jsonb_build_object('category', v_title));

            END IF;

        ELSIF v_state = 'new_booth' THEN
            v_org_id   := (v_payload ->> 'org_id')::uuid;
            v_org_code := v_payload ->> 'code';
            v_cat      := v_payload ->> 'category';
            SELECT hall, number INTO v_hall, v_number FROM iee1405.parse_booth(v_text);

            INSERT INTO iee1405.participations
                (organization_id, exhibition_id, hall, booth_number, confirmed)
            SELECT v_org_id, ex.id, v_hall, v_number, true
              FROM iee1405.exhibitions ex WHERE ex.code = 'IEE1405'
            ON CONFLICT (organization_id, exhibition_id) DO UPDATE
               SET hall = EXCLUDED.hall,
                   booth_number = EXCLUDED.booth_number,
                   confirmed = true;

            PERFORM iee1405.session_set(p_chat_id, v_actor, 'idle', '{}'::jsonb);
            PERFORM crm.audit(v_actor, 'update', 'participation', v_org_id,
                              jsonb_build_object('hall', v_hall, 'booth', v_number));

            SELECT coalesce(display_name, legal_name), title_fa
              INTO v_org_name, v_title
              FROM crm.organizations o
              LEFT JOIN crm.product_categories pc ON pc.code = v_cat
             WHERE o.id = v_org_id;

            v_reply := iee1405.msg('new_done', jsonb_build_object(
                'code', v_org_code, 'name', v_org_name,
                'category', coalesce(v_title, v_cat, '—'),
                'booth', CASE
                            WHEN v_number IS NULL THEN 'ثبت‌نشده'
                            WHEN v_hall IS NULL   THEN v_number
                            ELSE v_hall || '-' || v_number
                         END));

        ELSIF v_state = 'co_list' AND v_text ~ '^[0-9]{1,2}$' THEN
            -- کاربر شمارهٔ شرکت را فرستاده (مسیر بی‌دکمه؛ همان نتیجهٔ دکمه)
            v_ids := ARRAY(SELECT jsonb_array_elements_text(v_payload -> 'ids'))::bigint[];
            v_cid := v_ids[v_text::int];
            IF v_cid IS NULL THEN
                v_reply := 'شمارهٔ بیرون از این صفحه است. فهرست: /list';
            ELSE
                SELECT b.text_body, b.markup::jsonb INTO v_reply, v_markup
                  FROM iee1405.co_card(v_cid, COALESCE((v_payload ->> 'page')::int, 1)) b;
            END IF;

        ELSIF v_state = 'co_search' THEN
            -- دکمهٔ «🔎 جست‌وجو» زده شده و کاربر نام را نوشته است
            IF NOT iee1405.mirror_ready() THEN
                v_reply := 'آینهٔ فهرست نمایشگاه آماده نیست. روی سرور: bash 03_ops/load_exhibitors.sh';
            ELSE
                v_sids := ARRAY(SELECT s.company_id FROM barghpa.search(v_text, 24) s);
                IF v_sids IS NULL OR array_length(v_sids, 1) IS NULL THEN
                    v_reply  := '🔎 «' || v_text || '» → شرکتی پیدا نشد. املای دیگر، یا بخشی از نام.' ||
                                E'\n' || 'فهرست کامل: /list';
                    v_markup := iee1405.co_keyboard(ARRAY[]::bigint[], 1, 1, false)::jsonb;
                    PERFORM iee1405.session_set(p_chat_id, v_actor, 'idle', '{}'::jsonb);
                ELSE
                    SELECT b.text_body, b.markup::jsonb, b.page, b.pages, b.ids
                      INTO v_reply, v_markup, v_page, v_pages, v_ids
                      FROM iee1405.co_page_of(v_sids, '🔎 نتیجهٔ جست‌وجو: «' || v_text || '»', 1) b;
                    PERFORM iee1405.session_set(p_chat_id, v_actor, 'co_results',
                                jsonb_build_object('all', to_jsonb(v_sids), 'ids', to_jsonb(v_ids),
                                                   'q', v_text, 'page', v_page, 'pages', v_pages));
                END IF;
            END IF;

        ELSIF v_state = 'pick_org' AND v_text ~ '^[0-9]{1,2}$' THEN
            v_codes := v_payload -> 'codes';
            v_code_in := v_codes ->> ((v_text::int) - 1);
            IF v_code_in IS NULL THEN
                v_reply := iee1405.msg('find_none');
            ELSE
                SELECT id INTO v_org_id FROM crm.organizations
                 WHERE code = v_code_in AND deleted_at IS NULL;
                v_reply := iee1405.org_card(v_org_id);
                PERFORM iee1405.session_set(p_chat_id, v_actor, 'idle', '{}'::jsonb);
            END IF;

        ELSE
            -- متن آزاد در حالت عادی. قبلاً همه‌چیز «برای شروع: /new …» می‌گرفت
            -- که هم گمراه‌کننده بود و هم عیب‌یابی دکمه‌ها را ناممکن می‌کرد.
            IF v_cmd IS NOT NULL THEN
                -- دستور شناخته‌نشده: متن دقیق ورودی بازگفت می‌شود
                v_reply := iee1405.msg('cmd_unknown', jsonb_build_object('text', v_text));
            ELSIF v_key <> '' AND iee1405.mirror_ready() THEN
                -- در نمایشگاه کافی است نام شرکت تایپ یا دکمه زده شود
                v_count := (SELECT count(*) FROM barghpa.search(v_key, 24));
                IF v_count = 0 THEN
                    -- در آینه نبود؛ شاید شرکتی باشد که با /new در ربات ثبت شده.
                    -- (گزارش مالک: «شرکت جدید در جست‌وجو بالا نمی‌آید».)
                    IF to_regprocedure('iee1405.co_crm_rows(text, integer)') IS NOT NULL
                       AND EXISTS (SELECT 1 FROM iee1405.co_crm_rows(v_text, 8)) THEN
                        SELECT b.text_body, b.markup::jsonb
                          INTO v_reply, v_markup
                          FROM iee1405.co_search(v_text, 1, 8) b;
                    ELSE
                        v_reply := iee1405.msg('not_understood',
                                               jsonb_build_object('text', v_text));
                    END IF;
                ELSIF v_count = 1 THEN
                    -- یک شرکت: مستقیم کارت (سریع‌ترین مسیر در سالن)
                    v_reply := barghpa.bot_reply(v_key);
                    IF to_regprocedure('iee1405.co_keyboard(bigint[], integer, integer, boolean)')
                       IS NOT NULL THEN
                        v_markup := iee1405.co_keyboard(
                            ARRAY(SELECT s.company_id FROM barghpa.search(v_key, 1) s),
                            1, 1, false)::jsonb;
                    END IF;
                ELSE
                    -- چند شرکت: فهرست دکمه‌ای، مثل /search
                    v_sids := ARRAY(SELECT s.company_id FROM barghpa.search(v_key, 24) s);
                    SELECT b.text_body, b.markup::jsonb, b.page, b.pages, b.ids
                      INTO v_reply, v_markup, v_page, v_pages, v_ids
                      FROM iee1405.co_page_of(v_sids, '🔎 نتیجهٔ جست‌وجو: «' || v_text || '»', 1) b;
                    PERFORM iee1405.session_set(p_chat_id, v_actor, 'co_results',
                                jsonb_build_object('all', to_jsonb(v_sids), 'ids', to_jsonb(v_ids),
                                                   'q', v_text, 'page', v_page, 'pages', v_pages));
                END IF;
            ELSIF v_key <> '' THEN
                -- آینه بارگذاری نشده؛ جست‌وجوی CRM
                IF EXISTS (SELECT 1 FROM iee1405.search_orgs(v_key, 1)) THEN
                    v_reply := iee1405.msg('find_header', jsonb_build_object('q', v_text));
                    v_reply := v_reply || E'\n' ||
                               (SELECT string_agg(rn::text || ') ' || code || ' — ' || legal_name,
                                                  E'\n' ORDER BY rn)
                                  FROM (SELECT code, legal_name, row_number() OVER () AS rn
                                          FROM iee1405.search_orgs(v_key, 8)) s);
                ELSE
                    v_reply := iee1405.msg('not_understood',
                                           jsonb_build_object('text', v_text));
                END IF;
            ELSE
                v_reply := iee1405.msg('idle_hint');
            END IF;
        END IF;
    END IF;

    -- ۵.۵.۹) پاسخ تکراری راهنما — فقط برای «طوفان در یک دسته»
    --   اصل: پس از قطعی، هشت «/start» در یک دریافت می‌آید و کاربر هشت پیام
    --   یکسان می‌گیرد؛ آن هشت باید یکی شود.
    --   اما پنجرهٔ ۱۰ دقیقه‌ای فاجعه بود: هر /start عادی در آن بازه **سکوت**
    --   می‌گرفت و از دید کاربر یعنی «ربات خراب است». (دقیقاً همان چیزی که بعد
    --   از فعال‌شدن تشخیص دکمه‌ها گزارش شد: قبلاً /start شناخته نمی‌شد و
    --   idle_hint می‌گرفت، بعد از رفع، شناخته شد و بی‌صدا ماند.)
    --   اکنون: پنجرهٔ کوتاه (پیش‌فرض ۴۵ ثانیه، قابل تنظیم در bot_state) و
    --   فقط برای پاسخ **هم‌متن**. یک /start عادی همیشه پاسخ می‌گیرد.
    IF v_cmd IN ('/start', '/help') AND v_reply IS NOT NULL THEN
        v_dedupe_s := COALESCE((SELECT CASE WHEN value ~ '^[0-9]+$' THEN value::int END
                                  FROM iee1405.bot_state
                                 WHERE key = 'help_dedupe_seconds'), 45);
        IF v_dedupe_s > 0 AND EXISTS (
            SELECT 1 FROM iee1405.bot_updates u
             WHERE u.chat_id = p_chat_id
               AND u.update_id <> p_update_id
               AND u.reply_text = v_reply
               AND u.processed_at >
                   clock_timestamp() - make_interval(secs => v_dedupe_s)
        ) THEN
            v_reply := NULL;
        END IF;
    END IF;

    -- ۵.۵.۸) پاسخ خالی هرگز فرستاده نمی‌شود
    --   چرا؟ روی داده‌ای که `barghpa.stats_text()` برایش خالی برمی‌گرداند
    --   (مثلاً آینهٔ بدون `load_batch`)، `/c` متن خالی ساخت و بله ۴۰۰ داد:
    --   کاربر «سکوت» دید. سکوت، خرابی است؛ یک جملهٔ روشن بهتر است.
    IF v_reply IS NOT NULL AND btrim(v_reply) = '' THEN
        v_reply := iee1405.msg('empty_reply');
    END IF;

    -- ۵.۶) ثبت نتیجه در لاگ آپدیت
    UPDATE iee1405.bot_updates
       SET status = 'processed', reply_text = v_reply, actor = v_actor, processed_at = now(),
           -- دکمه‌های شیشه‌ای همین پاسخ؛ اگر NULL بماند، گرهٔ ارسال صفحه‌کلید پایین
           -- صفحه (current_keyboard) را می‌فرستد.
           reply_markup = COALESCE(v_markup, reply_markup),
           -- اگر این پاسخ به یک دکمه بود، همان پیام ویرایش می‌شود (پیام تازه نه)
           edit_message_id = COALESCE(p_edit_message_id, edit_message_id)
     WHERE update_id = p_update_id;

    RETURN QUERY SELECT p_chat_id, 'ok'::text, v_reply, v_org_code;

EXCEPTION WHEN OTHERS THEN
    -- ۵.۷) خطا: ثبت دقیق و پاسخ محترمانه (بدون از دست رفتن داده)
    INSERT INTO iee1405.bot_errors (update_id, chat_id, stage, message, detail)
    VALUES (p_update_id, p_chat_id, 'bot_dispatch', SQLERRM, SQLSTATE);

    INSERT INTO iee1405.bot_updates (update_id, chat_id, raw, status, error, processed_at)
    VALUES (p_update_id, p_chat_id, COALESCE(p_raw, '{}'::jsonb), 'error', SQLERRM, now())
    ON CONFLICT (update_id) DO UPDATE
       SET status = 'error', error = EXCLUDED.error, processed_at = now();

    RETURN QUERY SELECT p_chat_id, 'error'::text,
        'خطای موقت در ثبت (کد ' || SQLSTATE || '). یک بار دیگر تلاش کنید؛ اگر تکرار شد به مدیر بگویید.',
        NULL::text;
END $$;

COMMENT ON FUNCTION iee1405.bot_dispatch(bigint, bigint, text, jsonb, bigint) IS
'پردازش یک آپدیت بله: احراز هویت، idempotency، مسیریابی دستور، ثبت در پایگاه‌داده، تولید پاسخ';

-- ─────────────────────────────────────────────────────────────────────
-- ۵.۸) پوشش امن یک آپدیت خام بله
--
-- چرا؟ گردش‌کار n8n فقط یک پارامتر می‌فرستد (کل آپدیت به‌صورت JSON)،
-- چون دسترسی به $json.message.chat.id در سمت n8n برای آپدیت‌های بدون
-- پیام متنی (عکس، فایل، پست کانال، callback) خطا می‌دهد و آن خطا
-- می‌تواند کل دسته آپدیت‌ها را از بین ببرد. اینجا همه چیز امن استخراج
-- می‌شود و آپدیت‌های غیرقابل‌پردازش فقط «نادیده» ثبت می‌شوند.
-- ─────────────────────────────────────────────────────────────────────
-- اگر نسخهٔ نصب‌شدهٔ این تابع ستون‌های دیگری برگرداند، CREATE OR REPLACE نمی‌تواند
-- نوع خروجی را عوض کند و کل استقرار با این خطا می‌ایستد:
--   ERROR: cannot change return type of existing function
-- و بدتر: ربات بی‌صدا با نسخهٔ قدیمی به کار خود ادامه می‌دهد (پاسخ خالی).
-- پس امضا صریحاً حذف و از نو ساخته می‌شود. تنها مصرف‌کننده‌اش n8n است و چند خط
-- پایین‌تر بازساخته می‌شود؛ بین این دو خط هیچ اجرایی معنا ندارد.
DROP FUNCTION IF EXISTS iee1405.bot_dispatch_json(jsonb);

SELECT iee1405.drop_stale_result('iee1405', 'bot_dispatch_json',
       'TABLE(chat_id bigint, status text, reply_text text, org_code text)');
CREATE OR REPLACE FUNCTION iee1405.bot_dispatch_json(p_update jsonb)
RETURNS TABLE (chat_id bigint, status text, reply_text text, org_code text)
LANGUAGE plpgsql AS $$
DECLARE
    v_update_id bigint;
    v_chat_id   bigint;
    v_text      text;
    v_kind      text;
    v_edit_id   bigint;   -- شناسهٔ پیامی که دکمه‌اش زده شده (برای ویرایش)
    v_msg       jsonb;
BEGIN
    IF p_update IS NULL OR jsonb_typeof(p_update) <> 'object' THEN
        RETURN QUERY SELECT NULL::bigint, 'invalid'::text, NULL::text, NULL::text;
        RETURN;
    END IF;

    v_update_id := nullif(p_update ->> 'update_id', '')::bigint;

    IF v_update_id IS NULL THEN
        -- بدون کلید update_id یعنی «این یک آپدیت نیست» — مثلاً اجرای بی‌پیام
        -- wf-01 (getUpdates با result خالی). نه خطایی ثبت می‌شود و نه ردیفی
        -- ساخته می‌شود، وگرنه هر ۲۰ ثانیه یک خطای جعلی در سلامت می‌نشست.
        IF NOT (p_update ? 'update_id') THEN
            RETURN;
        END IF;
        RETURN QUERY SELECT NULL::bigint, 'invalid'::text, NULL::text, NULL::text;
        RETURN;
    END IF;

    -- پیام عادی، پست کانال، یا ویرایش پیام
    v_msg  := COALESCE(p_update -> 'message',
                       p_update -> 'channel_post',
                       p_update -> 'edited_message');
    v_kind := CASE
                WHEN p_update ? 'message'        THEN 'message'
                WHEN p_update ? 'channel_post'   THEN 'channel_post'
                WHEN p_update ? 'edited_message' THEN 'edited_message'
                WHEN p_update ? 'callback_query' THEN 'callback_query'
                ELSE 'other'
              END;

    -- callback_query ساختار متفاوتی دارد
    IF v_kind = 'callback_query' THEN
        v_chat_id := nullif(p_update #>> '{callback_query,message,chat,id}', '')::bigint;
        v_text    := COALESCE(p_update #>> '{callback_query,data}', '');
        -- همان پیامی که دکمه رویش زده شده؛ گرهٔ ارسال آن را ویرایش می‌کند
        v_edit_id := nullif(p_update #>> '{callback_query,message,message_id}', '')::bigint;
    ELSIF v_msg IS NOT NULL THEN
        v_chat_id := nullif(v_msg #>> '{chat,id}', '')::bigint;
        v_text    := COALESCE(v_msg ->> 'text', v_msg ->> 'caption', '');
    END IF;

    -- آپدیت بدون گفت‌وگو (مثلاً poll یا inline) → نادیده، بدون پاسخ
    IF v_chat_id IS NULL THEN
        INSERT INTO iee1405.bot_updates (update_id, chat_id, raw, command, status, processed_at)
        VALUES (v_update_id, NULL, p_update, v_kind, 'skipped', now())
        ON CONFLICT (update_id) DO NOTHING;
        RETURN QUERY SELECT NULL::bigint, 'ignored'::text, NULL::text, NULL::text;
        RETURN;
    END IF;

    -- پیام بدون متن (عکس/فایل/صوت): ثبت می‌شود و پاسخ راهنما در صف قرار می‌گیرد
    IF btrim(v_text) = '' THEN
        v_text := 'فعلاً فقط متن ثبت می‌شود.' || E'\n' ||
                  'عکس/فایل را بعد از ثبت متن شرکت بفرستید تا به پرونده وصل شود.' || E'\n' ||
                  'راهنما: /help';

        INSERT INTO iee1405.bot_updates (update_id, chat_id, raw, command, status, reply_text)
        VALUES (v_update_id, v_chat_id, p_update, v_kind, 'received', v_text)
        ON CONFLICT (update_id) DO NOTHING;

        RETURN QUERY SELECT v_chat_id, 'media'::text, v_text, NULL::text;
        RETURN;
    END IF;

    RETURN QUERY
    SELECT d.chat_id, d.status, d.reply_text, d.org_code
      FROM iee1405.bot_dispatch(v_update_id, v_chat_id, v_text, p_update, v_edit_id) d;
END $$;

COMMENT ON FUNCTION iee1405.bot_dispatch_json(jsonb) IS
'پوشش امن یک آپدیت خام بله؛ ورودی واحد گردش‌کار n8n ($1::jsonb)';
