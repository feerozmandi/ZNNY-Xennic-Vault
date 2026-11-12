-- 004_provenance.sql — منشأ هر داده، همان‌گونه که خودِ منبع ثبت کرده
-- شیت اصلی ستون «منبع تکمیل اطلاعات» و «منابع (URL)» دارد. این دو، جدا از
-- contact_evidence، سطح شرکت را ثبت می‌کنند: کدام شرکت از سایت رسمی تکمیل شده
-- و کدام از جست‌وجوی وب. هیچ‌کدام «تأیید» نیست؛ فقط ادعای منبع است.

ALTER TABLE company ADD COLUMN provenance_source TEXT;
ALTER TABLE company ADD COLUMN provenance_urls   TEXT;
ALTER TABLE company ADD COLUMN logo_url          TEXT;
ALTER TABLE company ADD COLUMN official_site     TEXT;
