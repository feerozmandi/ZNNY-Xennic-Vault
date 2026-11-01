-- ═══════════════════════════════════════════════════════════════════════
-- IEE 1405 — منطق ربات میدانی (Bot Logic)
-- پروژه: PRJ-IEE-016
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
  '/find نام — جست‌وجو\n'
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
  'راهنمای حالت عادی')
ON CONFLICT (key) DO NOTHING;

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

CREATE OR REPLACE FUNCTION iee1405.bot_dispatch(
    p_update_id bigint,
    p_chat_id   bigint,
    p_text      text,
    p_raw       jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE (chat_id bigint, status text, reply_text text, org_code text)
LANGUAGE plpgsql AS $$
DECLARE
    v_text      text := btrim(COALESCE(p_text, ''));
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
    IF v_text LIKE '/%' THEN
        v_cmd := lower(split_part(v_text, ' ', 1));
        v_arg := btrim(substr(v_text, length(split_part(v_text, ' ', 1)) + 1));
    END IF;
    -- میان‌برهای فارسی
    IF v_cmd IS NULL THEN
        v_cmd := CASE lower(v_text)
                    WHEN 'ن' THEN '/new'
                    WHEN 'ج' THEN '/find'
                    WHEN 'م' THEN '/log'
                    WHEN 'پ' THEN '/task'
                    WHEN 'و' THEN '/visit'
                    WHEN 'ر' THEN '/help'
                    ELSE NULL END;
        IF v_cmd IS NOT NULL THEN v_arg := ''; END IF;
    END IF;
    -- میان‌بر با آرگومان: «ج تابلو»
    IF v_cmd IS NULL AND v_text ~ '^(ن|ج|م|پ|و)\s' THEN
        v_cmd := CASE left(v_text, 1)
                    WHEN 'ن' THEN '/new' WHEN 'ج' THEN '/find'
                    WHEN 'م' THEN '/log' WHEN 'پ' THEN '/task'
                    WHEN 'و' THEN '/visit' END;
        v_arg := btrim(substr(v_text, 2));
    END IF;

    SELECT s.state, s.payload INTO v_state, v_payload
      FROM iee1405.session_get(p_chat_id) s;
    v_state   := COALESCE(v_state, 'idle');
    v_payload := COALESCE(v_payload, '{}'::jsonb);

    -- ۵.۴) دستورها
    IF v_cmd IN ('/start', '/help') THEN
        v_reply := iee1405.msg('help');

    ELSIF v_cmd = '/cancel' THEN
        PERFORM iee1405.session_set(p_chat_id, v_actor, 'idle', '{}'::jsonb);
        v_reply := iee1405.msg('cancelled');

    ELSIF v_cmd = '/new' THEN
        PERFORM iee1405.session_set(p_chat_id, v_actor, 'new_name', '{}'::jsonb);
        v_reply := iee1405.msg('new_ask_name');

    ELSIF v_cmd = '/find' THEN
        IF v_arg = '' THEN
            v_reply := iee1405.msg('unknown');
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
            v_reply := iee1405.msg('idle_hint');
        END IF;
    END IF;

    -- ۵.۶) ثبت نتیجه در لاگ آپدیت
    UPDATE iee1405.bot_updates
       SET status = 'processed', reply_text = v_reply, actor = v_actor, processed_at = now()
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

COMMENT ON FUNCTION iee1405.bot_dispatch(bigint, bigint, text, jsonb) IS
'پردازش یک آپدیت بله: احراز هویت، idempotency، مسیریابی دستور، ثبت در پایگاه‌داده، تولید پاسخ';
