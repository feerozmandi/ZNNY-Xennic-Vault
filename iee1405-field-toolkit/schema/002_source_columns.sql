-- 002_source_columns.sql — ستون‌هایی که فقط از شیت دوم/داده وب می‌آیند
-- چیزی حذف نمی‌شود؛ فقط ظرفیت نگهداری مقدار خام اضافه می‌شود تا
-- «موقعیت غرفه» و «صفحهٔ برق‌پا» گم نشوند و در صورت لزوم بازبینی شوند.

ALTER TABLE participation ADD COLUMN booth_raw TEXT;

ALTER TABLE company ADD COLUMN company_page TEXT;

-- نشانی خام هر منبع وب (بدون تفسیر) برای شاهد
ALTER TABLE contact_evidence ADD COLUMN raw_ref TEXT;
