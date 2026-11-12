-- ═══════════════════════════════════════════════════════════════════════
-- آزمون ورودی ربات: دکمه‌ها و برچسب‌های آلوده
-- اجرا: psql -d <db> -v ON_ERROR_STOP=1 -f 03_ops/test_buttons.sql
--
-- چرا؟ روی سرور «هر دکمه» به «برای شروع: /new …» می‌رسید، چون تشخیص دستور با
-- متن خام انجام می‌شد و برچسب دکمه‌های بله نویسه‌های جهت‌دهی/نامرئی و گاهی
-- «@نام‌ربات» دارد. این آزمون همان ورودی‌ها را می‌فرستد و پاسخ درست را می‌خواهد.
--
-- همه‌چیز داخل تراکنش است و با ROLLBACK برمی‌گردد؛ هیچ پیامی به بله نمی‌رود
-- (این توابع فقط ردیف در پایگاه می‌سازند و n8n آن‌ها را نمی‌بیند، چون تراکنش
-- برمی‌گردد).
-- ═══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

BEGIN;

-- کاربران آزمون با چت‌های جدا: قاعدهٔ «پاسخ تکراری راهنما» در ۱۰ دقیقه،
-- اگر همه یک چت باشند، پاسخ دوم را خالی می‌کند و آزمون را الکی قرمز می‌کند.
INSERT INTO crm.users (username, display_name, role, bale_chat_id, is_active) VALUES
    ('btn-1', 'آزمون دکمه ۱', 'owner', 990001, true),
    ('btn-2', 'آزمون دکمه ۲', 'owner', 990002, true),
    ('btn-3', 'آزمون دکمه ۳', 'owner', 990003, true),
    ('btn-4', 'آزمون دکمه ۴', 'owner', 990004, true),
    ('btn-5', 'آزمون دکمه ۵', 'owner', 990005, true),
    ('btn-6', 'آزمون دکمه ۶', 'owner', 990006, true),
    ('btn-7', 'آزمون دکمه ۷', 'owner', 990007, true),
    ('btn-8', 'آزمون فهرست شرکت‌ها', 'owner', 990008, true),
    ('btn-9', 'آزمون جست‌وجوی نمایشگاه', 'owner', 990009, true)
ON CONFLICT (username) DO UPDATE SET bale_chat_id = EXCLUDED.bale_chat_id,
                                     is_active = true;

DO $test$
DECLARE
    n bigint := 990000;
    r record;
    reply text;
    sample text;
    markup text;
    btn text;
    base_err bigint;
    cur_err bigint;
    mk jsonb;
    nav jsonb;
    row_len int;
    first_name text;
    page2_name text;
    div_code   text;
    page2_pages int;
    page2_name_num bigint;
    iv_n2      bigint;
    iv_n bigint;
    fails int := 0;

    -- چت، متن، انتظارِ «چه چیزی در پاسخ باشد»، توضیح

BEGIN
    -- یک نام واقعی از آینه برای آزمون جست‌وجوی خودکار (اگر آینه بارگذاری شده باشد)
    IF iee1405.mirror_ready() THEN
        SELECT name_fa INTO sample FROM barghpa.company ORDER BY id LIMIT 1;
    END IF;

    -- ── T1: دستور با نویسهٔ جهت‌دهی در ابتدا (برچسب دکمه) ─────────────
    n := n + 1;
    SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
        'update_id', n,
        'message', jsonb_build_object(
            'chat', jsonb_build_object('id', 990001),
            'text', E'\u200F\u200E/start'))) d;
    IF reply LIKE '%راهنمای ربات%' THEN
        RAISE NOTICE '✅ T1 · «chr(8207)||/start» (نویسهٔ نامرئی U+200F) → راهنما';
    ELSE
        fails := fails + 1;
        RAISE NOTICE '❌ T1 · «نویسهٔ نامرئی + /start» → %', left(coalesce(reply, '(خالی)'), 40);
    END IF;

    -- ── T2: دستور با @نام‌ربات ───────────────────────────────────────
    n := n + 1;
    SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
        'update_id', n,
        'message', jsonb_build_object(
            'chat', jsonb_build_object('id', 990002),
            'text', '/help@xennicnotifierbot'))) d;
    IF reply LIKE '%راهنمای ربات%' THEN
        RAISE NOTICE '✅ T2 · «/help@xennicnotifierbot» → راهنما';
    ELSE
        fails := fails + 1;
        RAISE NOTICE '❌ T2 · «/help@bot» → %', left(coalesce(reply, '(خالی)'), 40);
    END IF;

    -- ── T3: برچسب فارسی بدون اسلش ───────────────────────────────────
    n := n + 1;
    SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
        'update_id', n,
        'message', jsonb_build_object(
            'chat', jsonb_build_object('id', 990003),
            'text', 'شروع'))) d;
    IF reply LIKE '%راهنمای ربات%' THEN
        RAISE NOTICE '✅ T3 · «شروع» → راهنما';
    ELSE
        fails := fails + 1;
        RAISE NOTICE '❌ T3 · «شروع» → %', left(coalesce(reply, '(خالی)'), 40);
    END IF;

    -- ── T4: ایموجی + دستور (برچسب‌های دکمه‌ای که ایموجی دارند) ────────
    n := n + 1;
    SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
        'update_id', n,
        'message', jsonb_build_object(
            'chat', jsonb_build_object('id', 990004),
            'text', E'📊 امروز /today'))) d;
    IF reply LIKE '%خلاصه امروز%' THEN
        RAISE NOTICE '✅ T4 · «📊 امروز /today» → خلاصه امروز';
    ELSE
        fails := fails + 1;
        RAISE NOTICE '❌ T4 · «📊 امروز /today» → %', left(coalesce(reply, '(خالی)'), 40);
    END IF;

    -- ── T5: دستور ناشناخته باید متن را بازگفت کند (ابزار عیب‌یابی) ────
    n := n + 1;
    SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
        'update_id', n,
        'message', jsonb_build_object(
            'chat', jsonb_build_object('id', 990005),
            'text', '/foo'))) d;
    IF reply LIKE '%/foo%' AND reply LIKE '%نمی‌شناسم%' THEN
        RAISE NOTICE '✅ T5 · «/foo» → دستور ناشناخته با بازگفت متن';
    ELSE
        fails := fails + 1;
        RAISE NOTICE '❌ T5 · «/foo» → %', left(coalesce(reply, '(خالی)'), 40);
    END IF;

    -- ── T6: میان‌بر یک‌حرفی هنوز کار می‌کند ───────────────────────────
    -- چت تازه، نه 990001: قاعدهٔ ضدتکرار راهنما (۱۰ دقیقه) پاسخ دوم را خالی
    -- می‌کند — همان چیزی که در بله شبیه «ربات جواب نمی‌دهد» دیده می‌شود.
    n := n + 1;
    SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
        'update_id', n,
        'message', jsonb_build_object(
            'chat', jsonb_build_object('id', 990005),
            'text', 'ر'))) d;
    IF reply LIKE '%راهنمای ربات%' THEN
        RAISE NOTICE '✅ T6 · «ر» → راهنما';
    ELSE
        fails := fails + 1;
        RAISE NOTICE '❌ T6 · «ر» → %', left(coalesce(reply, '(خالی)'), 40);
    END IF;

    -- ── T7: /c با ارقام فارسی و نویسهٔ نامرئی ────────────────────────
    IF iee1405.mirror_ready() THEN
        n := n + 1;
        SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
            'update_id', n,
            'message', jsonb_build_object(
                'chat', jsonb_build_object('id', 990002),
                'text', E'\u200F/c ۳۸B\u200E'))) d;
        IF reply LIKE '%آینه%' OR reply LIKE '%سالن%' OR reply LIKE '%شرکت%' THEN
            RAISE NOTICE '✅ T7 · «/c با ارقام فارسی و نویسهٔ نامرئی» → پاسخ آینه';
        ELSE
            fails := fails + 1;
            RAISE NOTICE '❌ T7 · «/c ۳۸B» → %', left(coalesce(reply, '(خالی)'), 40);
        END IF;

        -- ── T8: نام شرکت در حالت عادی → جست‌وجوی خودکار ───────────────
        IF sample IS NOT NULL THEN
            n := n + 1;
            SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
                'update_id', n,
                'message', jsonb_build_object(
                    'chat', jsonb_build_object('id', 990003),
                    'text', sample))) d;
            IF reply IS NOT NULL AND reply NOT LIKE '%برای شروع%' THEN
                RAISE NOTICE '✅ T8 · نام شرکت در حالت عادی → جست‌وجوی خودکار (%)',
                             left(coalesce(reply, ''), 30);
            ELSE
                fails := fails + 1;
                RAISE NOTICE '❌ T8 · نام شرکت → %', left(coalesce(reply, '(خالی)'), 40);
            END IF;
        END IF;
    ELSE
        RAISE NOTICE '⏭  T7/T8 رد شد — آینهٔ barghpa بارگذاری نشده است';
    END IF;

    -- ── T9: پیام ناشناخته باید خالی نماند (هیچ‌وقت سکوت) ─────────────
    n := n + 1;
    SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
        'update_id', n,
        'message', jsonb_build_object(
            'chat', jsonb_build_object('id', 990004),
            'text', 'قققق'))) d;
    IF reply IS NOT NULL AND reply <> '' THEN
        RAISE NOTICE '✅ T9 · متن نامفهوم → پاسخ (نه سکوت)';
    ELSE
        fails := fails + 1;
        RAISE NOTICE '❌ T9 · متن نامفهوم → سکوت';
    END IF;

    -- ── T10: طوفان /start در یک دسته → فقط یکی پاسخ می‌گیرد ──────────
    n := n + 1;
    SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
        'update_id', n,
        'message', jsonb_build_object(
            'chat', jsonb_build_object('id', 990006),
            'text', '/start'))) d;
    IF reply LIKE '%راهنمای ربات%' THEN
        RAISE NOTICE '✅ T10 · اولین /start پاسخ گرفت';
    ELSE
        fails := fails + 1;
        RAISE NOTICE '❌ T10 · اولین /start → %', left(coalesce(reply, '(خالی)'), 40);
    END IF;

    n := n + 1;
    SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
        'update_id', n,
        'message', jsonb_build_object(
            'chat', jsonb_build_object('id', 990006),
            'text', '/start'))) d;
    IF reply IS NULL THEN
        RAISE NOTICE '✅ T10b · /start دوم در همان لحظه ساکت شد (ضدتکرار طوفان)';
    ELSE
        fails := fails + 1;
        RAISE NOTICE '❌ T10b · /start دوم هم پاسخ گرفت (ضدتکرار کار نمی‌کند)';
    END IF;

    -- ── T11: بعد از پنجرهٔ کوتاه (۴۵ ثانیه) دوباره پاسخ می‌گیرد ───────
    -- این همان چیزی است که با پنجرهٔ ۱۰ دقیقه‌ای «ربات خراب است» به نظر می‌رسید.
    UPDATE iee1405.bot_updates
       SET processed_at = processed_at - interval '120 seconds'
     WHERE chat_id = 990006;

    n := n + 1;
    SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
        'update_id', n,
        'message', jsonb_build_object(
            'chat', jsonb_build_object('id', 990006),
            'text', '/start'))) d;
    IF reply LIKE '%راهنمای ربات%' THEN
        RAISE NOTICE '✅ T11 · /start بعد از پنجرهٔ ضدتکرار دوباره پاسخ گرفت';
    ELSE
        fails := fails + 1;
        RAISE NOTICE '❌ T11 · /start بعد از پنجره → % (ربات ساکت می‌ماند)',
                     left(coalesce(reply, '(خالی)'), 40);
    END IF;

    -- ── T12: دکمه‌ها (reply_markup) — قرارداد گرهٔ ارسال در n8n ───────
    -- گرهٔ «📤 پاسخ‌های آماده ارسال» ستون reply_markup را می‌خواند و عیناً به
    -- بله می‌فرستد. اگر تابع این ستون را برنگرداند، کل ارسال می‌شکند:
    --   column "reply_markup" does not exist  →  ربات کامل ساکت
    n := n + 1;
    SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
        'update_id', n,
        'message', jsonb_build_object(
            'chat', jsonb_build_object('id', 990007),
            'text', '/start'))) d;

    SELECT p.reply_markup INTO markup
      FROM iee1405.pending_replies(50) p
     WHERE p.update_id = n;

    IF markup IS NULL OR markup = '' THEN
        fails := fails + 1;
        RAISE NOTICE '❌ T12 · pending_replies ستون reply_markup را برنگرداند (گرهٔ ارسال می‌شکند)';
    ELSIF NOT (markup::jsonb ? 'keyboard') THEN
        fails := fails + 1;
        RAISE NOTICE '❌ T12 · reply_markup صفحه‌کلید ندارد: %', left(markup, 60);
    ELSE
        RAISE NOTICE '✅ T12 · reply_markup معتبر است (keyboard با % ردیف)',
                     jsonb_array_length(markup::jsonb -> 'keyboard');
    END IF;

    -- ── T13: برچسب دکمه‌های همین صفحه‌کلید باید کار کند ──────────────
    -- اگر برچسبی در منو باشد که bot_dispatch نمی‌شناسد، کاربر دکمه می‌زند و
    -- «دستور نشناختم» می‌گیرد. پس تک‌تک برچسب‌ها آزمایش می‌شوند.
    FOR btn IN
        SELECT jsonb_array_elements_text(row_json) AS label
          FROM jsonb_array_elements(iee1405.menu_keyboard()::jsonb -> 'keyboard') AS row_json,
               LATERAL (SELECT row_json) x
    LOOP
        n := n + 1;
        SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
            'update_id', n,
            'message', jsonb_build_object(
                'chat', jsonb_build_object('id', 990004),
                'text', btn))) d;
        IF reply IS NULL OR reply LIKE '%نمی‌شناسم%' THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T13 · برچسب دکمه «%» شناخته نشد → %', btn, left(coalesce(reply, 'خالی'), 40);
        END IF;
    END LOOP;
    IF fails = 0 THEN
        RAISE NOTICE '✅ T13 · همهٔ برچسب‌های منو به دستور معتبر نگاشت می‌شوند';
    END IF;

    -- ── T14: «اطلاع» با «خطا» قاطی نشود ─────────────────────────────
    -- روی سرور ۲۵ ردیف offset_guard (شناسهٔ خارج از محدودهٔ بله) ساخته شد و
    -- health_text همیشه «⚠️ خطای باز ربات: ۲۵» می‌داد — هشدار دروغ. این ردیف
    -- اطلاع است و نباید در شمارش خطا بیاید؛ ولی باید دیده شود.
    -- نکته: نتیجهٔ تابع اول در متغیر گرفته می‌شود. نوشتن
    -- RAISE NOTICE '… % …', fn(interval '1 hour') مستقیم، پارسر سادهٔ RAISE را
    -- می‌شکند («mismatched parentheses») — یک بار همین‌جا وقت گرفت.
    SELECT iee1405.recent_error_count(interval '1 hour') INTO base_err;
    INSERT INTO iee1405.bot_errors (stage, message)
    VALUES ('offset_guard', 'آزمون T14 — این ردیف خطا نیست');
    SELECT iee1405.recent_error_count(interval '1 hour') INTO cur_err;
    IF cur_err <> base_err THEN
        fails := fails + 1;
        RAISE NOTICE '❌ T14 · ردیف offset_guard به‌اشتباه خطا شمرده شد (% → %)',
                     base_err, cur_err;
    ELSE
        INSERT INTO iee1405.bot_errors (stage, message)
        VALUES ('send', 'آزمون T14 — این ردیف خطاست');
        SELECT iee1405.recent_error_count(interval '1 hour') INTO cur_err;
        IF cur_err <> base_err + 1 THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T14 · خطای واقعی شمرده نشد (% → %)', base_err, cur_err;
        ELSE
            RAISE NOTICE '✅ T14 · «اطلاع» خطا شمرده نمی‌شود، «خطای واقعی» می‌شود';
        END IF;
    END IF;

    -- ── T15: دکمهٔ «لیست شرکت‌ها» → صفحهٔ دکمه‌ای دو‌ستونی + ناوبری ──
    IF iee1405.mirror_ready() THEN
        SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
            'update_id', 990801,
            'message', jsonb_build_object(
                'chat', jsonb_build_object('id', 990008),
                'text', '🏢 لیست شرکت‌ها'))) d;

        SELECT reply_markup INTO mk FROM iee1405.bot_updates WHERE update_id = 990801;

        IF reply IS NULL OR reply NOT LIKE '%فهرست شرکت%' THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T15 · دکمهٔ لیست شرکت‌ها پاسخ فهرست نداد: %',
                         left(coalesce(reply, '(خالی)'), 40);
        ELSIF mk IS NULL OR NOT (mk ? 'inline_keyboard') THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T15 · دکمه‌های شیشه‌ای ساخته نشد: %', left(coalesce(mk::text, 'NULL'), 60);
        ELSE
            SELECT max(jsonb_array_length(rowj)) INTO row_len
              FROM jsonb_array_elements(mk -> 'inline_keyboard') AS rowj;
            SELECT (mk -> 'inline_keyboard') -> -1 INTO nav;
            IF row_len > 2 THEN
                fails := fails + 1;
                RAISE NOTICE '❌ T15 · ردیفی با % دکمه (باید دو‌ستونی باشد)', row_len;
            ELSIF jsonb_array_length(nav) <> 2
                  OR NOT (nav @> '[{"text":"◀ صفحه قبل"}]'::jsonb)
                  OR NOT (nav @> '[{"text":"صفحه بعد ▶"}]'::jsonb) THEN
                fails := fails + 1;
                RAISE NOTICE '❌ T15 · ردیف آخر دکمه‌های قبل/بعد نیست: %', nav;
            ELSE
                RAISE NOTICE '✅ T15 · فهرست شرکت‌ها: دو ستون + ردیف «قبل/بعد»';
            END IF;
        END IF;

        SELECT p.pages INTO page2_pages FROM iee1405.co_page(1) p;

        -- ── T16: دکمهٔ «صفحه بعد» (callback_query) صفحه را عوض می‌کند ──
        SELECT (mk -> 'inline_keyboard') -> -1 -> 0 ->> 'callback_data' INTO first_name;  -- l:1
        row_len := 0;
        SELECT split_part(reply, E'\n', 2) INTO page2_name;   -- عنوان صفحهٔ ۱
        SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
            'update_id', 990802,
            'callback_query', jsonb_build_object(
                'data', ((mk -> 'inline_keyboard') -> -1 -> 1 ->> 'callback_data'),
                'message', jsonb_build_object('chat', jsonb_build_object('id', 990008))))) d;
        -- اگر آینه فقط یک صفحه دارد، «صفحه بعد» طبق طراحی همان صفحه را می‌دهد
        -- و آزمون نباید بشکند (روی دادهٔ محلی با چند شرکت، صفحه عوض می‌شود).
        IF page2_pages < 2 THEN
            RAISE NOTICE '⏭  T16 · آینه یک صفحه دارد؛ تغییر صفحه سنجیده نشد';
        ELSIF reply IS NULL OR split_part(reply, E'\n', 2) = page2_name THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T16 · دکمهٔ «صفحه بعد» صفحه را عوض نکرد (%)',
                         left(coalesce(reply, '(خالی)'), 40);
        ELSE
            RAISE NOTICE '✅ T16 · دکمهٔ «صفحه بعد» صفحه را عوض کرد (%)',
                         btrim(split_part(reply, E'\n', 2));
        END IF;

        -- ── T17: انتخاب با شماره (مسیر بی‌دکمه) همان کارت را می‌دهد ──
        SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
            'update_id', 990803,
            'message', jsonb_build_object(
                'chat', jsonb_build_object('id', 990008),
                'text', '2'))) d;
        IF reply IS NULL OR reply NOT LIKE '%🏭%' THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T17 · شماره در فهرست کارت نداد: %',
                         left(coalesce(reply, '(خالی)'), 40);
        ELSE
            RAISE NOTICE '✅ T17 · شمارهٔ شرکت در فهرست، کارت را باز کرد (مسیر بی‌دکمه)';
        END IF;

        -- ── T18: دکمهٔ «🔎 جست‌وجو» → پرسش، بعد نتیجهٔ دکمه‌ای ─────────
        SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
            'update_id', 990804,
            'message', jsonb_build_object(
                'chat', jsonb_build_object('id', 990009),
                'text', '🔎 جست‌وجو'))) d;
        IF reply IS NULL OR reply NOT LIKE '%نام شرکت%' THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T18 · دکمهٔ جست‌وجو پرسش نکرد: %',
                         left(coalesce(reply, '(خالی)'), 40);
        ELSE
            SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
                'update_id', 990805,
                'message', jsonb_build_object(
                    'chat', jsonb_build_object('id', 990009),
                    'text', left(sample, 12)))) d;
            SELECT reply_markup INTO mk FROM iee1405.bot_updates WHERE update_id = 990805;
            IF reply IS NULL OR mk IS NULL OR NOT (mk ? 'inline_keyboard') THEN
                fails := fails + 1;
                RAISE NOTICE '❌ T18 · نتیجهٔ جست‌وجو دکمه ندارد: %',
                             left(coalesce(reply, '(خالی)'), 40);
            ELSE
                RAISE NOTICE '✅ T18 · جست‌وجو → نتیجهٔ دکمه‌ای (نه فهرست متنی)';
            END IF;
        END IF;
    ELSE
        RAISE NOTICE '⏭  T15–T18 رد شد — آینهٔ barghpa بارگذاری نشده است';
    END IF;

    -- ── T19: کارت شرکت: حوزهٔ فعالیت + دکمهٔ مصاحبه ─────────────────
    IF iee1405.mirror_ready() THEN
        SELECT c.text_body INTO reply FROM iee1405.co_card((SELECT min(id) FROM barghpa.company)) c;
        SELECT c.markup::jsonb INTO mk FROM iee1405.co_card((SELECT min(id) FROM barghpa.company)) c;
        IF reply NOT LIKE '%حوزه فعالیت%' THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T19 · حوزهٔ فعالیت روی کارت نیست';
        ELSIF NOT (mk @> '[{"callback_data":"i:1"}]'::jsonb)
              AND NOT (mk::text LIKE '%"i:%') THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T19 · دکمهٔ مصاحبه روی کارت نیست';
        ELSE
            RAISE NOTICE '✅ T19 · کارت: حوزهٔ فعالیت زیر نام + دکمهٔ «🎤 مصاحبه»';
        END IF;

        -- ── T20: پاسخ به دکمه، شناسهٔ پیام را برای ویرایش می‌آورد ────
        SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
            'update_id', 990901,
            'callback_query', jsonb_build_object(
                'data', 'l:2',
                'message', jsonb_build_object('message_id', 4242,
                                              'chat', jsonb_build_object('id', 990008))))) d;
        SELECT u.edit_message_id INTO row_len FROM iee1405.bot_updates u WHERE u.update_id = 990901;
        IF row_len IS DISTINCT FROM 4242 THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T20 · شناسهٔ پیام برای ویرایش ثبت نشد: %', coalesce(row_len::text, 'NULL');
        ELSE
            RAISE NOTICE '✅ T20 · پاسخ دکمه، پیام را ویرایش می‌کند (نه پیام تازه)';
        END IF;
    ELSE
        RAISE NOTICE '⏭  T19/T20 رد شد — آینه بارگذاری نشده است';
    END IF;

    -- ── T21: مصاحبهٔ کامل از ورودی بله ──────────────────────────────
    IF iee1405.mirror_ready()
       AND to_regprocedure('iee1405.iv_step(bigint, text, text, text, jsonb)') IS NOT NULL THEN
        DELETE FROM iee1405.interviews WHERE chat_id = 990010;
        INSERT INTO crm.users (username, display_name, role, bale_chat_id, is_active)
        VALUES ('btn-10', 'آزمون مصاحبه', 'owner', 990010, true)
        ON CONFLICT (username) DO UPDATE SET bale_chat_id = 990010, is_active = true;
        PERFORM iee1405.session_set(990010, 'btn-10', 'idle', '{}'::jsonb);

        PERFORM iee1405.bot_dispatch_json(jsonb_build_object(
            'update_id', 991001,
            'callback_query', jsonb_build_object(
                'data', 'i:' || (SELECT min(id) FROM barghpa.company),
                'message', jsonb_build_object('message_id', 5001,
                                              'chat', jsonb_build_object('id', 990010)))));
        PERFORM iee1405.bot_dispatch_json(jsonb_build_object(
            'update_id', 991002,
            'message', jsonb_build_object('chat', jsonb_build_object('id', 990010),
                                          'text', 'حسن نوری')));
        PERFORM iee1405.bot_dispatch_json(jsonb_build_object(
            'update_id', 991003,
            'message', jsonb_build_object('chat', jsonb_build_object('id', 990010),
                                          'text', 'مدیر بازرگانی')));
        FOR i IN 1..6 LOOP
            PERFORM iee1405.bot_dispatch_json(jsonb_build_object(
                'update_id', 991010 + i,
                'message', jsonb_build_object('chat', jsonb_build_object('id', 990010),
                                              'text', 'پاسخ آزمایشی ' || i)));
        END LOOP;

        SELECT count(*), max(interviewee_name), max(interviewee_role), max(state)
          INTO base_err, first_name, page2_name, btn
          FROM iee1405.interviews WHERE chat_id = 990010;

        IF base_err <> 1 THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T21 · مصاحبه ثبت نشد (% ردیف)', base_err;
        ELSIF first_name IS DISTINCT FROM 'حسن نوری' OR page2_name IS DISTINCT FROM 'مدیر بازرگانی' THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T21 · نام/سمت درست ثبت نشد: % — %',
                         coalesce(first_name, 'NULL'), coalesce(page2_name, 'NULL');
        ELSIF btn <> 'done' THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T21 · مصاحبه کامل نشد (وضعیت: %)', btn;
        ELSE
            RAISE NOTICE '✅ T21 · مصاحبه: نام → سمت → ۶ پاسخ → ثبت کامل';
        END IF;

        -- ── T22: پایان زودهنگام هم ثبت می‌شود (نه دور ریخته) ───────
        PERFORM iee1405.session_set(990010, 'btn-10', 'idle', '{}'::jsonb);
        PERFORM iee1405.bot_dispatch_json(jsonb_build_object(
            'update_id', 991101,
            'callback_query', jsonb_build_object(
                'data', 'i:' || (SELECT min(id) FROM barghpa.company),
                'message', jsonb_build_object('message_id', 5002,
                                              'chat', jsonb_build_object('id', 990010)))));
        PERFORM iee1405.bot_dispatch_json(jsonb_build_object(
            'update_id', 991102,
            'message', jsonb_build_object('chat', jsonb_build_object('id', 990010),
                                          'text', 'رضا کاظمی')));
        PERFORM iee1405.bot_dispatch_json(jsonb_build_object(
            'update_id', 991103,
            'message', jsonb_build_object('chat', jsonb_build_object('id', 990010),
                                          'text', 'کارشناس')));
        SELECT d.reply_text INTO reply FROM iee1405.bot_dispatch_json(jsonb_build_object(
            'update_id', 991104,
            'callback_query', jsonb_build_object(
                'data', 'x:e',
                'message', jsonb_build_object('message_id', 5003,
                                              'chat', jsonb_build_object('id', 990010))))) d;
        IF reply NOT LIKE '%نیمه‌کاره%'
           OR NOT EXISTS (SELECT 1 FROM iee1405.interviews
                           WHERE chat_id = 990010 AND state = 'partial') THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T22 · پایان زودهنگام ثبت نشد: %', left(coalesce(reply, 'خالی'), 40);
        ELSE
            RAISE NOTICE '✅ T22 · «پایان زودهنگام» مصاحبه را نیمه‌کاره ثبت کرد';
        END IF;
        -- ── T23: سؤال اختصاصی شرکت (خروجی هوش مصنوعی) ───────────────
        DELETE FROM iee1405.iv_company_q
         WHERE question = 'آزمون: چند نمونه در ماه تولید می‌کنید؟';
        INSERT INTO iee1405.iv_company_q (company_ref, question, source)
        VALUES ((SELECT min(id) FROM barghpa.company),
                'آزمون: چند نمونه در ماه تولید می‌کنید؟', 'ai');
        SELECT count(*) INTO base_err
          FROM iee1405.iv_questions((SELECT min(id) FROM barghpa.company)) q
         WHERE q.code = 'custom' AND q.q = 'آزمون: چند نمونه در ماه تولید می‌کنید؟';
        IF base_err <> 1 THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T23 · سؤال اختصاصی شرکت در فهرست سؤال‌ها نیامد';
        ELSE
            RAISE NOTICE '✅ T23 · سؤال اختصاصی شرکت (منبع ai) در فهرست آمد';
        END IF;
        DELETE FROM iee1405.iv_company_q
         WHERE question = 'آزمون: چند نمونه در ماه تولید می‌کنید؟';
    ELSE
        RAISE NOTICE '⏭  T21/T22/T23 رد شد — آینه یا تابع مصاحبه موجود نیست';
    END IF;

    -- ── T24/T25: شرکت ثبت‌شده در ربات، در فهرست و جست‌وجو ──────────────
    -- گزارش مالک: «با ثبت شرکت جدید، در لیست شرکت‌ها ثبت نمی‌گردد و در جست‌وجو
    -- بالا نمی‌آید.» آزمون، همان مسیر واقعی /new را می‌رود و بعد می‌سنجد.
    -- بدون آینه، `co_page` خودش «فهرست خالی» می‌دهد؛ پس این دو مورد فقط با
    -- آینهٔ بارگذاری‌شده معنا دارند (روی پایگاه تازه، «رد» می‌شوند نه «سرخ»).
    IF to_regprocedure('iee1405.co_crm_rows(text, integer)') IS NOT NULL
       AND iee1405.mirror_ready() THEN
        INSERT INTO crm.users (username, display_name, role, bale_chat_id, is_active)
        VALUES ('btn-11', 'آزمون ثبت ربات', 'owner', 990011, true)
        ON CONFLICT (username) DO UPDATE SET bale_chat_id = 990011, is_active = true;
        PERFORM iee1405.session_set(990011, 'btn-11', 'idle', '{}'::jsonb);
        DELETE FROM crm.organizations WHERE legal_name = 'آزمون شرکت تازهٔ ربات';

        PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 992001,
            'message', jsonb_build_object('chat', jsonb_build_object('id', 990011), 'text', '/new')));
        PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 992002,
            'message', jsonb_build_object('chat', jsonb_build_object('id', 990011),
                                          'text', 'آزمون شرکت تازهٔ ربات')));
        PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 992003,
            'message', jsonb_build_object('chat', jsonb_build_object('id', 990011), 'text', 'TAB_MV')));
        PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 992004,
            'message', jsonb_build_object('chat', jsonb_build_object('id', 990011), 'text', '41-03')));

        SELECT count(*) INTO base_err FROM iee1405.co_crm_rows('آزمون شرکت تازهٔ ربات', 8);
        IF base_err <> 1 THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T24 · شرکت ثبت‌شده با /new در فهرست ربات نیامد (% ردیف)', base_err;
        ELSE
            PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 992005,
                'message', jsonb_build_object('chat', jsonb_build_object('id', 990011), 'text', '/list')));
            SELECT d.text_body, d.markup::text INTO reply, mk
              FROM iee1405.co_page(1) d;
            IF reply NOT LIKE '%آزمون شرکت تازهٔ ربات%' OR mk::text NOT LIKE '%"o:ORG-%' THEN
                fails := fails + 1;
                RAISE NOTICE '❌ T24 · در فهرست/جست‌وجو دیده نشد (متن: % · دکمه: %)',
                             (reply LIKE '%آزمون شرکت تازهٔ ربات%'), (mk::text LIKE '%"o:ORG-%');
            ELSE
                RAISE NOTICE '✅ T24 · شرکت ثبت‌شده با /new در فهرست و جست‌وجو آمد (دکمهٔ o:)';
            END IF;

            -- T25: دکمهٔ o: کارت همان شرکت را می‌دهد و پیام را ویرایش می‌کند
            SELECT d.reply_text INTO reply
              FROM iee1405.bot_dispatch_json(jsonb_build_object(
                     'update_id', 992006,
                     'callback_query', jsonb_build_object(
                        'data', 'o:' || (SELECT code FROM crm.organizations
                                          WHERE legal_name = 'آزمون شرکت تازهٔ ربات' LIMIT 1),
                        'message', jsonb_build_object('message_id', 7301,
                                                      'chat', jsonb_build_object('id', 990011))))) d;
            SELECT u.edit_message_id INTO row_len FROM iee1405.bot_updates u WHERE u.update_id = 992006;
            IF reply NOT LIKE '%آزمون شرکت تازهٔ ربات%' OR row_len IS DISTINCT FROM 7301 THEN
                fails := fails + 1;
                RAISE NOTICE '❌ T25 · دکمهٔ o: کارت/edit را درست نداد (edit=%)', coalesce(row_len::text, 'NULL');
            ELSE
                RAISE NOTICE '✅ T25 · دکمهٔ o: کارت شرکت CRM را در همان پیام نشان داد';
            END IF;
        END IF;

        DELETE FROM crm.organizations WHERE legal_name = 'آزمون شرکت تازهٔ ربات';

        -- ── T26: جریان نیمه‌کاره هم دیده می‌شود ──────────────────────
        -- تا مرحلهٔ غرفه نرفته، «مشارکت» ندارد؛ ولی از راه ربات ثبت شده.
        -- اگر این حالت دیده نشود، همان شکایت مالک برمی‌گردد.
        DELETE FROM crm.organizations WHERE legal_name = 'آزمون شرکت نیمه‌کاره';
        PERFORM iee1405.session_set(990011, 'btn-11', 'idle', '{}'::jsonb);
        PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 992101,
            'message', jsonb_build_object('chat', jsonb_build_object('id', 990011), 'text', '/new')));
        PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 992102,
            'message', jsonb_build_object('chat', jsonb_build_object('id', 990011),
                                          'text', 'آزمون شرکت نیمه‌کاره')));
        SELECT count(*) INTO base_err FROM iee1405.co_crm_rows('نیمه‌کاره', 8);
        IF base_err < 1 THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T26 · شرکت نیمه‌کاره (بدون غرفه) در فهرست نیامد (% ردیف)', base_err;
        ELSE
            RAISE NOTICE '✅ T26 · شرکت نیمه‌کارهٔ ثبت‌شده در ربات هم در فهرست دیده می‌شود';
        END IF;
        DELETE FROM crm.organizations WHERE legal_name = 'آزمون شرکت نیمه‌کاره';
    ELSE
        RAISE NOTICE '⏭  T24/T25 رد شد — توابع بخش «ثبت‌شده در ربات» یا آینهٔ بارگذاری‌شده موجود نیست';
    END IF;

    -- ── T27–T31: کارت مدیریتی شرکت CRM (مصاحبه · ویرایش · حذف) ─────────
    -- خواستهٔ مالک: «با فراخوانی شرکت‌های جدید، کلید مصاحبه ظاهر نمی‌شود» و
    -- «دکمهٔ ویرایش و حذف، با تأیید نهایی برای ویرایش و تأیید برای حذف».
    IF to_regprocedure('iee1405.co_org_card(text)') IS NOT NULL THEN
        INSERT INTO crm.users (username, display_name, role, bale_chat_id, is_active)
        VALUES ('btn-12', 'آزمون مدیریت شرکت', 'owner', 990012, true)
        ON CONFLICT (username) DO UPDATE SET bale_chat_id = 990012, is_active = true;
        PERFORM iee1405.session_set(990012, 'btn-12', 'idle', '{}'::jsonb);
        DELETE FROM crm.organizations WHERE legal_name LIKE 'آزمون مدیریت %';
        DELETE FROM iee1405.interviews WHERE org_code IN
               (SELECT code FROM crm.organizations WHERE legal_name LIKE 'آزمون مدیریت %');

        -- ساخت شرکت با همان مسیر واقعی /new
        PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 993001,
            'message', jsonb_build_object('chat', jsonb_build_object('id', 990012), 'text', '/new')));
        PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 993002,
            'message', jsonb_build_object('chat', jsonb_build_object('id', 990012),
                                          'text', 'آزمون مدیریت کابل')));
        PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 993003,
            'message', jsonb_build_object('chat', jsonb_build_object('id', 990012), 'text', 'TAB_MV')));
        PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 993004,
            'message', jsonb_build_object('chat', jsonb_build_object('id', 990012), 'text', '41-03')));

        SELECT code INTO div_code FROM crm.organizations
         WHERE legal_name = 'آزمون مدیریت کابل' LIMIT 1;
        SELECT count(*) INTO base_err FROM crm.organizations WHERE code = div_code;

        IF base_err <> 1 THEN
            fails := fails + 1;
            RAISE NOTICE '❌ T27 · شرکت آزمون ساخته نشد';
        ELSE
            -- T27: کارت شرکت CRM باید هر سه دکمه را داشته باشد
            SELECT c.text_body, c.markup::text INTO reply, mk
              FROM iee1405.co_org_card(div_code) c;
            IF mk::text NOT LIKE '%"i:' || div_code || '"%'
               OR mk::text NOT LIKE '%"e:' || div_code || '"%'
               OR mk::text NOT LIKE '%"d:' || div_code || '"%' THEN
                fails := fails + 1;
                RAISE NOTICE '❌ T27 · کارت CRM کلید مصاحبه/ویرایش/حذف را ندارد: %', left(mk::text, 120);
            ELSE
                RAISE NOTICE '✅ T27 · کارت شرکت CRM: «🎤 مصاحبه» + «✏️ ویرایش» + «🗑 حذف»';
            END IF;

            -- T28: مصاحبه برای شرکتی که در آینه نیست
            PERFORM iee1405.session_set(990012, 'btn-12', 'idle', '{}'::jsonb);
            PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 993010,
                'callback_query', jsonb_build_object('data', 'i:' || div_code,
                    'message', jsonb_build_object('message_id', 7401,
                                                  'chat', jsonb_build_object('id', 990012)))));
            PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 993011,
                'message', jsonb_build_object('chat', jsonb_build_object('id', 990012),
                                              'text', 'زهرا آزمون')));
            PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 993012,
                'message', jsonb_build_object('chat', jsonb_build_object('id', 990012),
                                              'text', 'مدیر بازرگانی')));
            FOR i IN 1..6 LOOP
                PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 993020 + i,
                    'message', jsonb_build_object('chat', jsonb_build_object('id', 990012),
                                                  'text', 'پاسخ آزمون ' || i)));
            END LOOP;

            SELECT count(*), max(state), max(org_code), max(company_ref)::bigint
              INTO base_err, btn, page2_name, row_len
              FROM iee1405.interviews WHERE org_code = div_code;

            IF base_err <> 1 OR btn <> 'done' OR row_len IS NOT NULL THEN
                fails := fails + 1;
                RAISE NOTICE '❌ T28 · مصاحبهٔ شرکت CRM ثبت نشد (% ردیف · % · ref=%)',
                             base_err, coalesce(btn, 'NULL'), coalesce(row_len::text, 'NULL');
            ELSE
                RAISE NOTICE '✅ T28 · مصاحبه برای شرکت CRM (بدون شناسهٔ آینه) ثبت شد';
            END IF;

            -- T29: ویرایش بدون تأیید نهایی ننویسد
            PERFORM iee1405.session_set(990012, 'btn-12', 'idle', '{}'::jsonb);
            PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 993030,
                'callback_query', jsonb_build_object('data', 'ef:activity:' || div_code,
                    'message', jsonb_build_object('message_id', 7402,
                                                  'chat', jsonb_build_object('id', 990012)))));
            PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 993031,
                'message', jsonb_build_object('chat', jsonb_build_object('id', 990012),
                                              'text', 'تولید کابل فشار متوسط')));

            SELECT count(*) INTO base_err FROM crm.claims c
              JOIN crm.organizations o ON o.id = c.subject_id
             WHERE o.code = div_code AND c.is_current
               AND c.value_text = 'تولید کابل فشار متوسط';
            IF base_err <> 0 THEN
                fails := fails + 1;
                RAISE NOTICE '❌ T29 · بدون تأیید نهایی نوشته شد (این همان ریسک مالک است)';
            ELSE
                PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 993032,
                    'callback_query', jsonb_build_object('data', 'ec:',
                        'message', jsonb_build_object('message_id', 7403,
                                                      'chat', jsonb_build_object('id', 990012)))));
                SELECT count(*) INTO base_err FROM crm.claims c
                  JOIN crm.organizations o ON o.id = c.subject_id
                 WHERE o.code = div_code AND c.is_current
                   AND c.value_text = 'تولید کابل فشار متوسط'
                   AND c.epistemic_status = 'reported';
                IF base_err <> 1 THEN
                    fails := fails + 1;
                    RAISE NOTICE '❌ T29 · تأیید نهایی اعمال نشد (% ردیف)', base_err;
                ELSE
                    RAISE NOTICE '✅ T29 · ویرایش: پیش‌نمایش بی‌اثر، تأیید نهایی می‌نویسد (reported)';
                END IF;
            END IF;

            -- T30: حذف بی‌تأیید نکن، با انصراف هم نکن، با تأیید بکن
            PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 993040,
                'callback_query', jsonb_build_object('data', 'd:' || div_code,
                    'message', jsonb_build_object('message_id', 7404,
                                                  'chat', jsonb_build_object('id', 990012)))));
            SELECT count(*) INTO base_err FROM crm.organizations
             WHERE code = div_code AND deleted_at IS NOT NULL;

            PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 993041,
                'callback_query', jsonb_build_object('data', 'dx:' || div_code,
                    'message', jsonb_build_object('message_id', 7405,
                                                  'chat', jsonb_build_object('id', 990012)))));
            SELECT count(*) INTO iv_n2 FROM iee1405.co_org_info(div_code);

            PERFORM iee1405.bot_dispatch_json(jsonb_build_object('update_id', 993042,
                'callback_query', jsonb_build_object('data', 'dc:' || div_code,
                    'message', jsonb_build_object('message_id', 7406,
                                                  'chat', jsonb_build_object('id', 990012)))));
            SELECT count(*) INTO page2_name_num FROM iee1405.co_org_info(div_code);

            IF base_err <> 0 OR iv_n2 <> 1 OR page2_name_num <> 0 THEN
                fails := fails + 1;
                RAISE NOTICE '❌ T30 · حذف دومرحله‌ای درست کار نکرد (بی‌تأیید=% · انصراف=% · تأیید=%)',
                             base_err, iv_n2, page2_name_num;
            ELSE
                RAISE NOTICE '✅ T30 · حذف: پیش از تأیید چیزی نشد، انصراف اثری نداشت، تأیید حذف کرد';
            END IF;

            -- T31: بازگردانی (حذف نرم) کار کند
            UPDATE crm.organizations SET deleted_at = NULL WHERE code = div_code;
            SELECT count(*) INTO base_err FROM iee1405.co_org_info(div_code);
            IF base_err <> 1 THEN
                fails := fails + 1;
                RAISE NOTICE '❌ T31 · بازگردانی شرکت حذف‌شده کار نکرد';
            ELSE
                RAISE NOTICE '✅ T31 · بازگردانی با یک UPDATE (حذف نرم، نه پاک‌کردن داده)';
            END IF;

            -- پاک‌کردن ردیف‌های آزمایشی
            DELETE FROM iee1405.interviews WHERE org_code = div_code;
            DELETE FROM crm.claims WHERE subject_id = (SELECT id FROM crm.organizations WHERE code = div_code);
            DELETE FROM iee1405.participations WHERE organization_id = (SELECT id FROM crm.organizations WHERE code = div_code);
            -- audit_events عمداً تغییرناپذیر است (تریگر forbid_mutation)؛
            -- ردیف‌های ممیزی آزمون می‌مانند و کسی را اذیت نمی‌کنند.
            DELETE FROM crm.organizations WHERE code = div_code;
        END IF;
    ELSE
        RAISE NOTICE '⏭  T27–T31 رد شد — فایل ۱۱ (کارت مدیریتی) نصب نشده';
    END IF;

    IF fails > 0 THEN
        RAISE EXCEPTION 'آزمون ورودی ربات: % مورد ناموفق', fails;
    END IF;
    RAISE NOTICE '── همهٔ موارد ورودی ربات سبز است ──';
END
$test$;

ROLLBACK;
