-- ═══════════════════════════════════════════════════════════════════════
-- IEE 1405 — نماهای گزارش
-- نماها مرجع داده نیستند؛ فقط خواندن برای ربات، پنل و خروجی.
-- idempotent: CREATE OR REPLACE VIEW
-- اجرا: psql -v ON_ERROR_STOP=1 -f 03_views.sql
-- ═══════════════════════════════════════════════════════════════════════

-- ── نمای کلی شرکت (یک ردیف به‌ازای شرکت) ──
CREATE OR REPLACE VIEW crm.v_company_overview AS
SELECT
    o.id,
    o.code,
    o.legal_name,
    o.display_name,
    o.org_type,
    o.initial_group,
    o.effective_group,
    o.score,
    o.status,
    o.city,
    o.website,
    p.hall,
    p.booth_number,
    (SELECT count(*) FROM crm.contacts c
      WHERE c.organization_id = o.id AND c.deleted_at IS NULL)          AS contacts_count,
    (SELECT count(*) FROM crm.products pr
      WHERE pr.organization_id = o.id AND pr.deleted_at IS NULL)        AS products_count,
    (SELECT count(*) FROM crm.interactions i
      WHERE i.organization_id = o.id)                                   AS interactions_count,
    (SELECT count(*) FROM crm.claims cl
      WHERE cl.subject_type = 'organization' AND cl.subject_id = o.id
        AND cl.is_current)                                              AS claims_count,
    (SELECT count(*) FROM crm.claims cl
      WHERE cl.subject_type = 'organization' AND cl.subject_id = o.id
        AND cl.is_current AND cl.source_id IS NOT NULL)                 AS claims_sourced,
    (SELECT max(i.occurred_at) FROM crm.interactions i
      WHERE i.organization_id = o.id)                                   AS last_interaction_at,
    (SELECT min(t.due_date) FROM crm.tasks t
      WHERE t.organization_id = o.id AND t.status = 'open')             AS next_task_due,
    o.created_at,
    o.updated_at,
    o.version
FROM crm.organizations o
LEFT JOIN iee1405.exhibitions ex ON ex.code = 'IEE1405'
LEFT JOIN iee1405.participations p
       ON p.organization_id = o.id AND p.exhibition_id = ex.id
WHERE o.deleted_at IS NULL;

COMMENT ON VIEW crm.v_company_overview IS 'نمای یک‌ردیفی هر شرکت با شمارش‌ها و آخرین وضعیت';

-- ── وظایف باز ──
CREATE OR REPLACE VIEW crm.v_open_tasks AS
SELECT
    t.id,
    t.code,
    t.title,
    t.due_date,
    t.priority,
    t.assignee,
    t.status,
    (t.due_date - current_date)                AS days_left,
    o.code                                      AS org_code,
    o.legal_name                                AS org_name
FROM crm.tasks t
LEFT JOIN crm.organizations o ON o.id = t.organization_id
WHERE t.status = 'open';

-- ── ثبت روز نمایشگاه ──
CREATE OR REPLACE VIEW iee1405.v_visit_log AS
SELECT
    v.code,
    v.visited_at,
    o.code        AS org_code,
    o.legal_name  AS org_name,
    p.hall,
    p.booth_number,
    v.by_user,
    v.outcome,
    v.duration_min
FROM iee1405.visits v
JOIN crm.organizations o      ON o.id = v.organization_id
JOIN iee1405.exhibitions ex   ON ex.id = v.exhibition_id
LEFT JOIN iee1405.participations p
       ON p.organization_id = o.id AND p.exhibition_id = ex.id
ORDER BY v.visited_at DESC;

-- ── کیفیت داده (شاخص‌های بازبینی شبانه — PRJ-IEE-012) ──
CREATE OR REPLACE VIEW crm.v_data_quality AS
SELECT
    (SELECT count(*) FROM crm.organizations WHERE deleted_at IS NULL)                       AS orgs_total,
    (SELECT count(*) FROM crm.organizations o WHERE o.deleted_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM crm.contacts c
                        WHERE c.organization_id = o.id AND c.deleted_at IS NULL))           AS orgs_without_contact,
    (SELECT count(*) FROM crm.organizations WHERE deleted_at IS NULL
        AND effective_group IS NULL)                                                        AS orgs_without_group,
    (SELECT count(*) FROM crm.claims WHERE is_current AND source_id IS NULL)                AS claims_without_source,
    (SELECT count(*) FROM crm.interactions i WHERE i.next_action IS NULL)                   AS interactions_without_next,
    (SELECT count(*) FROM crm.tasks WHERE status = 'open' AND due_date < current_date)       AS tasks_overdue,
    (SELECT count(*) FROM crm.attachments WHERE linked_id IS NULL)                           AS files_unlinked;

-- ── خلاصه روز برای پیام پایان روز ──
CREATE OR REPLACE VIEW iee1405.v_today_digest AS
SELECT
    (SELECT count(*) FROM crm.organizations
      WHERE created_at::date = current_date)                       AS orgs_today,
    (SELECT count(*) FROM crm.interactions
      WHERE occurred_at::date = current_date)                      AS interactions_today,
    (SELECT count(*) FROM crm.tasks
      WHERE created_at::date = current_date)                       AS tasks_today,
    (SELECT count(*) FROM crm.attachments
      WHERE created_at::date = current_date)                       AS files_today,
    (SELECT count(*) FROM crm.organizations WHERE deleted_at IS NULL) AS orgs_total;

-- ── خروجی استاندارد Excel/CSV ──
CREATE OR REPLACE VIEW crm.v_export_companies AS
SELECT
    o.code,
    o.legal_name,
    o.display_name,
    o.org_type,
    o.initial_group,
    o.effective_group,
    o.score,
    o.city,
    o.website,
    o.phone_main,
    o.email_main,
    p.hall,
    p.booth_number,
    (SELECT string_agg(c.full_name || coalesce(' (' || c.role_title || ')', ''), ' | ')
       FROM crm.contacts c
      WHERE c.organization_id = o.id AND c.deleted_at IS NULL)     AS contacts,
    (SELECT string_agg(pr.name, ' | ')
       FROM crm.products pr
      WHERE pr.organization_id = o.id AND pr.deleted_at IS NULL)   AS products,
    (SELECT cl.value_text FROM crm.claims cl
      WHERE cl.subject_type = 'organization' AND cl.subject_id = o.id
        AND cl.is_current AND cl.attribute = 'capability.summary'
      LIMIT 1)                                                      AS capability_summary,
    (SELECT max(i.occurred_at) FROM crm.interactions i
      WHERE i.organization_id = o.id)                               AS last_interaction_at,
    (SELECT min(t.due_date) FROM crm.tasks t
      WHERE t.organization_id = o.id AND t.status = 'open')         AS next_task_due,
    o.notes_general,
    o.created_at
FROM crm.organizations o
LEFT JOIN iee1405.participations p
       ON p.organization_id = o.id
      AND p.exhibition_id = (SELECT id FROM iee1405.exhibitions WHERE code = 'IEE1405')
WHERE o.deleted_at IS NULL;
