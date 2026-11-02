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
    ('last_error', NULL)
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

    SELECT max(u.update_id) INTO v_max FROM iee1405.bot_updates u;
    v_off := iee1405.poll_offset();
    IF v_max IS NULL OR v_off >= v_max THEN
        RETURN v_off;
    END IF;
    UPDATE iee1405.bot_state
       SET value = v_max::text, updated_at = clock_timestamp()
     WHERE key = 'bale_offset';
    RETURN v_max;
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
CREATE INDEX IF NOT EXISTS bot_updates_pending_idx
    ON iee1405.bot_updates (update_id)
 WHERE delivered_at IS NULL AND reply_text IS NOT NULL;

CREATE OR REPLACE FUNCTION iee1405.pending_replies(p_limit int DEFAULT 20)
RETURNS TABLE (update_id bigint, chat_id bigint, text_body text, attempt int)
LANGUAGE sql STABLE AS $$
    SELECT u.update_id, u.chat_id, u.reply_text,
           COALESCE((u.raw -> '_attempts')::int, 0)
      FROM iee1405.bot_updates u
     WHERE u.reply_text IS NOT NULL
       AND u.delivered_at IS NULL
       AND u.status <> 'duplicate'
     ORDER BY u.update_id
     LIMIT p_limit
$$;

CREATE OR REPLACE FUNCTION iee1405.mark_delivered(p_update_id bigint)
RETURNS void LANGUAGE sql AS $$
    UPDATE iee1405.bot_updates SET delivered_at = now() WHERE update_id = p_update_id
$$;

COMMENT ON FUNCTION iee1405.pending_replies IS 'پاسخ‌های ارسال‌نشده؛ مبنای تضمین تحویل';

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


