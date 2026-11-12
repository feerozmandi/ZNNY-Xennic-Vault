-- ═══════════════════════════════════════════════════════════════════════
-- آزمون پایانی منطق ربات — روی کلاستر محلی
-- اجرا: python3 03_ops/psqlrun.py 03_ops/test_bot_flow.sql
-- ═══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

BEGIN;

-- کاربر آزمایشی با chat_id مشخص
UPDATE crm.users SET bale_chat_id = 900001 WHERE username = 'ahmad';

-- ── ۱) کاربر ناشناس → unauthorized
SELECT 'T1' AS t, status FROM iee1405.bot_dispatch(1, 900999, '/start', '{}'::jsonb);

-- ── ۲) /help
SELECT 'T2' AS t, left(reply_text, 40) AS reply FROM iee1405.bot_dispatch(2, 900001, '/start', '{}'::jsonb);

-- ── ۳) idempotency: همان update_id دوباره
SELECT 'T3' AS t, status FROM iee1405.bot_dispatch(2, 900001, '/start', '{}'::jsonb);

-- ── ۴) /new → نام شرکت
SELECT 'T4' AS t, left(reply_text, 30) AS reply FROM iee1405.bot_dispatch(3, 900001, '/new', '{}'::jsonb);
SELECT 'T5' AS t, left(reply_text, 60) AS reply
  FROM iee1405.bot_dispatch(4, 900001, 'شرکت آزمون تابلو البرز', '{}'::jsonb)
 WHERE status = 'ok' \gset t5_
SELECT 'T6' AS t, code, legal_name FROM crm.organizations WHERE legal_name = 'شرکت آزمون تابلو البرز';

-- ── ۵) دسته با شماره (۱ = TAB_MV) سپس غرفه
SELECT 'T7' AS t, left(reply_text, 50) AS reply FROM iee1405.bot_dispatch(5, 900001, '1', '{}'::jsonb);
SELECT 'T8' AS t, left(reply_text, 80) AS reply FROM iee1405.bot_dispatch(6, 900001, '38-12', '{}'::jsonb);

-- ── ۶) بررسی نتیجه در پایگاه‌داده
SELECT 'T9' AS t, p.hall, p.booth_number, p.confirmed
  FROM iee1405.participations p
  JOIN crm.organizations o ON o.id = p.organization_id
 WHERE o.legal_name = 'شرکت آزمون تابلو البرز';

SELECT 'T10' AS t, cl.attribute, cl.value_text, cl.epistemic_status, cl.is_current
  FROM crm.claims cl
  JOIN crm.organizations o ON o.id = cl.subject_id
 WHERE o.legal_name = 'شرکت آزمون تابلو البرز' AND cl.subject_type = 'organization';

-- ── ۷) نام تکراری → نباید شرکت دوم بسازد
SELECT 'T11a' AS t, left(reply_text, 20) AS reply FROM iee1405.bot_dispatch(70, 900001, '/new', '{}'::jsonb);
SELECT 'T11' AS t, left(reply_text, 90) AS reply
  FROM iee1405.bot_dispatch(7, 900001, 'شرکت آزمون تابلو البرز', '{}'::jsonb);
SELECT 'T12' AS t, count(*) AS orgs_same_name
  FROM crm.organizations WHERE legal_name = 'شرکت آزمون تابلو البرز';

-- ── ۸) دسته نامعتبر (در حالت new_category)
SELECT 'T13' AS t, left(reply_text, 40) AS reply FROM iee1405.bot_dispatch(8, 900001, '۹۹', '{}'::jsonb);
SELECT 'T13b' AS t, left(reply_text, 40) AS reply FROM iee1405.bot_dispatch(81, 900001, '/cancel', '{}'::jsonb);

-- ── ۹) جست‌وجو
SELECT 'T14' AS t, left(reply_text, 80) AS reply
  FROM iee1405.bot_dispatch(9, 900001, '/find آزمون', '{}'::jsonb);
SELECT 'T15' AS t, left(reply_text, 120) AS card
  FROM iee1405.bot_dispatch(10, 900001, '1', '{}'::jsonb);

-- ── ۱۰) مذاکره با اقدام بعدی → باید وظیفه بسازد
SELECT 'T16' AS t, left(reply_text, 120) AS reply
  FROM iee1405.bot_dispatch(11, 900001,
       '/log ' || (SELECT code FROM crm.organizations WHERE legal_name = 'شرکت آزمون تابلو البرز')
       || ' | جلسه با مدیر فنی، نیاز به تابلوی ۲۰kV | ارسال کاتالوگ', '{}'::jsonb);
SELECT 'T17' AS t, count(*) AS interactions
  FROM crm.interactions i JOIN crm.organizations o ON o.id = i.organization_id
 WHERE o.legal_name = 'شرکت آزمون تابلو البرز';
SELECT 'T18' AS t, t.title, t.due_date, t.status
  FROM crm.tasks t JOIN crm.organizations o ON o.id = t.organization_id
 WHERE o.legal_name = 'شرکت آزمون تابلو البرز';

-- ── ۱۱) توانمندی
SELECT 'T19' AS t, left(reply_text, 60) AS reply
  FROM iee1405.bot_dispatch(12, 900001,
       '/cap ' || (SELECT code FROM crm.organizations WHERE legal_name = 'شرکت آزمون تابلو البرز')
       || ' | تولید تابلوی MV تا 36kV', '{}'::jsonb);

-- ── ۱۲) وظیفه مستقل و بازدید
SELECT 'T20' AS t, left(reply_text, 60) AS reply
  FROM iee1405.bot_dispatch(13, 900001,
       '/task ' || (SELECT code FROM crm.organizations WHERE legal_name = 'شرکت آزمون تابلو البرز')
       || ' | تماس با مدیرعامل | 2', '{}'::jsonb);
SELECT 'T21' AS t, left(reply_text, 60) AS reply
  FROM iee1405.bot_dispatch(14, 900001,
       '/visit ' || (SELECT code FROM crm.organizations WHERE legal_name = 'شرکت آزمون تابلو البرز'),
       '{}'::jsonb);

-- ── ۱۳) خلاصه روز
SELECT 'T22' AS t, left(reply_text, 120) AS reply FROM iee1405.bot_dispatch(15, 900001, '/today', '{}'::jsonb);

-- ── ۱۴) کد نامعتبر و دستور ناشناخته
SELECT 'T23' AS t, left(reply_text, 40) AS reply FROM iee1405.bot_dispatch(16, 900001, '/org ORG-999999', '{}'::jsonb);
SELECT 'T24' AS t, left(reply_text, 40) AS reply FROM iee1405.bot_dispatch(17, 900001, 'سلام', '{}'::jsonb);

-- ── ۱۵) نمای کیفیت داده
SELECT 'T25' AS t, dq.orgs_total, dq.orgs_without_contact, dq.claims_without_source, dq.interactions_without_next
  FROM crm.v_data_quality dq;

-- ── ۱۶) نماهای گزارش
SELECT 'T26' AS t, code, legal_name, booth_number, claims_count FROM (
    SELECT o.code, o.legal_name, ov.booth_number, ov.claims_count
      FROM crm.v_company_overview ov JOIN crm.organizations o ON o.id = ov.id
     WHERE o.legal_name = 'شرکت آزمون تابلو البرز') s;

-- ── ۱۷) audit ثبت شده باشد
SELECT 'T27' AS t, ae.action, ae.entity, count(*)
  FROM crm.audit_events ae GROUP BY ae.action, ae.entity ORDER BY 2, 1;

ROLLBACK;
