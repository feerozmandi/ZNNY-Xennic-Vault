-- ═══════════════════════════════════════════════════════════════════════
-- IEE 1405 — فهرست شرکت‌ها به‌صورت دکمه‌های شیشه‌ای (inline keyboard)
--
-- درخواست مالک: «یک دکمه به عنوان لیست شرکت‌ها؛ داخل پیام، شرکت‌ها به صورت
-- دکمه‌های شیشه در ۲ ستون و در انتها یک ردیف دکمهٔ صفحه بعد و قبل».
--
-- چرا در SQL و نه در n8n؟ چون ساختن JSON صفحه‌کلید با عبارت‌های n8n شکننده
-- است و آزمودنش سخت. این‌جا تابع‌های خالص‌اند، با psql آزموده می‌شوند و
-- گردش‌کار فقط `reply_markup` را عیناً می‌فرستد.
--
-- قرارداد مهم: هر صفحه **هم متن** دارد و هم دکمه. متن، شماره گذاری‌شده است
-- (۱…۸) تا اگر بله callback_query را تحویل نداد، کاربر همان کار را با
-- فرستادن شماره انجام دهد. یک ویژگی که فقط با دکمه کار کند، در روز نمایشگاه
-- ریسک است.
-- ═══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── ۰) ابزار کوچک: برچسب کوتاه دکمه و ارقام فارسی برای نمایش ───────────
CREATE OR REPLACE FUNCTION iee1405.co_label(p_name text, p_max int DEFAULT 24)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
             WHEN length(btrim(COALESCE(p_name, ''))) <= p_max THEN btrim(COALESCE(p_name, ''))
             ELSE rtrim(left(btrim(p_name), p_max - 1)) || '…'
           END
$$;

COMMENT ON FUNCTION iee1405.co_label(text, int) IS
'کوتاه‌کردن نام شرکت برای برچسب دکمه؛ متن دکمه‌های بله محدودیت طول دارد';

-- ارقام لاتین → فارسی، فقط برای نمایش (ذخیره همیشه لاتین است)
CREATE OR REPLACE FUNCTION iee1405.fa_out(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT translate(COALESCE(p, ''), '0123456789', '۰۱۲۳۴۵۶۷۸۹')
$$;

-- ── ۱) ساخت صفحه‌کلید شیشه‌ای ─────────────────────────────────────────
-- خروجی: رشتهٔ JSON آماده برای فیلد reply_markup بله:
--   {"inline_keyboard":[[شرکت۱, شرکت۲],[شرکت۳, شرکت۴],…,[قبل, بعد]]}
-- هر دکمهٔ شرکت:  callback_data = "c:<id>"
-- دکمه‌های ناوبری: callback_data = "l:<page>"
CREATE OR REPLACE FUNCTION iee1405.co_keyboard(
    p_ids bigint[], p_page int, p_pages int, p_nav boolean DEFAULT true)
RETURNS text LANGUAGE sql STABLE AS $$
    WITH btns AS (
        SELECT i.id, i.ord,
               jsonb_build_object('text', iee1405.co_label(c.name_fa, 24),
                                  'callback_data', 'c:' || i.id) AS b
          FROM unnest(COALESCE(p_ids, ARRAY[]::bigint[])) WITH ORDINALITY AS i(id, ord)
          JOIN barghpa.company c ON c.id = i.id
    ), rows AS (
        SELECT (btns.ord - 1) / 2 AS r,
               jsonb_agg(btns.b ORDER BY btns.ord) AS arr
          FROM btns
         GROUP BY (btns.ord - 1) / 2
    )
    SELECT jsonb_build_object(
        'inline_keyboard',
        COALESCE((SELECT jsonb_agg(rows.arr ORDER BY rows.r) FROM rows), '[]'::jsonb)
        ||
        CASE WHEN p_nav THEN
            jsonb_build_array(
                jsonb_build_array(
                    jsonb_build_object('text', '◀ صفحه قبل',
                                       'callback_data', 'l:' || GREATEST(COALESCE(p_page, 1) - 1, 1)),
                    jsonb_build_object('text', 'صفحه بعد ▶',
                                       'callback_data', 'l:' || LEAST(COALESCE(p_page, 1) + 1,
                                                                      GREATEST(COALESCE(p_pages, 1), 1)))
                )
            )
        ELSE '[]'::jsonb END
    )::text
$$;

COMMENT ON FUNCTION iee1405.co_keyboard IS
'صفحه‌کلید شیشه‌ای فهرست شرکت‌ها: دو ستون شرکت + یک ردیف ناوبری (قبل/بعد)';

-- ── ۲) هستهٔ صفحه‌بندی: از یک فهرست شناسه، یک صفحه می‌سازد ────────────
-- هر سه تابع زیر همین شکل خروجی را دارند، پس n8n و آزمون‌ها یک قرارداد
-- می‌بینند: متن صفحه، صفحه‌کلید، شمارهٔ صفحه، شمار کل صفحه‌ها، شناسه‌های صفحه.
SELECT iee1405.drop_stale_result('iee1405', 'co_page_of',
       'TABLE(text_body text, markup text, page integer, pages integer, ids bigint[])');
CREATE OR REPLACE FUNCTION iee1405.co_page_of(
    p_ids bigint[], p_title text, p_page int DEFAULT 1, p_size int DEFAULT 8)
RETURNS TABLE (text_body text, markup text, page int, pages int, ids bigint[])
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_total int := COALESCE(array_length(p_ids, 1), 0);
    v_size  int := GREATEST(COALESCE(p_size, 8), 1);
    v_pages int;
    v_page  int;
    v_off   int;
    v_rows  text;
    v_out   bigint[];
BEGIN
    IF v_total = 0 THEN
        RETURN QUERY SELECT p_title || E'\n' ||
                            'چیزی برای نمایش نیست. اگر آینه خالی است: bash 03_ops/load_exhibitors.sh',
                            NULL::text, 1, 1, ARRAY[]::bigint[];
        RETURN;
    END IF;

    v_pages := GREATEST(1, (v_total + v_size - 1) / v_size);
    v_page  := LEAST(GREATEST(COALESCE(p_page, 1), 1), v_pages);
    v_off   := (v_page - 1) * v_size;

    WITH page AS (
        SELECT i.id, i.ord, c.name_fa,
               COALESCE((SELECT string_agg(DISTINCT p.hall, '، ')
                           FROM barghpa.participation p
                          WHERE p.company_id = i.id), '—') AS halls
          FROM unnest(p_ids) WITH ORDINALITY AS i(id, ord)
          JOIN barghpa.company c ON c.id = i.id
         WHERE i.ord > v_off AND i.ord <= v_off + v_size
    )
    SELECT array_agg(page.id ORDER BY page.ord),
           string_agg(iee1405.fa_out((page.ord - v_off)::text) || ') ' ||
                      page.name_fa || ' · ' || page.halls,
                      E'\n' ORDER BY page.ord)
      INTO v_out, v_rows
      FROM page;

    RETURN QUERY SELECT
        p_title || E'\n' ||
        'صفحهٔ ' || iee1405.fa_out(v_page::text) || ' از ' || iee1405.fa_out(v_pages::text) ||
        ' · ' || iee1405.fa_out(v_total::text) || ' شرکت' || E'\n' ||
        '────────────' || E'\n' ||
        v_rows || E'\n' ||
        '────────────' || E'\n' ||
        'دکمه را بزنید، یا شمارهٔ شرکت را بفرستید (۱…' ||
        iee1405.fa_out(LEAST(v_size, array_length(v_out, 1))::text) || ')' ||
        ' · صفحهٔ بعد: /list ' || iee1405.fa_out(LEAST(v_page + 1, v_pages)::text),
        iee1405.co_keyboard(v_out, v_page, v_pages),
        v_page, v_pages, v_out;
END $$;

COMMENT ON FUNCTION iee1405.co_page_of IS
'یک صفحه از فهرست شرکت‌ها: متن شماره‌دار + دکمه‌های شیشه‌ای دو‌ستونی + ناوبری';

-- ── ۳) همهٔ شرکت‌ها، الفبایی ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION iee1405.co_page(p_page int DEFAULT 1, p_size int DEFAULT 8)
RETURNS TABLE (text_body text, markup text, page int, pages int, ids bigint[])
LANGUAGE plpgsql STABLE AS $$
DECLARE v_ids bigint[];
BEGIN
    IF to_regclass('barghpa.company') IS NULL OR NOT iee1405.mirror_ready() THEN
        RETURN QUERY SELECT 'آینهٔ فهرست نمایشگاه آماده نیست. روی سرور: bash 03_ops/load_exhibitors.sh',
                            NULL::text, 1, 1, ARRAY[]::bigint[];
        RETURN;
    END IF;

    -- ترتیب روی name_norm است، نه name_fa: نام‌های یکسان با ی/ک عربی و فارسی
    -- باید کنار هم بیایند، وگرنه فهرست برای کاربر «نامرتب» دیده می‌شود.
    SELECT array_agg(c.id ORDER BY c.name_norm, c.id) INTO v_ids FROM barghpa.company c;

    RETURN QUERY SELECT * FROM iee1405.co_page_of(v_ids, '🏢 فهرست شرکت‌های نمایشگاه',
                                                  p_page, p_size) x;
END $$;

COMMENT ON FUNCTION iee1405.co_page IS
'صفحهٔ فهرست الفبایی همهٔ شرکت‌های نمایشگاه (۲۹۷ شرکت در آینه)';

-- ── ۴) جست‌وجو با نتیجهٔ دکمه‌ای ──────────────────────────────────────
-- برخلاف `/c نام` که فقط متن می‌داد، این‌جا نتیجه به دکمه تبدیل می‌شود:
-- کاربر شرکت را می‌بیند و با یک ضربه کارتش را باز می‌کند.
CREATE OR REPLACE FUNCTION iee1405.co_search(
    p_q text, p_page int DEFAULT 1, p_size int DEFAULT 8, p_max int DEFAULT 24)
RETURNS TABLE (text_body text, markup text, page int, pages int, ids bigint[])
LANGUAGE plpgsql STABLE AS $$
DECLARE v_ids bigint[];
BEGIN
    IF to_regclass('barghpa.company') IS NULL OR NOT iee1405.mirror_ready() THEN
        RETURN QUERY SELECT 'آینهٔ فهرست نمایشگاه آماده نیست. روی سرور: bash 03_ops/load_exhibitors.sh',
                            NULL::text, 1, 1, ARRAY[]::bigint[];
        RETURN;
    END IF;

    SELECT array_agg(s.company_id ORDER BY s.rn) INTO v_ids
      FROM (SELECT company_id, row_number() OVER () AS rn
              FROM barghpa.search(btrim(COALESCE(p_q, '')), GREATEST(COALESCE(p_max, 24), 1))) s;

    IF v_ids IS NULL OR array_length(v_ids, 1) = 0 THEN
        RETURN QUERY SELECT '🔎 جست‌وجو: «' || btrim(COALESCE(p_q, '')) || '»' || E'\n' ||
                            'شرکتی با این نام پیدا نشد. املای دیگر، یا فقط بخشی از نام را بنویسید.' ||
                            E'\n' || 'فهرست کامل: /list',
                            iee1405.co_keyboard(ARRAY[]::bigint[], 1, 1),
                            1, 1, ARRAY[]::bigint[];
        RETURN;
    END IF;

    RETURN QUERY SELECT * FROM iee1405.co_page_of(
        v_ids, '🔎 نتیجهٔ جست‌وجو: «' || btrim(COALESCE(p_q, '')) || '»', p_page, p_size) x;
END $$;

COMMENT ON FUNCTION iee1405.co_search IS
'جست‌وجوی نام شرکت با نتیجهٔ دکمه‌ای صفحه‌بندی‌شده (تا ۲۴ نتیجه در ۳ صفحه)';

-- ── ۵) کارت شرکت + دکمهٔ بازگشت ───────────────────────────────────────
SELECT iee1405.drop_stale_result('iee1405', 'co_card',
       'TABLE(text_body text, markup text)');
CREATE OR REPLACE FUNCTION iee1405.co_card(p_id bigint, p_back_page int DEFAULT 1)
RETURNS TABLE (text_body text, markup text)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_text text;
BEGIN
    IF p_id IS NULL OR NOT EXISTS (SELECT 1 FROM barghpa.company c WHERE c.id = p_id) THEN
        RETURN QUERY SELECT 'شرکت با این شناسه در آینه نیست. /list را بزنید.',
                            iee1405.co_keyboard(ARRAY[]::bigint[], 1, 1, false);
        RETURN;
    END IF;

    v_text := barghpa.card(p_id);

    RETURN QUERY SELECT
        v_text,
        jsonb_build_object('inline_keyboard', jsonb_build_array(
            jsonb_build_array(
                jsonb_build_object('text', '↩ بازگشت به فهرست',
                                   'callback_data', 'l:' || GREATEST(COALESCE(p_back_page, 1), 1)),
                jsonb_build_object('text', '🔎 جست‌وجوی دیگر',
                                   'callback_data', 's:0')
            )
        ))::text;
END $$;

COMMENT ON FUNCTION iee1405.co_card IS
'کارت متنی شرکت از آینه + دکمه‌های بازگشت به فهرست و جست‌وجوی تازه';

-- ── ۶) گرنت نقش ربات (همان نقش n8n) ──────────────────────────────────
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iee_app') THEN
        EXECUTE 'GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA iee1405 TO iee_app';
    END IF;
END $$;

-- ── ۷) خودآزمایی: شکل خروجی، نه فقط «خطا نداد» ───────────────────────
DO $$
DECLARE
    p       record;
    c       record;
    n_rows  int;
    n_cols  int;
    n_pages int;
    nav     jsonb;
BEGIN
    IF to_regclass('barghpa.company') IS NULL OR NOT iee1405.mirror_ready() THEN
        RAISE NOTICE 'آینه خالی است؛ خودآزمایی فهرست رد شد (پس از load_exhibitors.sh دوباره اجرا کنید)';
        RETURN;
    END IF;

    SELECT * INTO p FROM iee1405.co_page(1) x;
    IF p.text_body IS NULL OR p.markup IS NULL THEN
        RAISE EXCEPTION 'فهرست شرکت‌ها متن یا دکمه ندارد';
    END IF;
    IF NOT (p.markup::jsonb ? 'inline_keyboard') THEN
        RAISE EXCEPTION 'صفحه‌کلید شیشه‌ای نیست: %', left(p.markup, 80);
    END IF;
    IF p.pages < 1 OR p.page <> 1 THEN
        RAISE EXCEPTION 'صفحه‌بندی نادرست: صفحه % از %', p.page, p.pages;
    END IF;

    -- ردیف‌های شرکت‌ها باید حداکثر دو دکمه داشته باشند (دو ستون)
    SELECT max(jsonb_array_length(r)) INTO n_cols
      FROM jsonb_array_elements(p.markup::jsonb -> 'inline_keyboard') r;
    IF n_cols > 2 THEN
        RAISE EXCEPTION 'دکمه‌ها دو‌ستونی نیستند (ردیفی با % دکمه)', n_cols;
    END IF;

    -- ردیف آخر باید دکمه‌های قبل/بعد باشد
    SELECT (p.markup::jsonb -> 'inline_keyboard') -> -1 INTO nav;
    IF jsonb_array_length(nav) <> 2
       OR NOT (nav @> '[{"text":"◀ صفحه قبل"}]'::jsonb)
       OR NOT (nav @> '[{"text":"صفحه بعد ▶"}]'::jsonb) THEN
        RAISE EXCEPTION 'ردیف ناوبری درست نیست: %', nav;
    END IF;

    -- شمارهٔ شرکت‌های صفحه باید در متن باشد
    n_rows := COALESCE(array_length(p.ids, 1), 0);
    IF n_rows = 0 OR p.text_body NOT LIKE '%۱)%' THEN
        RAISE EXCEPTION 'متن صفحه شماره‌گذاری ندارد (% ردیف)', n_rows;
    END IF;

    n_pages := p.pages;

    -- کارت با دکمهٔ بازگشت
    SELECT * INTO c FROM iee1405.co_card(p.ids[1]) x;
    IF c.text_body IS NULL OR c.markup NOT LIKE '%l:%' THEN
        RAISE EXCEPTION 'کارت شرکت یا دکمهٔ بازگشت ناقص است';
    END IF;

    RAISE NOTICE '✅ فهرست شرکت‌ها: % صفحه · دو ستون · ناوبری قبل/بعد · کارت سالم', n_pages;
END $$;
