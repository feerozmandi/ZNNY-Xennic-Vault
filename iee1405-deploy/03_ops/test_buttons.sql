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
    ('btn-7', 'آزمون دکمه ۷', 'owner', 990007, true)
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

    IF fails > 0 THEN
        RAISE EXCEPTION 'آزمون ورودی ربات: % مورد ناموفق', fails;
    END IF;
    RAISE NOTICE '── همهٔ موارد ورودی ربات سبز است ──';
END
$test$;

ROLLBACK;
