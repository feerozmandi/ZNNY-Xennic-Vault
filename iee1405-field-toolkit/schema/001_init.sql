-- 001_init.sql — پایگاه دادهٔ بازدید نمایشگاه برق ۱۴۰۵
-- مرجع: L2-MKT-006 §۵. فقط SQLite، بدون سرویس اضافه، خارج از Vault.
-- قواعد ثابت این اسکیما:
--   * هیچ شمارهٔ غرفه‌ای ساخته نمی‌شود؛ اگر منبع نداشته باشد NULL می‌ماند.
--   * verified فقط با شاهد (contact_evidence) و آزمون مشخص ۱ می‌شود.
--   * متن اصلی دست‌نخورده می‌ماند؛ نرمال‌سازی فقط در ستون‌های *_norm برای جست‌وجو.

CREATE TABLE exhibition (
    id          INTEGER PRIMARY KEY,
    code        TEXT    NOT NULL UNIQUE,          -- iee1405
    title_fa    TEXT    NOT NULL,
    starts_on   TEXT,                             -- ISO؛ از منبع رسمی تأیید شود
    ends_on     TEXT,
    venue       TEXT,
    source_url  TEXT,
    created_at  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE TABLE hall (
    id           INTEGER PRIMARY KEY,
    exhibition_id INTEGER NOT NULL REFERENCES exhibition(id) ON DELETE CASCADE,
    code         TEXT    NOT NULL,                -- 38B | 38 | 41 | فضای باز | ...
    label_fa     TEXT,
    UNIQUE (exhibition_id, code)
);

-- منبع هر مقدار: شیت، فایل، هش، تاریخ برداشت
CREATE TABLE source (
    id          INTEGER PRIMARY KEY,
    kind        TEXT    NOT NULL,                 -- xlsx | csv | manual | web | owner
    path        TEXT    NOT NULL,
    sha256      TEXT,
    captured_on TEXT,
    note        TEXT,
    UNIQUE (kind, path, sha256)
);

CREATE TABLE company (
    id          INTEGER PRIMARY KEY,
    name_fa     TEXT    NOT NULL,
    name_norm   TEXT    NOT NULL,                 -- کلید تطبیق یکتایی
    name_en     TEXT,
    slug        TEXT,
    website     TEXT,
    about_fa    TEXT,
    province_label TEXT,                          -- برچسب خام منبع (ممکن است کشور باشد)
    source_id   INTEGER REFERENCES source(id),
    source_row  INTEGER,
    verified    INTEGER NOT NULL DEFAULT 0 CHECK (verified IN (0,1)),
    notes       TEXT,                             -- یادداشت دستی؛ ایمپورت بازنویسی نمی‌کند
    created_at  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    updated_at  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);
CREATE UNIQUE INDEX ux_company_name_norm ON company(name_norm);
CREATE INDEX ix_company_slug ON company(slug) WHERE slug IS NOT NULL;

-- یک شرکت می‌تواند در چند سالن باشد (مپنا، ایران‌ترانسفو، آرمان بنیان اکسین)
CREATE TABLE participation (
    id            INTEGER PRIMARY KEY,
    exhibition_id INTEGER NOT NULL REFERENCES exhibition(id) ON DELETE CASCADE,
    company_id    INTEGER NOT NULL REFERENCES company(id) ON DELETE CASCADE,
    hall_id       INTEGER REFERENCES hall(id) ON DELETE SET NULL,
    booth         TEXT,                           -- همیشه NULL تا منبع معتبر بیاید
    priority      INTEGER NOT NULL DEFAULT 0 CHECK (priority BETWEEN 0 AND 100),
    priority_reason TEXT,                          -- چرا این اولویت؟ بدون دلیل = 0
    created_at    TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    UNIQUE (exhibition_id, company_id, hall_id)
);
CREATE INDEX ix_participation_hall ON participation(hall_id);

CREATE TABLE contact (
    id          INTEGER PRIMARY KEY,
    company_id  INTEGER NOT NULL REFERENCES company(id) ON DELETE CASCADE,
    channel     TEXT    NOT NULL,                 -- email|phone|mobile|whatsapp|instagram|telegram|linkedin|website|address
    value       TEXT    NOT NULL,                 -- آن‌گونه که در منبع آمده
    value_norm  TEXT    NOT NULL,                 -- برای یکتایی و جست‌وجو
    is_primary  INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0,1)),
    verified    INTEGER NOT NULL DEFAULT 0 CHECK (verified IN (0,1)),
    source_id   INTEGER REFERENCES source(id),
    created_at  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    UNIQUE (company_id, channel, value_norm)
);
CREATE INDEX ix_contact_company ON contact(company_id);
CREATE INDEX ix_contact_norm ON contact(channel, value_norm);

-- شاهد: هر مقدار تماس باید بداند از کجا و کِی آمده (R6)
CREATE TABLE contact_evidence (
    id          INTEGER PRIMARY KEY,
    contact_id  INTEGER NOT NULL REFERENCES contact(id) ON DELETE CASCADE,
    source_id   INTEGER REFERENCES source(id),
    observed_on TEXT,
    method      TEXT,                             -- import | manual | owner_check | phone_call
    value_seen  TEXT,                             -- مقداری که در آن لحظه دیده شد
    note        TEXT
);
CREATE INDEX ix_evidence_contact ON contact_evidence(contact_id);

-- پرچم‌های منبع (توانیر، دانش‌بنیان، ...) — نه تماس
CREATE TABLE company_flag (
    company_id INTEGER NOT NULL REFERENCES company(id) ON DELETE CASCADE,
    flag       TEXT    NOT NULL,                  -- tavanir_vendor | daneshbonyan
    value      TEXT,
    source_id  INTEGER REFERENCES source(id),
    PRIMARY KEY (company_id, flag)
);

-- ثبت تعامل میدانی؛ فقط محلی، بدون همگام‌سازی چنددستگاهی
CREATE TABLE visit_interaction (
    id           INTEGER PRIMARY KEY,
    company_id   INTEGER NOT NULL REFERENCES company(id) ON DELETE CASCADE,
    at_utc       TEXT    NOT NULL,
    kind         TEXT    NOT NULL,                -- visit | call | note | followup
    outcome      TEXT,                            -- interested | not_relevant | callback | ...
    next_action  TEXT,
    next_due_on  TEXT,
    person       TEXT,
    note         TEXT,
    device       TEXT,
    uid          TEXT UNIQUE,                     -- کلید ادغام هنگام import تعامل‌ها
    created_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);
CREATE INDEX ix_interaction_company ON visit_interaction(company_id);
CREATE INDEX ix_interaction_due ON visit_interaction(next_due_on);

-- نام‌های جایگزین همان شرکت (برای تطبیق تعامل‌های واردشده)
CREATE TABLE company_alias (
    company_id INTEGER NOT NULL REFERENCES company(id) ON DELETE CASCADE,
    alias_norm TEXT    NOT NULL,
    PRIMARY KEY (company_id, alias_norm)
);

-- جست‌وجوی فارسی: ستون نرمال‌شدهٔ مستقل + FTS5 روی همان
CREATE TABLE company_search (
    company_id INTEGER PRIMARY KEY REFERENCES company(id) ON DELETE CASCADE,
    name_norm  TEXT NOT NULL,
    text_norm  TEXT NOT NULL
);
CREATE VIRTUAL TABLE company_fts USING fts5(
    name_norm, text_norm,
    content='company_search',
    content_rowid='company_id',
    tokenize="unicode61 remove_diacritics 2"
);

CREATE TRIGGER company_search_ai AFTER INSERT ON company_search BEGIN
    INSERT INTO company_fts(rowid, name_norm, text_norm)
    VALUES (new.company_id, new.name_norm, new.text_norm);
END;
CREATE TRIGGER company_search_ad AFTER DELETE ON company_search BEGIN
    INSERT INTO company_fts(company_fts, rowid, name_norm, text_norm)
    VALUES ('delete', old.company_id, old.name_norm, old.text_norm);
END;
CREATE TRIGGER company_search_au AFTER UPDATE ON company_search BEGIN
    INSERT INTO company_fts(company_fts, rowid, name_norm, text_norm)
    VALUES ('delete', old.company_id, old.name_norm, old.text_norm);
    INSERT INTO company_fts(rowid, name_norm, text_norm)
    VALUES (new.company_id, new.name_norm, new.text_norm);
END;

-- نمای کارت میدانی: یک ردیف برای هر شرکت، بدون تکثیر کارتزین
CREATE VIEW v_company_card AS
SELECT
    c.id                AS company_id,
    c.name_fa,
    c.name_en,
    c.website,
    c.province_label,
    c.verified,
    (SELECT group_concat(h.code, ' · ')
       FROM participation p JOIN hall h ON h.id = p.hall_id
      WHERE p.company_id = c.id)                     AS halls,
    (SELECT max(p.priority) FROM participation p
      WHERE p.company_id = c.id)                     AS priority,
    (SELECT p.priority_reason FROM participation p
      WHERE p.company_id = c.id ORDER BY p.priority DESC LIMIT 1) AS priority_reason,
    (SELECT group_concat(ct.value, ' | ') FROM contact ct
      WHERE ct.company_id = c.id AND ct.channel IN ('phone','mobile')) AS phones,
    (SELECT group_concat(ct.value, ' | ') FROM contact ct
      WHERE ct.company_id = c.id AND ct.channel = 'email')             AS emails,
    (SELECT group_concat(ct.channel || ':' || ct.value, ' | ') FROM contact ct
      WHERE ct.company_id = c.id
        AND ct.channel IN ('whatsapp','instagram','telegram','linkedin')) AS socials,
    (SELECT ct.value FROM contact ct
      WHERE ct.company_id = c.id AND ct.channel = 'address' LIMIT 1)   AS address,
    (SELECT count(*) FROM contact ct WHERE ct.company_id = c.id)       AS contact_count,
    (SELECT count(*) FROM visit_interaction vi WHERE vi.company_id = c.id) AS interaction_count,
    (SELECT vi.next_action FROM visit_interaction vi WHERE vi.company_id = c.id
      ORDER BY vi.at_utc DESC LIMIT 1)                                 AS last_next_action,
    (SELECT vi.next_due_on FROM visit_interaction vi WHERE vi.company_id = c.id
      ORDER BY vi.at_utc DESC LIMIT 1)                                 AS last_next_due
FROM company c;

CREATE VIEW v_contacts_by_company AS
SELECT c.id AS company_id, c.name_fa, ct.channel, ct.value, ct.verified,
       s.kind AS source_kind, s.path AS source_path, ce.observed_on
FROM company c
JOIN contact ct ON ct.company_id = c.id
LEFT JOIN source s  ON s.id = ct.source_id
LEFT JOIN contact_evidence ce ON ce.contact_id = ct.id;
