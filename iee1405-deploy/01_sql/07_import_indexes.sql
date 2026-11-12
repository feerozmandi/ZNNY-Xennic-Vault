-- ═══════════════════════════════════════════════════════════════════════
-- IEE 1405 — پیش‌نیاز ایندکس‌های ایمپورت
--
-- چرا؟ برای اینکه ایمپورت کاتالوگ نمایشگاه، شرکت تکراری نسازد، واکشی باید
-- با نام نرمال‌شده یکتا باشد. در ساختار اولیه، ایندکس name_norm یکتا نبود و
-- «ON CONFLICT (name_norm)» با خطای «no unique constraint matching» شکست
-- می‌خورد. این فایل آن را ایمن اضافه می‌کند:
--   • اگر از قبل نام تکراری وجود داشته باشد، فقط هشدار می‌دهد و رد می‌شود
--     (به‌جای شکستن استقرار).
--   • نام‌های حذف‌شده (deleted_at) در قید نمی‌آیند تا بازیابی شرکت ممکن بماند.
-- ═══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── گام ۰: به‌روز کردن ستون نام نرمال‌شده ─────────────────────────────
-- norm_text تازه نیم‌فاصله را هم یکسان می‌کند، ولی name_norm یک ستون
-- تولیدشده ذخیره‌شده است و مقدار ردیف‌های قدیمی بازمحاسبه نمی‌شود. اگر
-- مقدار ذخیره‌شده با تابع فعلی اختلاف داشت، ایندکس یکتا موقتاً برداشته
-- می‌شود، ردیف‌ها «لمس» می‌شوند تا بازمحاسبه شوند، و ایندکس دوباره ساخته
-- می‌شود (آزمون‌شده: UPDATE ... SET updated_at = updated_at بازمحاسبه می‌کند).
DO $$
DECLARE
    v_stale int;
BEGIN
    SELECT count(*) INTO v_stale
      FROM crm.organizations
     WHERE name_norm IS DISTINCT FROM crm.norm_text(legal_name);
    IF v_stale > 0 THEN
        RAISE NOTICE 'بازمحاسبه نام نرمال‌شده برای % شرکت (نیم‌فاصله و ی/ک)', v_stale;
        DROP INDEX IF EXISTS crm.organizations_name_uq;
        DROP INDEX IF EXISTS crm.organizations_name_idx;
        UPDATE crm.organizations SET updated_at = updated_at;
    END IF;
END $$;

DO $$
DECLARE
    v_dups int;
    v_names text;
BEGIN
    SELECT count(*) INTO v_dups FROM (
        SELECT name_norm FROM crm.organizations
         WHERE deleted_at IS NULL AND name_norm IS NOT NULL
         GROUP BY name_norm HAVING count(*) > 1
    ) d;

    IF v_dups > 0 THEN
        SELECT string_agg(name_norm || ' ×' || n, ', ') INTO v_names FROM (
            SELECT name_norm, count(*) AS n FROM crm.organizations
             WHERE deleted_at IS NULL AND name_norm IS NOT NULL
             GROUP BY name_norm HAVING count(*) > 1 LIMIT 5
        ) x;
        RAISE WARNING 'ایندکس یکتا ساخته نشد: % نام تکراری وجود دارد (%). ابتدا آن‌ها را ادغام کنید.', v_dups, v_names;
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_indexes
                    WHERE schemaname = 'crm' AND indexname = 'organizations_name_uq') THEN
        CREATE UNIQUE INDEX organizations_name_uq
            ON crm.organizations (name_norm)
            WHERE deleted_at IS NULL AND name_norm IS NOT NULL;
        RAISE NOTICE 'ایندکس یکتای نام شرکت ساخته شد (organizations_name_uq)';
    END IF;
END $$;

-- ایندکس جست‌وجوی ساده (اگر در گام بازمحاسبه برداشته شد، دوباره ساخته می‌شود)
CREATE INDEX IF NOT EXISTS organizations_name_idx ON crm.organizations (name_norm);

-- مشارکت: برای یک شرکت در یک نمایشگاه فقط یک ردیف (قید از قبل موجود است،
-- اما اگر ساختار قدیمی باشد این‌جا تضمین می‌شود).
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_indexes
                    WHERE schemaname = 'iee1405'
                      AND indexname = 'participations_organization_id_exhibition_id_key') THEN
        CREATE UNIQUE INDEX participations_organization_id_exhibition_id_key
            ON iee1405.participations (organization_id, exhibition_id);
        RAISE NOTICE 'قید یکتای مشارکت ساخته شد';
    END IF;
END $$;

\echo '✅ پیش‌نیازهای ایمپورت آماده است'
