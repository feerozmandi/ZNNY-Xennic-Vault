-- 007_pilot.sql — فهرست پایلوت بازدید (L2-MKT-006 مرحلهٔ C)
-- قاعده: هیچ شرکتی خودکار «انتخاب‌شده» نمی‌شود. ابزار فقط نامزد پیشنهاد می‌دهد؛
-- نوشتن در این جدول تنها با --approve و به تصمیم مالک انجام می‌شود.

CREATE TABLE visit_pilot (
    company_id  INTEGER PRIMARY KEY REFERENCES company(id) ON DELETE CASCADE,
    rank        INTEGER NOT NULL,
    reason      TEXT    NOT NULL,          -- چرا این شرکت در فهرست است
    first_check TEXT,                      -- اولین چیزی که سر میز باید تأیید شود
    approved    INTEGER NOT NULL DEFAULT 0 CHECK (approved IN (0,1)),
    approved_by TEXT,
    approved_at TEXT,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE VIEW v_pilot AS
SELECT p.rank, c.name_fa, v.halls, v.priority, v.provenance_class,
       v.phones, v.emails, p.first_check, p.reason, p.approved
  FROM visit_pilot p
  JOIN company c ON c.id = p.company_id
  LEFT JOIN v_company_card v ON v.company_id = c.id
 ORDER BY p.rank;
