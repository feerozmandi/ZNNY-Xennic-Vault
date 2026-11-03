-- 005_confidence.sql — اطمینان داده، همان‌گونه که منبع خودش اعلام کرده
-- بیشتر دادهٔ تکمیل‌شده با «حدس دامنه» به دست آمده، نه از سایت رسمی.
-- این تفاوت باید در پایگاه و روی کارت میدانی دیده شود، نه در یادداشت شفاهی.

ALTER TABLE company ADD COLUMN provenance_class TEXT;
-- official | guessed | portal | web_search | other | unknown

ALTER TABLE contact ADD COLUMN confidence TEXT NOT NULL DEFAULT 'unknown';
-- همان مقدار شرکت؛ برای هر مقدار تماس جداگانه هم قابل بازبینی است

CREATE INDEX IF NOT EXISTS ix_contact_confidence ON contact(confidence);

-- نما با ستون تازه بازسازی می‌شود (001 دست‌نخورده می‌ماند)
DROP VIEW v_company_card;

CREATE VIEW v_company_card AS
SELECT
    c.id AS company_id, c.name_fa, c.name_en, c.website, c.company_page,
    c.province_label, c.verified, c.provenance_class,
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
    (SELECT count(*) FROM visit_interaction vi WHERE vi.company_id = c.id) AS interaction_count,
    (SELECT vi.next_action FROM visit_interaction vi WHERE vi.company_id = c.id
      ORDER BY vi.at_utc DESC LIMIT 1) AS last_next_action,
    (SELECT vi.next_due_on FROM visit_interaction vi WHERE vi.company_id = c.id
      ORDER BY vi.at_utc DESC LIMIT 1) AS last_next_due
FROM company c;
