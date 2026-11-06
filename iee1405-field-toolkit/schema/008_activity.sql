-- 008_activity.sql — «نوع فعالیت» شرکت در پایگاه و روی کارت
--
-- چرا؟ ستون «نوع فعالیت» در گزارش برق‌پا برای هر شرکت پر است (تولید /
-- بازرگانی / خدمات) و `import_barghpa.py` آن را از نسخهٔ اول می‌شناخت
-- (کلید ALIASES با نام «type»)، ولی **هیچ‌جا ذخیره نمی‌شد**. یعنی داده در
-- فایل بود و در پایگاه نبود؛ روی کارت هم دیده نمی‌شد. در بازدید، اولین
-- چیزی که از یک غرفه می‌خواهیم بدانیم همین است.
--
-- قاعده: همان مقداری که در منبع آمده ذخیره می‌شود، بدون بازنویسی یا حدس.
-- خالی می‌ماند اگر منبع خالی بود؛ «تولید» از «بازرگانی» استنباط نمی‌شود.

ALTER TABLE company ADD COLUMN activity TEXT;

DROP VIEW v_company_card;

CREATE VIEW v_company_card AS
SELECT
    c.id AS company_id, c.name_fa, c.name_en, c.website, c.company_page,
    c.province_label, c.verified, c.provenance_class, c.official_site, c.google_search,
    c.activity,
    (SELECT group_concat(h.code, ' · ')
       FROM participation p JOIN hall h ON h.id = p.hall_id
      WHERE p.company_id = c.id) AS halls,
    (SELECT group_concat(b, ' · ') FROM (
        SELECT DISTINCT p.booth AS b FROM participation p
         WHERE p.company_id = c.id AND p.booth IS NOT NULL)) AS booths,
    (SELECT group_concat(b, ' · ') FROM (
        SELECT DISTINCT p.booth_raw AS b FROM participation p
         WHERE p.company_id = c.id AND p.booth_raw IS NOT NULL)) AS booths_raw,
    (SELECT max(p.priority) FROM participation p WHERE p.company_id = c.id) AS priority,
    (SELECT p.priority_reason FROM participation p
      WHERE p.company_id = c.id ORDER BY p.priority DESC LIMIT 1) AS priority_reason,
    (SELECT group_concat(ct.value, ' | ') FROM contact ct
      WHERE ct.company_id = c.id AND ct.channel IN ('phone','mobile')) AS phones,
    (SELECT group_concat(ct.value, ' | ') FROM contact ct
      WHERE ct.company_id = c.id AND ct.channel = 'email') AS emails,
    (SELECT group_concat(ct.channel || ':' || ct.value, ' | ') FROM contact ct
      WHERE ct.company_id = c.id
        AND ct.channel IN ('whatsapp','instagram','telegram','linkedin',
                           'twitter','aparat','eita','bale')) AS socials,
    (SELECT ct.value FROM contact ct
      WHERE ct.company_id = c.id AND ct.channel = 'address' LIMIT 1) AS address,
    (SELECT count(*) FROM contact ct WHERE ct.company_id = c.id) AS contact_count,
    (SELECT group_concat(DISTINCT ct.confidence) FROM contact ct
      WHERE ct.company_id = c.id) AS contact_confidence,
    (SELECT count(*) FROM visit_interaction vi WHERE vi.company_id = c.id) AS interaction_count,
    (SELECT vi.next_action FROM visit_interaction vi WHERE vi.company_id = c.id
      ORDER BY vi.at_utc DESC LIMIT 1) AS last_next_action,
    (SELECT vi.next_due_on FROM visit_interaction vi WHERE vi.company_id = c.id
      ORDER BY vi.at_utc DESC LIMIT 1) AS last_next_due
FROM company c;
