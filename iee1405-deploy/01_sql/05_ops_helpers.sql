-- ═══════════════════════════════════════════════════════════════════════
-- IEE 1405 — توابع عملیاتی n8n (Ops helpers)
-- هر چیزی که n8n لازم دارد، اینجا به‌صورت تابع تست‌شده فراهم است؛
-- گره‌های n8n فقط این توابع را صدا می‌زنند (بدون منطق در JSON).
-- اجرا: psql -v ON_ERROR_STOP=1 -f 05_ops_helpers.sql
-- ═══════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────
-- 1) وضعیت پایدار سرویس (offset بله، پرچم‌ها)
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS iee1405.bot_state (
    key        text PRIMARY KEY,
    value      text,
    updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO iee1405.bot_state (key, value) VALUES
    ('bale_offset', '0'),
    ('poll_enabled', 'true'),
    ('last_poll_at', NULL),
    ('last_error', NULL),
    ('bale_seen_max', NULL),      -- بزرگ‌ترین update_id که بله در آخرین دریافت داد
    ('bale_batch_ids', NULL),     -- فهرست update_idهای همان دریافت (برای بررسی گم‌شدن)
    ('health_alert_last_at', NULL) -- آخرین هشدار سلامت (بازه سکوت WF-04)
ON CONFLICT (key) DO NOTHING;

COMMENT ON TABLE iee1405.bot_state IS 'وضعیت پایدار سرویس؛ با ری‌استارت n8n از دست نمی‌رود';

-- ─────────────────────────────────────────────────────────────────────
-- 2) گام ۱ دریافت: offset جاری
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION iee1405.poll_offset()
RETURNS bigint LANGUAGE sql STABLE AS $$
    SELECT COALESCE((SELECT value::bigint FROM iee1405.bot_state WHERE key = 'bale_offset'), 0)
$$;

-- گام ۳ بعد از پردازش: جلو بردن offset تا max(update_id)
CREATE OR REPLACE FUNCTION iee1405.poll_advance()
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_max bigint; v_off bigint;
BEGIN
    -- این دو ثبت باید **همیشه** انجام شوند، حتی وقتی هیچ پیام تازه‌ای نیست:
    -- در غیر این صورت «سکوت» در بله شبیه «قطعی» دیده می‌شود.
    -- clock_timestamp نه now(): داخل یک تراکنش now() ثابت است و ترتیب
    -- «خطا بعد از دریافت موفق» قابل تشخیص نمی‌ماند.
    UPDATE iee1405.bot_state SET value = clock_timestamp()::text,
                                 updated_at = clock_timestamp()
     WHERE key = 'last_poll_at';
    -- دریافت موفق یعنی خطای قبلی برطرف شده است
    UPDATE iee1405.bot_state SET value = NULL, updated_at = clock_timestamp()
     WHERE key = 'last_error';

    -- بیشترین شناسه‌ای که **دیده شد** (نه فقط آنچه ذخیره شد)
    SELECT GREATEST(
               COALESCE((SELECT max(u.update_id) FROM iee1405.bot_updates u), 0),
               -- فقط اگر در همین چرخه دسته‌ای دیده شده باشد؛ مقدار کهنه بی‌اثر است
               CASE WHEN COALESCE((SELECT value FROM iee1405.bot_state
                                    WHERE key = 'bale_batch_ids'), '[]') <> '[]'
                    THEN COALESCE((SELECT value::bigint FROM iee1405.bot_state
                                    WHERE key = 'bale_seen_max'), 0)
                    ELSE 0 END
           ) INTO v_max;

    -- اگر آپدیتی گرفته شد ولی هیچ ردیفی برایش ساخته نشد، گم نشود: ثبت می‌شود
    INSERT INTO iee1405.bot_errors (update_id, chat_id, stage, message, detail)
    SELECT b.id, NULL, 'unrecorded',
           'آپدیت گرفته شد ولی در bot_updates ثبت نشد (پردازش ناقص ماند)',
           'offset از این آپدیت گذشت تا طوفان تلاش تکرار نشود'
      FROM (SELECT jsonb_array_elements_text(
                     COALESCE((SELECT value::text FROM iee1405.bot_state
                                WHERE key = 'bale_batch_ids'), '[]')::jsonb)::bigint AS id) b
     WHERE NOT EXISTS (SELECT 1 FROM iee1405.bot_updates u WHERE u.update_id = b.id)
       AND NOT EXISTS (SELECT 1 FROM iee1405.bot_errors e
                        WHERE e.update_id = b.id AND e.stage = 'unrecorded');

    v_off := iee1405.poll_offset();
    IF v_max IS NULL OR v_off >= v_max THEN
        RETURN v_off;
    END IF;
    UPDATE iee1405.bot_state
       SET value = v_max::text, updated_at = clock_timestamp()
     WHERE key = 'bale_offset';
    RETURN v_max;
END $$;

-- بازنشانی آگاهانه: فقط از این راه offset را عقب ببرید. اگر این کار را با
-- UPDATE دستی بکنید، نشانگرهای کمکی (seen_max/batch_ids) کهنه می‌مانند.
CREATE OR REPLACE FUNCTION iee1405.poll_reset(p_offset bigint DEFAULT 0)
RETURNS bigint LANGUAGE plpgsql AS $$
BEGIN
    UPDATE iee1405.bot_state SET value = p_offset::text, updated_at = clock_timestamp()
     WHERE key = 'bale_offset';
    UPDATE iee1405.bot_state SET value = NULL, updated_at = clock_timestamp()
     WHERE key = 'bale_seen_max';
    UPDATE iee1405.bot_state SET value = '[]', updated_at = clock_timestamp()
     WHERE key = 'bale_batch_ids';
    RETURN p_offset;
END $$;

COMMENT ON FUNCTION iee1405.poll_reset IS 'بازخوانی از شناسه مشخص؛ نشانگرهای کمکی را هم صفر می‌کند';

-- ضربان: «هر ۲۰ ثانیه یک بار تلاش کردم» — مستقل از موفقیت یا شکست درخواست.
-- چرا جدا از poll_advance؟ چون wenn شبکه/بله قطع باشد و درخواست معلق بماند،
-- poll_advance هرگز اجرا نمی‌شد و تازگی زمان با «توقف گردش‌کار» اشتباه می‌شد.
CREATE OR REPLACE FUNCTION iee1405.poll_heartbeat()
RETURNS timestamptz LANGUAGE plpgsql AS $$
DECLARE v_now timestamptz := clock_timestamp();
BEGIN
    UPDATE iee1405.bot_state SET value = v_now::text, updated_at = v_now
     WHERE key = 'last_poll_at';
    RETURN v_now;
END $$;

-- بازرسی پاسخ بله پیش از پردازش:
--   بله برای بسیاری از خطاها (توکن اشتباه، پارامتر بد) کد ۲۰۰ با {"ok":false}
--   برمی‌گرداند. بدون این تابع، چنین خطایی «هیچ آپدیتی نبود» تلقی می‌شد و
--   هیچ‌جا ثبت نمی‌شد. پاسخ عیناً برمی‌گردد تا ادامه زنجیره تغییر نکند.
CREATE OR REPLACE FUNCTION iee1405.poll_watch(p_response jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
    IF p_response IS NULL THEN
        PERFORM iee1405.record_poll_error('{"error":{"message":"پاسخ خالی از بله"}}');
        RETURN COALESCE(p_response, '{}'::jsonb);
    END IF;

    -- شناسه‌های همین دریافت را ثبت می‌کنیم. چرا؟ جلو بردن offset نباید به
    -- موفقیت گره «پردازش» گره‌خورده باشد؛ وگرنه یک آپدیت مشکل‌دار باعث می‌شود
    -- همان دسته هر ۲۰ ثانیه دوباره گرفته شود (طوفان تلاش و پاسخ تکراری).
    IF jsonb_typeof(p_response -> 'result') = 'array' THEN
        UPDATE iee1405.bot_state
           SET value = COALESCE((
                   SELECT jsonb_agg((x ->> 'update_id')::bigint ORDER BY (x ->> 'update_id')::bigint)::text
                     FROM jsonb_array_elements(p_response -> 'result') x
                    WHERE (x ->> 'update_id') ~ '^[0-9]+$'), '[]'),
               updated_at = clock_timestamp()
         WHERE key = 'bale_batch_ids';
        -- بازنویسی می‌شود (نه انباره): اگر offset دستی به عقب برگردد، این مقدار
        -- قدیمی جلوی آن را نمی‌گیرد.
        UPDATE iee1405.bot_state
           SET value = COALESCE((SELECT max((x ->> 'update_id')::bigint)
                                   FROM jsonb_array_elements(p_response -> 'result') x
                                  WHERE (x ->> 'update_id') ~ '^[0-9]+$'), 0)::text,
               updated_at = clock_timestamp()
         WHERE key = 'bale_seen_max';
    END IF;

    IF (p_response ->> 'ok') = 'false' THEN
        PERFORM iee1405.record_poll_error(
            jsonb_build_object(
                'error', jsonb_build_object(
                    'message',     COALESCE(p_response ->> 'description', 'ok=false'),
                    'description', 'پاسخ بله ناموفق بود (HTTP 200)',
                    'httpCode',    COALESCE(p_response ->> 'error_code', '—'),
                    'node',        jsonb_build_object('name', '📥 دریافت پیام‌ها')
                )
            )::text);
    END IF;
    RETURN p_response;
END $$;

-- اقدام خودترمیمی: اگر دریافت واقعاً مرده باشد (نه فقط کند/خطا)،
-- گردش‌کار ۰۱ را دوباره فعال می‌کنیم. تلاش‌ها محدود و ثبت‌شده است تا
-- حلقه بی‌پایان نشود. WF-04 هر ۳۰ دقیقه یک بار این تابع را صدا می‌زند.
CREATE OR REPLACE FUNCTION iee1405.recover_if_dead(
    p_stale interval DEFAULT '15 minutes',
    p_max_attempts int DEFAULT 6,
    p_window interval DEFAULT '6 hours'
) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE
    v_poll  timestamptz := (SELECT value::timestamptz FROM iee1405.bot_state WHERE key = 'last_poll_at');
    v_tries bigint;
BEGIN
    -- فقط وقتی هیچ ضربانی در بازه نرسیده باشد
    IF v_poll IS NOT NULL AND v_poll > now() - p_stale THEN
        RETURN false;
    END IF;

    SELECT count(*) INTO v_tries
      FROM iee1405.bot_errors
     WHERE stage = 'self_recovery'
       AND occurred_at > now() - p_window;

    IF v_tries >= p_max_attempts THEN
        -- یک بار در بازه هشدار بده، بعد ساکت شو (نه حلقه بی‌پایان)
        IF NOT EXISTS (SELECT 1 FROM iee1405.bot_errors
                        WHERE stage = 'self_recovery_gave_up'
                          AND occurred_at > now() - p_window) THEN
            INSERT INTO iee1405.bot_errors (update_id, chat_id, stage, message, detail)
            VALUES (0, NULL, 'self_recovery_gave_up',
                    'خودترمیمی ' || v_tries || ' بار تلاش کرد و موفق نشد؛ دخالت دستی لازم است',
                    'wf-04 · bash 03_ops/diagnose_n8n.sh');
        END IF;
        RETURN false;
    END IF;

    INSERT INTO iee1405.bot_errors (update_id, chat_id, stage, message, detail)
    VALUES (0, NULL, 'self_recovery',
            'دریافت پیام‌ها مرده بود؛ تلاش ' || (v_tries + 1) || ' برای فعال‌سازی دوباره',
            'wf-04 · bash 03_ops/diagnose_n8n.sh');
    -- ضربان را هم جلو می‌بریم تا در همان بازه دوباره تلاش نشود
    UPDATE iee1405.bot_state SET value = clock_timestamp()::text, updated_at = clock_timestamp()
     WHERE key = 'last_poll_at' AND (value IS NULL OR value::timestamptz < now() - p_stale);
    RETURN true;
END $$;

-- «آیا دریافت پیام‌ها سالم است؟» — یک نقطه حقیقت برای همه نماها و هشدارها
CREATE OR REPLACE FUNCTION iee1405.poll_is_stale(p_grace interval DEFAULT '10 minutes')
RETURNS boolean LANGUAGE sql STABLE AS $$
    WITH s AS (
        SELECT (SELECT value::timestamptz FROM iee1405.bot_state WHERE key = 'last_poll_at') AS poll,
               (SELECT value::timestamptz FROM iee1405.bot_state WHERE key = 'last_error')   AS err
    )
    SELECT (poll IS NULL)
        OR (poll < now() - p_grace)
        OR (err IS NOT NULL AND err > poll)
      FROM s
$$;

-- خطاهای «واقعاً باز»: خطای getUpdates با دریافت موفق بعدی پاک می‌شود،
-- وگرنه یک قطعی کوتاه تا یک ساعت هشدار تکراری می‌فرستاد.
CREATE OR REPLACE FUNCTION iee1405.recent_error_count(p_window interval DEFAULT '1 hour')
RETURNS bigint LANGUAGE sql STABLE AS $$
    SELECT count(*)
      FROM iee1405.bot_errors e
     WHERE e.occurred_at > now() - p_window
       AND (e.stage <> 'bale_getupdates'
            OR e.occurred_at > COALESCE((SELECT value::timestamptz
                                           FROM iee1405.bot_state
                                          WHERE key = 'last_poll_at'),
                                        '-infinity'::timestamptz))
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 3) پیام پایان روز (WF-03)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION iee1405.digest_text()
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE d record; v_txt text; v_top text; v_over int;
BEGIN
    SELECT * INTO d FROM iee1405.v_today_digest;

    SELECT count(*) INTO v_over FROM crm.tasks
     WHERE status = 'open' AND due_date < current_date;

    SELECT string_agg(x.line, E'\n') INTO v_top FROM (
        SELECT o.code || ' ' || left(coalesce(o.display_name, o.legal_name), 26) ||
               ' — پیگیری: ' || left(t.title, 30) AS line
          FROM crm.tasks t JOIN crm.organizations o ON o.id = t.organization_id
         WHERE t.status = 'open' AND t.due_date <= current_date + 2
         ORDER BY t.due_date, t.priority DESC
         LIMIT 5) x;

    v_txt :=
        E'📊 خلاصه ' || to_char(now() AT TIME ZONE 'Asia/Tehran', 'YYYY-MM-DD') || E'\n' ||
        E'شرکت جدید امروز: ' || d.orgs_today || E'\n' ||
        E'مذاکره امروز: '     || d.interactions_today || E'\n' ||
        E'پیگیری جدید: '      || d.tasks_today || E'\n' ||
        E'فایل امروز: '       || d.files_today || E'\n' ||
        E'مجموع شرکت‌ها: '     || d.orgs_total;

    IF v_over > 0 THEN
        v_txt := v_txt || E'\n⚠️ پیگیری گذشته از موعد: ' || v_over;
    END IF;
    IF v_top IS NOT NULL THEN
        v_txt := v_txt || E'\n\n⏭ نزدیک‌ترین پیگیری‌ها:\n' || v_top;
    END IF;
    RETURN v_txt;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 4) یادآور پیگیری‌ها (WF-02) — یک ردیف به‌ازای هر گیرنده
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION iee1405.reminder_items()
RETURNS TABLE (chat_id bigint, actor text, text_body text)
LANGUAGE sql STABLE AS $$
    WITH due AS (
        SELECT t.assignee AS actor,
               o.code, coalesce(o.display_name, o.legal_name) AS name,
               t.title, t.due_date,
               (t.due_date - current_date) AS days_left
          FROM crm.tasks t
          LEFT JOIN crm.organizations o ON o.id = t.organization_id
         WHERE t.status = 'open'
           AND t.due_date <= current_date + 3
    )
    SELECT u.bale_chat_id,
           d.actor,
           E'⏰ پیگیری‌های باز تا ۳ روز آینده\n\n' ||
           string_agg(
             CASE WHEN d.days_left < 0
                  THEN '🔴 ' || abs(d.days_left) || ' روز گذشته'
                  WHEN d.days_left = 0 THEN '🟠 امروز'
                  ELSE '🟡 ' || d.days_left || ' روز' END
             || ' — ' || coalesce(d.code, '—') || ' ' || left(coalesce(d.name, ''), 24)
             || E'\n   ' || left(d.title, 60),
             E'\n' ORDER BY d.due_date)
      FROM due d
      JOIN crm.users u ON u.username = d.actor AND u.bale_chat_id IS NOT NULL AND u.is_active
     GROUP BY u.bale_chat_id, d.actor
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 5) گیرنده گزارش مدیریتی
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION iee1405.owner_chat_ids()
RETURNS TABLE (chat_id bigint) LANGUAGE sql STABLE AS $$
    SELECT u.bale_chat_id FROM crm.users u
     WHERE u.role IN ('owner', 'manager') AND u.bale_chat_id IS NOT NULL AND u.is_active
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 6) سلامت سیستم (WF-04): یک ردیف متن، آماده ارسال
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION iee1405.health_text()
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_poll   timestamptz;
    v_dq     record;
    v_pg     text;
    v_size   text;
    v_issues text := '';
BEGIN
    v_poll := (SELECT value::timestamptz FROM iee1405.bot_state WHERE key = 'last_poll_at');
    SELECT * INTO v_dq FROM crm.v_data_quality;
    v_pg   := current_setting('server_version');
    v_size := pg_size_pretty(pg_database_size(current_database()));

    IF v_poll IS NULL OR v_poll < now() - interval '10 minutes' THEN
        v_issues := v_issues || E'\n⚠️ دریافت پیام‌های بله در ۱۰ دقیقه گذشته اجرا نشده است.';
    END IF;
    IF (SELECT value::timestamptz FROM iee1405.bot_state WHERE key = 'last_error')
       > COALESCE(v_poll, '-infinity'::timestamptz) THEN
        v_issues := v_issues || E'\n🛑 آخرین درخواست getUpdates خطا داد: ' ||
            COALESCE((SELECT left(message, 120) FROM iee1405.bot_errors
                       WHERE stage = 'bale_getupdates'
                       ORDER BY occurred_at DESC LIMIT 1), 'نامشخص');
    END IF;
    IF iee1405.recent_error_count(interval '1 hour') > 0 THEN
        v_issues := v_issues || E'\n⚠️ خطای باز ربات: ' ||
                    iee1405.recent_error_count(interval '1 hour');
    END IF;
    IF v_dq.tasks_overdue > 0 THEN
        v_issues := v_issues || E'\n⚠️ پیگیری گذشته از موعد: ' || v_dq.tasks_overdue;
    END IF;

    IF v_issues = '' THEN
        RETURN '✅ سامانه سالم است' || E'\n' ||
               'PostgreSQL ' || v_pg || ' · حجم ' || v_size || E'\n' ||
               'شرکت‌ها: ' || v_dq.orgs_total ||
               ' · ادعا بدون منبع: ' || v_dq.claims_without_source ||
               ' · آخرین دریافت: ' || coalesce(to_char(v_poll AT TIME ZONE 'Asia/Tehran', 'MM-DD HH24:MI'), '—');
    END IF;
    RETURN '🔎 وضعیت سامانه' || E'\n' ||
           'PostgreSQL ' || v_pg || ' · حجم ' || v_size || v_issues;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 7) ورود/خروج کاربر (فعال‌سازی گوشی دوم با /whoami)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION iee1405.register_new_chat(p_chat_id bigint, p_name text DEFAULT NULL)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO iee1405.bot_errors (update_id, chat_id, stage, message, detail)
    VALUES (0, p_chat_id, 'registration_request',
            'درخواست دسترسی از chat_id جدید', p_name)
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 8) هشدار سلامت (WF-04) — فقط وقتی مشکل هست ردیف برمی‌گرداند
--    (اگر سالم باشد هیچ ردیفی نیست → پیامی ارسال نمی‌شود)
-- ─────────────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────────────
-- نگهبان واحد WF-04: خودترمیمی + هشدار با فاصله اجباری
--
-- دو باگ واقعی که این تابع می‌بندد:
--  ۱) WF-04 قبلاً «WITH rec AS (SELECT recover_if_dead()) SELECT ...» بود.
--     PostgreSQL کات‌های بدون ارجاع را هرس می‌کند (آزمون‌شده روی ۱۶.۲)، پس
--     recover_if_dead هرگز اجرا نمی‌شد و خودترمیمی مرده بود. حالا فراخوانی
--     داخل همین تابع و صریح است، نه در کات بی‌استفاده.
--  ۲) هشدار فاصله نداشت: هر ۳۰ دقیقه همان پیام تکرار می‌شد (۴۸ پیام در روز).
--     حالا یک claim اتمی روی bot_state، حداکثر یک هشدار در هر بازه.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION iee1405.health_watch(
    p_min_interval interval DEFAULT '3 hours'
) RETURNS TABLE (chat_id bigint, text_body text)
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_recovered boolean;
    v_claimed   boolean;
    v_errors    int;
BEGIN
    -- گام ۱: خودترمیمی (همیشه، حتی اگر هشدار در کار نباشد)
    v_recovered := iee1405.recover_if_dead();
    IF v_recovered THEN
        RAISE NOTICE 'iee1405.health_watch: گردش‌کار دریافت خودترمیمی شد';
    END IF;

    -- گام ۲: آیا اصلاً مشکلی هست؟
    SELECT iee1405.recent_error_count(interval '1 hour') INTO v_errors;
    IF NOT (v_errors > 0
            OR iee1405.poll_is_stale(interval '2 hours')
            OR (SELECT count(*) FROM crm.tasks
                 WHERE status = 'open' AND due_date < current_date) > 10) THEN
        RETURN;   -- سالم است: هیچ پیامی
    END IF;

    -- گام ۳: claim اتمی فاصله. INSERT..ON CONFLICT..WHERE در یک دستور، پس دو
    -- اجرای هم‌زمان نمی‌توانند هر دو claim کنند.
    INSERT INTO iee1405.bot_state (key, value, updated_at)
    VALUES ('health_alert_last_at', clock_timestamp()::text, clock_timestamp())
    ON CONFLICT (key) DO UPDATE
       SET value = clock_timestamp()::text, updated_at = clock_timestamp()
     WHERE iee1405.bot_state.value IS NULL
        OR iee1405.bot_state.value::timestamptz < clock_timestamp() - p_min_interval
    RETURNING true INTO v_claimed;

    IF v_claimed IS NULL THEN
        RETURN;   -- هنوز در بازه سکوت هستیم
    END IF;

    RETURN QUERY
    SELECT o.chat_id, iee1405.health_text() FROM iee1405.owner_chat_ids() o;
END $$;

COMMENT ON FUNCTION iee1405.health_watch IS
'خودترمیمی + هشدار سلامت با فاصله حداقل ۳ ساعت؛ جای health_alert_rows در WF-04';

-- بازنشانی بازه سکوت (برای آزمون یا وقتی می‌خواهید هشدار بعدی فوری بیاید)
CREATE OR REPLACE FUNCTION iee1405.health_alert_reset()
RETURNS void LANGUAGE sql AS $$
    UPDATE iee1405.bot_state SET value = NULL, updated_at = clock_timestamp()
     WHERE key = 'health_alert_last_at';
$$;

CREATE OR REPLACE FUNCTION iee1405.health_alert_rows()
RETURNS TABLE (chat_id bigint, text_body text)
LANGUAGE sql STABLE AS $$
    WITH issues AS (
        SELECT
            iee1405.recent_error_count(interval '1 hour')                                AS errors_1h,
            ((SELECT value::timestamptz FROM iee1405.bot_state
               WHERE key = 'last_poll_at'))                                     AS last_poll,
            ((SELECT count(*) FROM crm.tasks
               WHERE status = 'open' AND due_date < current_date))              AS overdue
    )
    SELECT o.chat_id, iee1405.health_text()
      FROM iee1405.owner_chat_ids() o, issues i
     WHERE i.errors_1h > 0
        OR iee1405.poll_is_stale(interval '2 hours')
        OR i.overdue > 10
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 9) نقش دیتابیس برای n8n (کم‌دسترسی، بدون DDL)
--    اجرا با کاربر superuser: psql -f 05_ops_helpers.sql سپس 06_roles.sql
-- ─────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────
-- 10) تحویل تضمین‌شده پاسخ‌ها (at-least-once)
--     پاسخ در پایگاه‌داده می‌ماند تا ارسال موفق شود؛ اگر ارسال به بله
--     شکست بخورد، در اجرای بعدی دوباره تلاش می‌شود. هیچ پاسخی گم نمی‌شود.
-- ─────────────────────────────────────────────────────────────────────
ALTER TABLE iee1405.bot_updates ADD COLUMN IF NOT EXISTS delivered_at timestamptz;
ALTER TABLE iee1405.bot_updates ADD COLUMN IF NOT EXISTS claimed_at timestamptz;
ALTER TABLE iee1405.bot_updates ADD COLUMN IF NOT EXISTS reply_markup jsonb;

-- مهاجرت: جدول‌های قدیمی با CHECK بدون 'sending'/'failed' ساخته شده‌اند و
-- CREATE TABLE IF NOT EXISTS آن را اصلاح نمی‌کند؛ پس constraint را بازسازی می‌کنیم.
ALTER TABLE iee1405.bot_updates DROP CONSTRAINT IF EXISTS bot_updates_status_check;
ALTER TABLE iee1405.bot_updates ADD CONSTRAINT bot_updates_status_check
    CHECK (status IN ('received', 'processed', 'skipped', 'error', 'sending', 'failed'));
CREATE INDEX IF NOT EXISTS bot_updates_pending_idx
    ON iee1405.bot_updates (update_id)
 WHERE delivered_at IS NULL AND reply_text IS NOT NULL;

-- صف پاسخ‌های ارسالی: claim اتمیک با FOR UPDATE SKIP LOCKED.
-- چرا؟ دو اجرای هم‌زمان گردش‌کار (n8n هر چند ثانیه یک اجرا شروع می‌کند و
-- منتظر پایان اجرای قبلی نمی‌ماند) قبلاً می‌توانستند همان ردیف‌های «ارسال‌نشده»
-- را هر دو select کنند و همان پیام را دو بار (چند ثانیه پشت سر هم) بفرستند.
-- با SKIP LOCKED هر ردیف فقط یک‌بار claim می‌شود و status آن 'sending' می‌شود;
-- mark_sent بعد از ارسال موفق delivered_at را ست می‌کند و در ارسال ناموفق
-- status را به 'processed' برمی‌گرداند تا در چرخه بعد دوباره تلاش شود.
-- امضای تابع تغییر کرده (ستون reply_markup اضافه شده)؛ CREATE OR REPLACE
-- نمی‌تواند نوع خروجی را عوض کند، پس先 DROP می‌کنیم (idempotent).
DROP FUNCTION IF EXISTS iee1405.pending_replies(int);

CREATE OR REPLACE FUNCTION iee1405.pending_replies(p_limit int DEFAULT 20)
RETURNS TABLE (update_id bigint, chat_id bigint, text_body text, attempt int, reply_markup jsonb)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    UPDATE iee1405.bot_updates u
       SET status = 'sending', claimed_at = clock_timestamp()
      FROM (SELECT u2.update_id
              FROM iee1405.bot_updates u2
             WHERE u2.reply_text IS NOT NULL
               AND u2.delivered_at IS NULL
               AND (u2.status IN ('received', 'processed', 'skipped')
                    -- claimهای کهنه (اجرای نیمه‌کاره) دوباره در صف قرار می‌گیرند
                    OR (u2.status = 'sending'
                        AND u2.claimed_at < clock_timestamp() - interval '90 seconds'))
             ORDER BY u2.update_id
             LIMIT p_limit
             FOR UPDATE OF u2 SKIP LOCKED) c
     WHERE u.update_id = c.update_id
    RETURNING u.update_id, u.chat_id, u.reply_text,
              COALESCE((u.raw -> '_attempts')::int, 0),
              COALESCE(u.reply_markup, iee1405.menu_kb());
END $$;

-- ثبت نتیجه ارسال. چرا پاسخ بله هم ورودی است؟ چون «ارسال شد» را نباید از
-- متن خطای n8n حدس زد: بله برای خیلی از خطاها کد ۲۰۰ با ok:false می‌دهد.
-- اگر ارسال ناموفق باشد، پیام در صف می‌ماند و در چرخه بعد دوباره تلاش می‌شود؛
-- بعد از ۵ تلاش رها می‌شود تا حلقه بی‌پایان ارسال رخ ندهد (و در bot_errors می‌ماند).
CREATE OR REPLACE FUNCTION iee1405.mark_sent(p_update_id bigint, p_response jsonb DEFAULT NULL)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    v_ok       boolean := COALESCE((p_response ->> 'ok')::boolean, false);
    v_attempts int;
    v_code     text;
BEGIN
    IF p_update_id IS NULL THEN
        RETURN 'no-id';
    END IF;

    IF v_ok THEN
        UPDATE iee1405.bot_updates
           SET delivered_at = clock_timestamp(), status = 'processed'
         WHERE update_id = p_update_id;
        RETURN 'delivered';
    END IF;

    v_code := COALESCE(p_response #>> '{error,status}',
                       p_response ->> 'error_code',
                       p_response ->> 'message',
                       '?');
    -- ارسال ناموفق: دوباره به صف برمی‌گردد ('processed') تا چرخه بعد retry شود
    UPDATE iee1405.bot_updates
       SET raw = jsonb_set(COALESCE(raw, '{}'::jsonb), '{_attempts}',
                           to_jsonb(COALESCE((raw ->> '_attempts')::int, 0) + 1), true),
           status = 'processed', claimed_at = NULL
     WHERE update_id = p_update_id
     RETURNING COALESCE((raw ->> '_attempts')::int, 0) INTO v_attempts;

    INSERT INTO iee1405.bot_errors (update_id, chat_id, stage, message, detail)
    SELECT p_update_id, u.chat_id, 'send',
           'ارسال به بله ناموفق بود (کد ' || COALESCE(v_code, '?') || ')',
           left(COALESCE(p_response::text, '—'), 400)
      FROM iee1405.bot_updates u
     WHERE u.update_id = p_update_id;

    IF COALESCE(v_attempts, 0) >= 5 THEN
        UPDATE iee1405.bot_updates SET delivered_at = clock_timestamp()
         WHERE update_id = p_update_id;
        RETURN 'gave-up';
    END IF;
    RETURN 'retry';
END $$;

COMMENT ON FUNCTION iee1405.mark_sent IS 'ثبت ارسال بر اساس پاسخ واقعی بله؛ تلاش محدود تا حلقه بی‌پایان نشود';

CREATE OR REPLACE FUNCTION iee1405.mark_delivered(p_update_id bigint)
RETURNS void LANGUAGE sql AS $$
    UPDATE iee1405.bot_updates SET delivered_at = now() WHERE update_id = p_update_id
$$;

COMMENT ON FUNCTION iee1405.pending_replies IS 'claim اتمیک پاسخ‌های ارسال‌نشده (SKIP LOCKED)؛ مبنای تضمین تحویل بدون ارسال تکراری';

-- ─────────────────────────────────────────────────────────────────────
-- 11) ثبت خطای دریافت از بله
--     اگر getUpdates شکست بخورد، گردش‌کار این را ثبت می‌کند تا «سکوت»
--     با «قطعی» اشتباه گرفته نشود.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION iee1405.record_poll_error(p_message text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_txt text := COALESCE(p_message, 'unknown error'); v_json jsonb; v_node text;
BEGIN
    -- ورودی ممکن است JSON کامل خروجی خطای n8n باشد؛ پیام و نام گره از آن
    -- استخراج می‌شود تا در /status علت واقعی دیده شود، نه یک رشته نامفهوم.
    IF left(btrim(v_txt), 1) IN ('{', '[') THEN
        BEGIN
            v_json := v_txt::jsonb;
        EXCEPTION WHEN others THEN
            v_json := NULL;
        END;
        IF v_json IS NOT NULL THEN
            v_node := COALESCE(v_json #>> '{error,node,name}', v_json ->> 'lastNodeExecuted');
            v_txt  := COALESCE(
                        v_json #>> '{error,message}',
                        v_json #>> '{resultData,error,message}',
                        v_json ->> 'message',
                        v_txt);
            IF v_json #>> '{error,description}' IS NOT NULL THEN
                v_txt := v_txt || ' — ' || (v_json #>> '{error,description}');
            END IF;
            IF v_json #>> '{error,httpCode}' IS NOT NULL THEN
                v_txt := v_txt || ' (HTTP ' || (v_json #>> '{error,httpCode}') || ')';
            END IF;
        END IF;
    END IF;

    INSERT INTO iee1405.bot_errors (update_id, chat_id, stage, message, detail)
    VALUES (0, NULL, 'bale_getupdates', left(v_txt, 500),
            left(COALESCE('wf-01 · ' || v_node, 'wf-01'), 200));
    UPDATE iee1405.bot_state SET value = clock_timestamp()::text,
                                 updated_at = clock_timestamp()
     WHERE key = 'last_error';
END $$;


