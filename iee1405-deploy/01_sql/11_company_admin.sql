-- ═══════════════════════════════════════════════════════════════════════
-- IEE 1405 — کارت مدیریتی شرکت‌های ثبت‌شده در ربات (ویرایش / حذف)
--
-- خواستهٔ مالک (۱۴۰۵-۱۱-۰۶):
--   «با فراخوانی شرکت‌های جدید، کلید مصاحبه ظاهر نمی‌شود.»  → کارت CRM
--     دکمهٔ «🎤 مصاحبه در غرفه» را گرفت (شرکت آینه این را از قبل داشت).
--   «نیاز به دکمه ویرایش و حذف برای شرکت‌ها نیاز دارم. برای ویرایش امکان
--    تایید نهایی نیاز است و برای حذف هم نیاز به تایید است. تا اشتباه شرکتی
--    حذف نگردد.» → هر دو دو‌مرحله‌ای: اول پیش‌نمایش، بعد تأیید.
--
-- اصول:
--   • ویرایش: مقدار تازه گرفته می‌شود، **پیش‌نمایش «قبلی ← جدید»** نشان داده
--     می‌شود و فقط با «✅ تأیید نهایی» نوشته می‌شود. تا تأیید نشود، هیچ
--     UPDATE‌ای اجرا نمی‌شود.
--   • حذف: **حذف نرم** (`deleted_at`)، نه DELETE. نقش ربات اصلاً مجوز DELETE
--     ندارد (تصمیم امنیتی)، و داده میدانی نباید واقعاً پاک شود. پیش از حذف،
--     صفحهٔ تأیید با کد و نام شرکت می‌آید.
--   • هر دو در `crm.audit_events` ثبت می‌شوند، با `via=bale`.
--   • حذف، مصاحبه‌ها و تعامل‌ها را پاک نمی‌کند؛ فقط شرکت از فهرست/جست‌وجو
--     پنهان می‌شود. بازگردانی با یک UPDATE در README آمده است.
-- ═══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── ۰) خواندن یک شرکت با همهٔ آنچه کارت نشان می‌دهد ───────────────────
SELECT iee1405.drop_stale_result('iee1405', 'co_org_info',
       'TABLE(code text, name text, org_id uuid, activity text, category text, place text, hall text, booth text, interviews text)');
CREATE OR REPLACE FUNCTION iee1405.co_org_info(p_code text)
RETURNS TABLE (code text, name text, org_id uuid, activity text, category text,
               place text, hall text, booth text, interviews text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_code text := upper(btrim(COALESCE(p_code, '')));
BEGIN
    RETURN QUERY
    SELECT o.code,
           COALESCE(NULLIF(btrim(o.display_name), ''), o.legal_name),
           o.id,
           (SELECT cl.value_text FROM crm.claims cl
             WHERE cl.subject_type = 'organization' AND cl.subject_id = o.id
               AND cl.is_current AND cl.attribute = 'capability.summary'),
           (SELECT pc.title_fa
              FROM crm.claims cl JOIN crm.product_categories pc ON pc.code = cl.value_text
             WHERE cl.subject_type = 'organization' AND cl.subject_id = o.id
               AND cl.is_current AND cl.attribute = 'capability.category'),
           NULLIF(btrim(COALESCE(p.hall, '') ||
                        CASE WHEN p.booth_number IS NOT NULL
                             THEN '-' || p.booth_number ELSE '' END), ''),
           p.hall, p.booth_number,
           CASE WHEN to_regprocedure('iee1405.iv_summary_org(text)') IS NOT NULL
                THEN iee1405.iv_summary_org(o.code) ELSE NULL END
      FROM crm.organizations o
      LEFT JOIN iee1405.participations p ON p.organization_id = o.id
      LEFT JOIN iee1405.exhibitions ex
             ON ex.id = p.exhibition_id AND ex.code = 'IEE1405'
     WHERE upper(o.code) = v_code AND o.deleted_at IS NULL
     LIMIT 1;
END $$;

COMMENT ON FUNCTION iee1405.co_org_info(text) IS
'اطلاعات یک شرکت ثبت‌شده در ربات برای کارت و پیش‌نمایش ویرایش';

-- ── ۱) کارت مدیریتی (مصاحبه + ویرایش + حذف) ───────────────────────────
SELECT iee1405.drop_stale_result('iee1405', 'co_org_card',
       'TABLE(text_body text, markup text)');
CREATE OR REPLACE FUNCTION iee1405.co_org_card(p_code text)
RETURNS TABLE (text_body text, markup text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    i     record;
    v_txt text;
BEGIN
    SELECT * INTO i FROM iee1405.co_org_info(p_code) x;
    IF i.code IS NULL THEN
        RETURN QUERY SELECT
            'این شرکت در ربات نیست (یا حذف شده است). فهرست: /list',
            jsonb_build_object('inline_keyboard', jsonb_build_array(
                jsonb_build_array(jsonb_build_object('text', '↩ بازگشت به فهرست',
                                                     'callback_data', 'l:1'))))::text;
        RETURN;
    END IF;

    v_txt := '🏢 ' || i.code || ' — ' || i.name || E'\n' ||
             '🏷 حوزه فعالیت: ' || COALESCE(NULLIF(btrim(i.activity), ''),
                                            'ثبت‌نشده (با ✏️ ویرایش اضافه کنید)') || E'\n' ||
             'نوع: ' || COALESCE(i.category, '—') ||
             ' · سالن/غرفه: ' || COALESCE(i.place, 'ثبت‌نشده') || E'\n' ||
             '📌 ثبت‌شده با ربات (در فهرست نمایشگاه نیست)';

    IF i.interviews IS NOT NULL AND btrim(i.interviews) <> '' THEN
        v_txt := v_txt || E'\n' || i.interviews;
    END IF;

    v_txt := v_txt || E'\n' || '────────────' || E'\n' ||
             '🎤 مصاحبه · ✏️ ویرایش (با تأیید نهایی) · 🗑 حذف (با تأیید)';

    RETURN QUERY SELECT v_txt, jsonb_build_object('inline_keyboard', jsonb_build_array(
        jsonb_build_array(
            jsonb_build_object('text', '🎤 مصاحبه در غرفه',
                               'callback_data', 'i:' || i.code)),
        jsonb_build_array(
            jsonb_build_object('text', '✏️ ویرایش', 'callback_data', 'e:' || i.code),
            jsonb_build_object('text', '🗑 حذف',    'callback_data', 'd:' || i.code)),
        jsonb_build_array(
            jsonb_build_object('text', '↩ بازگشت به فهرست', 'callback_data', 'l:1'),
            jsonb_build_object('text', '🔎 جست‌وجوی دیگر',  'callback_data', 's:0'))
    ))::text;
END $$;

COMMENT ON FUNCTION iee1405.co_org_card(text) IS
'کارت شرکت ثبت‌شده در ربات: مصاحبه + ویرایش + حذف (هر دو با تأیید)';

-- ── ۲) اعمال تغییر (فقط پس از تأیید صریح صدا زده می‌شود) ──────────────
CREATE OR REPLACE FUNCTION iee1405.ca_apply(p_code text, p_field text, p_value text, p_actor text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_info  record;
    v_val   text := btrim(COALESCE(p_value, ''));
    v_old   text;
    v_hall  text;
    v_booth text;
BEGIN
    SELECT * INTO v_info FROM iee1405.co_org_info(p_code) x;
    IF v_info.code IS NULL THEN
        RETURN 'شرکت پیدا نشد.';
    END IF;
    IF v_val = '' THEN
        RETURN 'مقدار خالی پذیرفته نشد؛ چیزی تغییر نکرد.';
    END IF;

    IF p_field = 'name' THEN
        v_old := v_info.name;
        UPDATE crm.organizations
           SET legal_name = v_val,
               display_name = v_val,
               updated_at = now()
         WHERE id = v_info.org_id;

    ELSIF p_field = 'activity' THEN
        v_old := v_info.activity;
        -- ادعای reported: گفتهٔ بازدیدکننده، نه واقعیت تأییدشده (اصل PRJ-IEE-012)
        PERFORM iee1405.add_claim('organization', v_info.org_id, 'capability.summary',
                                  v_val, 'reported', NULL, p_actor, NULL, p_actor);

    ELSIF p_field IN ('hall', 'booth') THEN
        IF p_field = 'hall' THEN
            v_old := v_info.hall;
            v_hall := v_val; v_booth := v_info.booth;
        ELSE
            v_old := v_info.booth;
            v_hall := v_info.hall; v_booth := v_val;
        END IF;

        INSERT INTO iee1405.participations
            (organization_id, exhibition_id, hall, booth_number, confirmed)
        SELECT v_info.org_id, ex.id, v_hall, v_booth, true
          FROM iee1405.exhibitions ex WHERE ex.code = 'IEE1405'
        ON CONFLICT (organization_id, exhibition_id) DO UPDATE
           SET hall = EXCLUDED.hall,
               booth_number = EXCLUDED.booth_number;
    ELSE
        RETURN 'فیلد ناشناخته: ' || COALESCE(p_field, '—');
    END IF;

    PERFORM crm.audit(p_actor, 'update', 'organization', v_info.org_id,
                      jsonb_build_object('field', p_field,
                                         'old', left(COALESCE(v_old, ''), 200),
                                         'new', left(v_val, 200),
                                         'via', 'bale'));
    RETURN '✅ ثبت شد: ' || p_field || ' ← «' || v_val || '»';
END $$;

COMMENT ON FUNCTION iee1405.ca_apply(text, text, text, text) IS
'اعمال یک تغییر تأییدشده روی شرکت (نام/حوزه فعالیت/سالن/غرفه) + ثبت ممیزی';

-- ── ۳) گام‌های گفت‌وگو: ویرایش دومرحله‌ای و حذف دومرحله‌ای ──────────────
SELECT iee1405.drop_stale_result('iee1405', 'ca_step',
       'TABLE(reply text, markup text, state text, payload jsonb)');
CREATE OR REPLACE FUNCTION iee1405.ca_step(
    p_chat bigint, p_actor text, p_text text, p_state text, p_payload jsonb)
RETURNS TABLE (reply text, markup text, state text, payload jsonb)
LANGUAGE plpgsql AS $$
DECLARE
    v_text  text := btrim(COALESCE(p_text, ''));
    v_state text := COALESCE(p_state, 'idle');
    v_p     jsonb := COALESCE(p_payload, '{}'::jsonb);
    v_info  record;
    v_org   text;
    v_field text;
    v_val   text;
    v_label text;
    v_old   text;
    v_res   text;
    v_card  record;
BEGIN
    -- ── ویرایش: منوی فیلدها ──
    IF v_text ~ '^e:ORG-[0-9]+$' THEN
        v_org := upper(substring(v_text FROM 3));
        SELECT * INTO v_info FROM iee1405.co_org_info(v_org) x;
        IF v_info.code IS NULL THEN
            RETURN QUERY SELECT 'شرکت پیدا نشد.', NULL::text, 'idle'::text, '{}'::jsonb;
            RETURN;
        END IF;
        RETURN QUERY SELECT
            '✏️ ویرایش «' || v_info.name || '» (' || v_info.code || ')' || E'\n' ||
            'کدام مورد را عوض کنیم؟' || E'\n' ||
            'نام: ' || v_info.name || E'\n' ||
            'حوزه فعالیت: ' || COALESCE(NULLIF(btrim(v_info.activity), ''), '—') || E'\n' ||
            'سالن: ' || COALESCE(v_info.hall, '—') ||
            ' · غرفه: ' || COALESCE(v_info.booth, '—') || E'\n' ||
            'پس از انتخاب، مقدار تازه را می‌فرستید و پیش از ثبت، پیش‌نمایش می‌بینید.',
            jsonb_build_object('inline_keyboard', jsonb_build_array(
                jsonb_build_array(
                    jsonb_build_object('text', 'نام', 'callback_data', 'ef:name:' || v_org),
                    jsonb_build_object('text', 'حوزه فعالیت', 'callback_data', 'ef:activity:' || v_org)),
                jsonb_build_array(
                    jsonb_build_object('text', 'سالن', 'callback_data', 'ef:hall:' || v_org),
                    jsonb_build_object('text', 'غرفه', 'callback_data', 'ef:booth:' || v_org)),
                jsonb_build_array(
                    jsonb_build_object('text', '✖ انصراف', 'callback_data', 'ex:'))))::text,
            'idle'::text, jsonb_build_object('org', v_org);
        RETURN;
    END IF;

    -- ── ویرایش: انتخاب فیلد → درخواست مقدار تازه ──
    IF v_text ~ '^ef:(name|activity|hall|booth):ORG-[0-9]+$' THEN
        v_field := split_part(v_text, ':', 2);
        v_org   := upper(split_part(v_text, ':', 3));
        SELECT * INTO v_info FROM iee1405.co_org_info(v_org) x;
        IF v_info.code IS NULL THEN
            RETURN QUERY SELECT 'شرکت پیدا نشد.', NULL::text, 'idle'::text, '{}'::jsonb;
            RETURN;
        END IF;

        v_label := CASE v_field WHEN 'name' THEN 'نام'
                               WHEN 'activity' THEN 'حوزه فعالیت'
                               WHEN 'hall' THEN 'سالن'
                               ELSE 'غرفه' END;
        v_old := CASE v_field WHEN 'name' THEN v_info.name
                              WHEN 'activity' THEN v_info.activity
                              WHEN 'hall' THEN v_info.hall
                              ELSE v_info.booth END;

        RETURN QUERY SELECT
            '✏️ ' || v_label || ' تازه برای «' || v_info.name || '»؟' || E'\n' ||
            'مقدار فعلی: ' || COALESCE(NULLIF(btrim(COALESCE(v_old, '')), ''), '—') || E'\n' ||
            'مقدار تازه را بنویسید و بفرستید. (هنوز چیزی تغییر نکرده است.)',
            jsonb_build_object('inline_keyboard', jsonb_build_array(
                jsonb_build_array(jsonb_build_object('text', '✖ انصراف',
                                                     'callback_data', 'ex:'))))::text,
            'ca_val'::text,
            jsonb_build_object('org', v_org, 'field', v_field, 'old', v_old);
        RETURN;
    END IF;

    -- ── ویرایش: دریافت مقدار تازه → پیش‌نمایش با تأیید نهایی ──
    IF v_state = 'ca_val' THEN
        IF v_text = '' OR v_text = 'x:e' OR v_text = 'ex:' THEN
            SELECT * INTO v_card FROM iee1405.co_org_card(v_p ->> 'org') c;
            RETURN QUERY SELECT 'ویرایش لغو شد؛ چیزی تغییر نکرد.' || E'\n\n' || v_card.text_body,
                                v_card.markup, 'idle'::text, '{}'::jsonb;
            RETURN;
        END IF;

        SELECT * INTO v_info FROM iee1405.co_org_info(v_p ->> 'org') x;
        IF v_info.code IS NULL THEN
            RETURN QUERY SELECT 'شرکت پیدا نشد.', NULL::text, 'idle'::text, '{}'::jsonb;
            RETURN;
        END IF;

        v_label := CASE v_p ->> 'field' WHEN 'name' THEN 'نام'
                                        WHEN 'activity' THEN 'حوزه فعالیت'
                                        WHEN 'hall' THEN 'سالن'
                                        ELSE 'غرفه' END;

        RETURN QUERY SELECT
            '🔎 پیش‌نمایش تغییر — هنوز ثبت نشده' || E'\n' ||
            'شرکت: ' || v_info.name || ' (' || v_info.code || ')' || E'\n' ||
            v_label || ':' || E'\n' ||
            '   قبلی: ' || COALESCE(NULLIF(btrim(COALESCE(v_p ->> 'old', '')), ''), '—') || E'\n' ||
            '   جدید: ' || v_text || E'\n' ||
            '────────────' || E'\n' ||
            'اگر درست است، «✅ تأیید نهایی» را بزنید.',
            jsonb_build_object('inline_keyboard', jsonb_build_array(
                jsonb_build_array(
                    jsonb_build_object('text', '✅ تأیید نهایی', 'callback_data', 'ec:')),
                jsonb_build_array(
                    jsonb_build_object('text', '✖ انصراف', 'callback_data', 'ex:'))))::text,
            'ca_pending'::text,
            v_p || jsonb_build_object('value', v_text);
        RETURN;
    END IF;

    -- ── ویرایش: تأیید نهایی ──
    IF v_text = 'ec:' THEN
        IF v_state <> 'ca_pending' OR NOT (v_p ? 'value') THEN
            RETURN QUERY SELECT 'تغییری در انتظار تأیید نیست. ✏️ ویرایش را از کارت شرکت بزنید.',
                                NULL::text, 'idle'::text, '{}'::jsonb;
            RETURN;
        END IF;

        v_res := iee1405.ca_apply(v_p ->> 'org', v_p ->> 'field', v_p ->> 'value', p_actor);
        SELECT * INTO v_card FROM iee1405.co_org_card(v_p ->> 'org') c;
        RETURN QUERY SELECT v_res || E'\n\n' || v_card.text_body,
                            v_card.markup, 'idle'::text, '{}'::jsonb;
        RETURN;
    END IF;

    -- ── حذف: صفحهٔ تأیید ──
    IF v_text ~ '^d:ORG-[0-9]+$' THEN
        v_org := upper(substring(v_text FROM 3));
        SELECT * INTO v_info FROM iee1405.co_org_info(v_org) x;
        IF v_info.code IS NULL THEN
            RETURN QUERY SELECT 'شرکت پیدا نشد یا قبلاً حذف شده است.',
                                NULL::text, 'idle'::text, '{}'::jsonb;
            RETURN;
        END IF;

        RETURN QUERY SELECT
            '⚠️ حذف «' || v_info.name || '» (' || v_info.code || ')' || E'\n' ||
            'شرکت از فهرست و جست‌وجو پنهان می‌شود؛' || E'\n' ||
            'داده پاک نمی‌شود (حذف نرم) و بعداً قابل بازگردانی است.' || E'\n' ||
            'اگر مطمئنید، «🗑 بله، حذف کن» را بزنید.',
            jsonb_build_object('inline_keyboard', jsonb_build_array(
                jsonb_build_array(
                    jsonb_build_object('text', '🗑 بله، حذف کن',
                                       'callback_data', 'dc:' || v_info.code)),
                jsonb_build_array(
                    jsonb_build_object('text', '✖ انصراف',
                                       'callback_data', 'dx:' || v_info.code))))::text,
            'ca_del'::text, jsonb_build_object('org', v_info.code);
        RETURN;
    END IF;

    -- ── حذف: تأیید ──
    IF v_text ~ '^dc:ORG-[0-9]+$' THEN
        -- «dc:» سه نویسه است؛ FROM 4 (اشتباه FROM 3 باعث می‌شد کد «:ORG-…»
        -- ساخته شود و شرکت «پیدا نشود» — همان‌جا آزمون خودکار لو داد).
        v_org := upper(substring(v_text FROM 4));
        SELECT * INTO v_info FROM iee1405.co_org_info(v_org) x;
        IF v_info.code IS NULL THEN
            RETURN QUERY SELECT 'شرکت پیدا نشد یا قبلاً حذف شده است.',
                                NULL::text, 'idle'::text, '{}'::jsonb;
            RETURN;
        END IF;

        UPDATE crm.organizations
           SET deleted_at = now(), updated_at = now()
         WHERE id = v_info.org_id AND deleted_at IS NULL;

        PERFORM crm.audit(p_actor, 'delete', 'organization', v_info.org_id,
                          jsonb_build_object('name', v_info.name, 'soft', true,
                                             'via', 'bale'));

        RETURN QUERY SELECT
            '🗑 حذف شد: «' || v_info.name || '» (' || v_info.code || ')' || E'\n' ||
            'از فهرست و جست‌وجو پنهان شد. داده‌اش (مصاحبه‌ها و ممیزی) پاک نشد.' || E'\n' ||
            'بازگردانی روی سرور: UPDATE crm.organizations SET deleted_at = NULL WHERE code = ''' ||
            v_info.code || ''';',
            jsonb_build_object('inline_keyboard', jsonb_build_array(
                jsonb_build_array(jsonb_build_object('text', '↩ بازگشت به فهرست',
                                                     'callback_data', 'l:1'))))::text,
            'idle'::text, '{}'::jsonb;
        RETURN;
    END IF;

    -- ── انصراف (هر مرحله) ──
    IF v_text LIKE 'ex:%' OR v_text = 'dx:' OR v_text ~ '^dx:ORG-[0-9]+$' THEN
        v_org := COALESCE(NULLIF(upper(substring(v_text FROM 4)), ''),
                          v_p ->> 'org');
        IF v_org IS NOT NULL THEN
            SELECT * INTO v_card FROM iee1405.co_org_card(v_org) c;
            IF v_card.text_body IS NOT NULL THEN
                RETURN QUERY SELECT 'لغو شد؛ چیزی تغییر نکرد.' || E'\n\n' || v_card.text_body,
                                    v_card.markup, 'idle'::text, '{}'::jsonb;
                RETURN;
            END IF;
        END IF;
        RETURN QUERY SELECT 'لغو شد؛ چیزی تغییر نکرد.' || E'\n' || 'فهرست: /list',
                            jsonb_build_object('inline_keyboard', jsonb_build_array(
                                jsonb_build_array(jsonb_build_object(
                                    'text', '↩ بازگشت به فهرست', 'callback_data', 'l:1'))))::text,
                            'idle'::text, '{}'::jsonb;
        RETURN;
    END IF;

    RETURN QUERY SELECT NULL::text, NULL::text, 'idle'::text, '{}'::jsonb;
END $$;

COMMENT ON FUNCTION iee1405.ca_step IS
'ویرایش دومرحله‌ای (پیش‌نمایش + تأیید نهایی) و حذف دومرحله‌ای شرکت‌های ثبت‌شده در ربات';

-- ── ۴) گرنت نقش ربات ─────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iee_app') THEN
        EXECUTE 'GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA iee1405 TO iee_app';
        -- حذف نرم فقط UPDATE می‌خواهد؛ DELETE عمداً داده نشده است.
        EXECUTE 'GRANT UPDATE (deleted_at, updated_at, legal_name, display_name) ON crm.organizations TO iee_app';
    END IF;
END $$;

-- ── ۵) خودآزمایی: پیش‌نمایش پیش از نوشتن، و تأیید پیش از حذف ──────────
DO $$
DECLARE
    r        record;
    v_code   text;
    v_name   text;
    v_cnt    int;
BEGIN
    IF to_regclass('crm.organizations') IS NULL THEN
        RAISE NOTICE 'جدول شرکت‌ها نیست؛ خودآزمایی ویرایش/حذف رد شد';
        RETURN;
    END IF;

    -- یک شرکت آزمایشی می‌سازیم، همه‌چیز را می‌سنجیم و پاک می‌کنیم (حذف نرم
    -- کافی نیست برای آزمون؛ ردیف آزمایشی باید واقعاً برود وگرنه در فهرست
    -- کاربر دیده می‌شود. پس آزمون را داخل تراکنش نمی‌گذاریم، ولی در پایان
    -- ردیف آزمایشی را پاک می‌کنیم).
    INSERT INTO crm.organizations (legal_name, display_name, org_type, created_by, updated_by)
    VALUES ('آزمون خودکار مدیریت شرکت', 'آزمون خودکار مدیریت شرکت', 'other', 'selftest', 'selftest')
    RETURNING code INTO v_code;

    SELECT c.text_body, c.markup INTO r FROM iee1405.co_org_card(v_code) c;
    IF r.text_body NOT LIKE '%مصاحبه%' OR r.markup NOT LIKE '%"i:' || v_code || '"%' THEN
        RAISE EXCEPTION 'کارت شرکت CRM دکمهٔ مصاحبه ندارد: %', left(r.markup, 120);
    END IF;
    IF r.markup NOT LIKE '%"e:' || v_code || '"%'
       OR r.markup NOT LIKE '%"d:' || v_code || '"%' THEN
        RAISE EXCEPTION 'کارت شرکت CRM دکمهٔ ویرایش/حذف ندارد: %', left(r.markup, 200);
    END IF;

    -- ویرایش: مقدار گرفته می‌شود ولی تا تأیید، نام عوض نمی‌شود
    SELECT * INTO r FROM iee1405.ca_step(0, 'selftest', 'ef:name:' || v_code, 'idle', '{}'::jsonb);
    IF r.state <> 'ca_val' THEN
        RAISE EXCEPTION 'گام گرفتن مقدار تازه وضعیت درست نداد: %', r.state;
    END IF;
    SELECT * INTO r FROM iee1405.ca_step(0, 'selftest', 'نام آزمون تازه', r.state, r.payload);
    IF r.state <> 'ca_pending' OR r.reply NOT LIKE '%پیش‌نمایش%' THEN
        RAISE EXCEPTION 'پیش‌نمایش تغییر ساخته نشد (وضعیت %)', r.state;
    END IF;
    SELECT count(*) INTO v_cnt FROM crm.organizations WHERE code = v_code AND legal_name = 'نام آزمون تازه';
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'بدون تأیید نهایی نوشته شد — این همان چیزی است که مالک نمی‌خواهد';
    END IF;

    -- تأیید نهایی
    SELECT * INTO r FROM iee1405.ca_step(0, 'selftest', 'ec:', r.state, r.payload);
    SELECT legal_name INTO v_name FROM crm.organizations WHERE code = v_code;
    IF v_name <> 'نام آزمون تازه' THEN
        RAISE EXCEPTION 'تأیید نهایی اعمال نشد (نام: %)', v_name;
    END IF;

    -- حذف: صفحهٔ تأیید نباید چیزی را حذف کند
    SELECT * INTO r FROM iee1405.ca_step(0, 'selftest', 'd:' || v_code, 'idle', '{}'::jsonb);
    IF r.state <> 'ca_del' OR r.reply NOT LIKE '%حذف%' THEN
        RAISE EXCEPTION 'صفحهٔ تأیید حذف ساخته نشد (وضعیت %)', r.state;
    END IF;
    SELECT count(*) INTO v_cnt FROM crm.organizations WHERE code = v_code AND deleted_at IS NOT NULL;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'پیش از تأیید حذف شد — این همان چیزی است که مالک نمی‌خواهد';
    END IF;

    -- انصراف: نه حذف، نه تغییر
    SELECT * INTO r FROM iee1405.ca_step(0, 'selftest', 'dx:' || v_code, r.state, r.payload);
    SELECT count(*) INTO v_cnt FROM crm.organizations WHERE code = v_code AND deleted_at IS NOT NULL;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'با انصراف هم حذف شد';
    END IF;

    -- تأیید حذف
    SELECT * INTO r FROM iee1405.ca_step(0, 'selftest', 'dc:' || v_code, 'idle', '{}'::jsonb);
    SELECT count(*) INTO v_cnt FROM iee1405.co_org_info(v_code);
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION 'پس از تأیید، شرکت هنوز در فهرست دیده می‌شود';
    END IF;
    IF r.reply NOT LIKE '%حذف شد%' THEN
        RAISE EXCEPTION 'پیام حذف ساخته نشد: %', left(r.reply, 60);
    END IF;

    -- پاک‌کردن ردیف آزمایشی (و مشارکت/ادعاهایش)
    DELETE FROM crm.claims WHERE subject_id = (SELECT id FROM crm.organizations WHERE code = v_code);
    DELETE FROM iee1405.participations WHERE organization_id = (SELECT id FROM crm.organizations WHERE code = v_code);
    DELETE FROM crm.organizations WHERE code = v_code;

    RAISE NOTICE '✅ کارت CRM: مصاحبه + ویرایش + حذف · بدون تأیید چیزی نوشته/حذف نمی‌شود';
END $$;
