-- 08_exhibitor_mirror.sql — آینهٔ خواندنی فهرست نمایشگاه برای ربات بله
--
-- چرا اسکیمای جدا و نه `crm.organizations`: شرکت حاضر در نمایشگاه «مشتری»
-- نیست (تصمیم R5 در L2-MKT-006). نوشتن ۲۹۷ غرفه‌دار در CRM، پرونده مشتری
-- جعلی می‌سازد و حذفش بعداً پرهزینه است. این آینه:
--   • فقط‌خواندنی برای برنامه است (نقش iee_app فقط SELECT/EXECUTE می‌گیرد)،
--   • با `DROP SCHEMA barghpa CASCADE` کامل و بی‌اثر روی CRM پاک می‌شود،
--   • منبعش همان پایگاه SQLite تأییدشده است (۲۹۷/۴۹۷/۳۰۰)، نه بازخوانی xlsx.
--
-- ارتقای هر شرکت از این آینه به CRM فقط با تصمیم مالک و تطبیق هویت جداگانه.

CREATE SCHEMA IF NOT EXISTS barghpa;

COMMENT ON SCHEMA barghpa IS
'آینهٔ خواندنی فهرست غرفه‌داران نمایشگاه برق ۱۴۰۵؛ خارج از CRM و بدون نوشتن.';

-- ── بارگذاری‌ها: هر اجرا یک ردیف، برای اینکه «چه زمانی و از کدام فایل» معلوم باشد
CREATE TABLE IF NOT EXISTS barghpa.load_batch (
    id             bigserial PRIMARY KEY,
    loaded_at      timestamptz NOT NULL DEFAULT now(),
    source_file    text NOT NULL,
    source_sha256  text,
    companies      integer,
    contacts       integer,
    participations integer,
    flags          integer,
    pilot_rows     integer,
    tool_version   text
);

COMMENT ON TABLE barghpa.load_batch IS
'سابقهٔ هر بارگذاری: فایل مبدأ، هش و شمار ردیف‌ها؛ تا عدد بی‌شاهد نماند.';

CREATE TABLE IF NOT EXISTS barghpa.company (
    id               bigint PRIMARY KEY,          -- همان id پایگاه SQLite (ارجاع پایدار)
    name_fa          text NOT NULL,
    name_norm        text NOT NULL UNIQUE,
    name_en          text,
    slug             text,
    website          text,
    about_fa         text,
    province_label   text,                        -- برچسب خام منبع (ممکن است کشور باشد)
    provenance_class text NOT NULL DEFAULT 'unknown'
                     CHECK (provenance_class IN
                            ('official','guessed','portal','web_search','other','unknown')),
    official_site    text,
    google_search    text,
    verified         boolean NOT NULL DEFAULT false,
    source_row       integer,
    updated_at       timestamptz NOT NULL DEFAULT now()
);

COMMENT ON COLUMN barghpa.company.provenance_class IS
'ادعای خودِ منبع دربارهٔ دامنه: official | guessed | portal | web_search | unknown.';
COMMENT ON COLUMN barghpa.company.verified IS
'هرگز در بارگذاری ساخته نمی‌شود؛ فقط با شاهد و تأیید انسانی true می‌شود.';

CREATE TABLE IF NOT EXISTS barghpa.participation (
    company_id      bigint NOT NULL REFERENCES barghpa.company(id) ON DELETE CASCADE,
    hall            text NOT NULL DEFAULT '—',
    booth           text,                         -- فقط با الگوی روشن؛ وگرنه NULL
    booth_raw       text,                         -- آن‌گونه که در منبع آمده
    priority        smallint NOT NULL DEFAULT 0 CHECK (priority BETWEEN 0 AND 100),
    priority_reason text,
    PRIMARY KEY (company_id, hall)
);

CREATE INDEX IF NOT EXISTS participation_hall_idx ON barghpa.participation (hall);

CREATE TABLE IF NOT EXISTS barghpa.contact (
    company_id  bigint NOT NULL REFERENCES barghpa.company(id) ON DELETE CASCADE,
    channel     text NOT NULL,
    value       text NOT NULL,
    value_norm  text NOT NULL,
    confidence  text NOT NULL DEFAULT 'unknown'
                CHECK (confidence IN ('official','guessed','portal','web_search','other','unknown')),
    is_primary  boolean NOT NULL DEFAULT false,
    verified    boolean NOT NULL DEFAULT false,
    PRIMARY KEY (company_id, channel, value_norm)
);

CREATE INDEX IF NOT EXISTS contact_channel_idx ON barghpa.contact (channel, value_norm);

CREATE TABLE IF NOT EXISTS barghpa.company_flag (
    company_id bigint NOT NULL REFERENCES barghpa.company(id) ON DELETE CASCADE,
    flag       text NOT NULL,
    value      text,
    PRIMARY KEY (company_id, flag)
);

CREATE TABLE IF NOT EXISTS barghpa.pilot (
    rank        integer PRIMARY KEY CHECK (rank BETWEEN 1 AND 200),
    company_id  bigint NOT NULL REFERENCES barghpa.company(id) ON DELETE CASCADE,
    reason      text,
    first_check text,
    approved    boolean NOT NULL DEFAULT false,
    approved_by text,
    approved_at text
);

-- ── نمای کارت: یک ردیف برای هر شرکت، بدون ضرب کارتزین
-- ── حوزه فعالیت (از ستون «نوع فعالیت» منبع) ──────────────────────────
-- در بازدید، اولین چیزی که از یک غرفه می‌پرسیم همین است: تولیدکننده‌اید یا
-- بازرگان؟ در نسخهٔ قبل این داده در فایل منبع بود و در آینه نبود — یعنی روی
-- کارت دیده نمی‌شد. مقدار عیناً منتقل می‌شود؛ خالی می‌ماند اگر منبع خالی بود.
ALTER TABLE barghpa.company ADD COLUMN IF NOT EXISTS activity text;

COMMENT ON COLUMN barghpa.company.activity IS
'نوع فعالیت از منبع («تولید» / «بازرگانی» / «خدمات» …) — دست‌نخورده، بدون استنباط';

CREATE OR REPLACE VIEW barghpa.v_card AS
SELECT c.id AS company_id, c.name_fa, c.name_en, c.slug, c.website, c.about_fa,
       c.province_label, c.provenance_class, c.official_site, c.google_search,
       c.verified,
       (SELECT string_agg(p.hall, ' · ' ORDER BY p.hall)
          FROM barghpa.participation p WHERE p.company_id = c.id)              AS halls,
       (SELECT string_agg(DISTINCT p.booth, ' · ')
          FROM barghpa.participation p
         WHERE p.company_id = c.id AND p.booth IS NOT NULL)                    AS booths,
       (SELECT max(p.priority) FROM barghpa.participation p
         WHERE p.company_id = c.id)                                            AS priority,
       (SELECT string_agg(ct.value, ' | ' ORDER BY ct.value) FROM barghpa.contact ct
         WHERE ct.company_id = c.id AND ct.channel IN ('phone','mobile'))      AS phones,
       (SELECT string_agg(ct.value, ' | ' ORDER BY ct.value) FROM barghpa.contact ct
         WHERE ct.company_id = c.id AND ct.channel = 'email')                  AS emails,
       (SELECT string_agg(ct.channel || ':' || ct.value, ' | ')
          FROM barghpa.contact ct
         WHERE ct.company_id = c.id
           AND ct.channel IN ('whatsapp','instagram','telegram','linkedin',
                              'twitter','aparat','eita','bale'))               AS socials,
       (SELECT ct.value FROM barghpa.contact ct
         WHERE ct.company_id = c.id AND ct.channel = 'address' LIMIT 1)        AS address,
       (SELECT count(*) FROM barghpa.contact ct WHERE ct.company_id = c.id)    AS contact_count,
       (SELECT string_agg(DISTINCT ct.confidence, ',') FROM barghpa.contact ct
         WHERE ct.company_id = c.id)                                           AS contact_confidence,
       (SELECT string_agg(f.flag, ',') FROM barghpa.company_flag f
         WHERE f.company_id = c.id)                                            AS flags,
       (SELECT pi.rank FROM barghpa.pilot pi WHERE pi.company_id = c.id)       AS pilot_rank,
       -- ⚠️ ستون تازه همیشه در **پایان** فهرست: CREATE OR REPLACE VIEW نمی‌تواند
       -- ترتیب ستون‌های موجود را عوض کند و فقط افزودن در انتها مجاز است.
       c.activity
  FROM barghpa.company c;

-- ── توابع ربات ────────────────────────────────────────────────────────

-- برچسب فارسی سطح اطمینان؛ همان واژه‌هایی که در کارت چاپی میدانی به‌کار رفت
CREATE OR REPLACE FUNCTION barghpa.conf_label(p text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE coalesce(p, 'unknown')
             WHEN 'official'   THEN 'سایت رسمی (ادعای منبع)'
             WHEN 'portal'     THEN 'پورتال برق‌پا'
             WHEN 'web_search' THEN 'جست‌وجوی وب'
             WHEN 'guessed'    THEN 'حدس دامنه — تأییدنشده'
             ELSE 'نامشخص'
           END
$$;

-- ارقام فارسی/عربی → لاتین، تا «۳۸B» هم سالن شناخته شود
CREATE OR REPLACE FUNCTION barghpa.fa_digits(p text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT translate(COALESCE(p, ''),
                     '۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩',
                     '01234567890123456789')
$$;

-- جست‌وجو در آینه: ۰ نتیجه، یک نتیجه (کارت)، چند نتیجه (فهرست شماره‌دار)
SELECT iee1405.drop_stale_result('barghpa', 'search',
       'TABLE(company_id bigint, name_fa text, halls text, contact_count int, provenance text)');
CREATE OR REPLACE FUNCTION barghpa.search(p_q text, p_limit int DEFAULT 8)
RETURNS TABLE (company_id bigint, name_fa text, halls text,
               contact_count int, provenance text)
LANGUAGE sql STABLE AS $$
    WITH q AS (SELECT crm.norm_text(barghpa.fa_digits(btrim(coalesce(p_q, '')))) AS n)
    SELECT v.company_id, v.name_fa, coalesce(v.halls, '—'),
           v.contact_count::int, v.provenance_class
      FROM barghpa.v_card v
     WHERE (SELECT n FROM q) <> ''
       AND (   crm.norm_text(v.name_fa) ILIKE '%' || (SELECT n FROM q) || '%'
            OR barghpa.fa_digits(v.company_id::text) = (SELECT n FROM q)
            OR crm.norm_text(coalesce(v.name_en, '')) ILIKE '%' || (SELECT n FROM q) || '%')
     ORDER BY CASE
                WHEN barghpa.fa_digits(v.company_id::text) = (SELECT n FROM q) THEN 0
                WHEN crm.norm_text(v.name_fa) ILIKE (SELECT n FROM q) || '%'      THEN 1
                WHEN crm.norm_text(v.name_fa) ILIKE '%' || (SELECT n FROM q) || '%' THEN 2
                ELSE 3 END,
              v.contact_count DESC, v.name_fa
     LIMIT greatest(1, least(coalesce(p_limit, 8), 25))
$$;

COMMENT ON FUNCTION barghpa.search(text, int) IS
'جست‌وجوی نام/شناسه با یکسان‌سازی فارسی (ي/ك، نیم‌فاصله، ارقام فارسی).';

-- فهرست یک سالن
SELECT iee1405.drop_stale_result('barghpa', 'by_hall',
       'TABLE(company_id bigint, name_fa text, priority int, contact_count int)');
CREATE OR REPLACE FUNCTION barghpa.by_hall(p_hall text, p_limit int DEFAULT 15)
RETURNS TABLE (company_id bigint, name_fa text, priority int, contact_count int)
LANGUAGE sql STABLE AS $$
    SELECT v.company_id, v.name_fa, coalesce(v.priority, 0), v.contact_count::int
      FROM barghpa.v_card v
      JOIN barghpa.participation p ON p.company_id = v.company_id
     WHERE crm.norm_text(barghpa.fa_digits(p.hall)) =
           crm.norm_text(barghpa.fa_digits(btrim(coalesce(p_hall, ''))))
     ORDER BY coalesce(v.priority, 0) DESC, v.contact_count DESC, v.name_fa
     LIMIT greatest(1, least(coalesce(p_limit, 15), 40))
$$;

-- متن کارت برای بله (کوتاه، بدون شرط‌های تزئینی)
CREATE OR REPLACE FUNCTION barghpa.card(p_id bigint) RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v   record;
    out text;
    v_conf text;
BEGIN
    SELECT * INTO v FROM barghpa.v_card WHERE company_id = p_id;
    IF v.company_id IS NULL THEN
        RETURN NULL;
    END IF;

    out := '🏭 ' || v.name_fa || E'\n';
    -- حوزه فعالیت دقیقاً زیر نام، چون در بازدید اولین سؤال همین است.
    out := out || '🏷 حوزه فعالیت: ' ||
           COALESCE(NULLIF(btrim(v.activity), ''),
                    'ثبت‌نشده (با به‌روزرسانی داده پر می‌شود)') || E'\n';
    out := out || 'سالن: ' || coalesce(v.halls, 'ثبت‌نشده');
    IF v.booths IS NOT NULL THEN
        out := out || ' | غرفه: ' || v.booths;
    ELSE
        out := out || ' | غرفه: ثبت‌نشده';
    END IF;
    out := out || E'\n' || 'شناسه: ' || v.company_id;

    v_conf := barghpa.conf_label(v.provenance_class);
    out := out || E'\n' || 'منبع: ' || v_conf;
    IF v.official_site IS NOT NULL THEN
        out := out || E'\n' || 'سایت رسمی: ' || v.official_site;
    ELSIF v.website IS NOT NULL THEN
        out := out || E'\n' || 'وب‌سایت: ' || v.website;
    END IF;

    IF v.priority IS NOT NULL AND v.priority > 0 THEN
        out := out || E'\n' || 'اولویت: ' || v.priority;
    END IF;

    IF v.phones IS NOT NULL THEN
        out := out || E'\n' || '📞 ' || v.phones;
    END IF;
    IF v.emails IS NOT NULL THEN
        out := out || E'\n' || '✉️ ' || v.emails;
    END IF;
    IF v.socials IS NOT NULL THEN
        out := out || E'\n' || '🔗 ' || v.socials;
    END IF;
    IF v.phones IS NULL AND v.emails IS NULL AND v.socials IS NULL THEN
        out := out || E'\n' || '⚠️ هیچ تماسی در فهرست ثبت نشده است.';
        IF v.google_search IS NOT NULL THEN
            out := out || E'\n' || 'جست‌وجوی دستی: ' || v.google_search;
        END IF;
    END IF;

    -- هشدار اطمینان: اگر هیچ تماس رسمی نبود، صریح بگو
    IF v.contact_confidence IS NOT NULL
       AND v.contact_confidence NOT LIKE '%official%' THEN
        out := out || E'\n\n' || '⚠️ تماس‌ها تأییدنشده‌اند (' ||
               barghpa.conf_label(split_part(v.contact_confidence, ',', 1)) ||
               ')؛ پیش از هر پیشنهاد تأیید کنید.';
    END IF;

    IF v.flags IS NOT NULL THEN
        IF v.flags LIKE '%tavanir_vendor%' THEN
            out := out || E'\n' || '✅ وندور لیست توانیر';
        END IF;
        IF v.flags LIKE '%daneshbonyan%' THEN
            out := out || E'\n' || '✅ دانش‌بنیان';
        END IF;
    END IF;

    IF v.pilot_rank IS NOT NULL THEN
        out := out || E'\n' || '🎯 در فهرست پایلوت: رتبه ' || v.pilot_rank;
    END IF;

    RETURN left(out, 3800);
END $$;

COMMENT ON FUNCTION barghpa.card(bigint) IS
'کارت متنی یک شرکت برای بله؛ سطح اطمینان و نبود تماس را صریح می‌نویسد.';

-- خلاصهٔ آینه: عددهایی که با پایگاه مبدأ قابل تطبیق‌اند
CREATE OR REPLACE FUNCTION barghpa.stats_text() RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE
    c bigint; k bigint; p bigint; f bigint; pl bigint;
    v_official bigint; v_guessed bigint;
    v_last timestamptz; v_file text;
BEGIN
    SELECT count(*) INTO c FROM barghpa.company;
    SELECT count(*) INTO k FROM barghpa.contact;
    SELECT count(*) INTO p FROM barghpa.participation;
    SELECT count(*) INTO f FROM barghpa.company_flag;
    SELECT count(*) INTO pl FROM barghpa.pilot;
    SELECT count(*) INTO v_official FROM barghpa.contact WHERE confidence = 'official';
    SELECT count(*) INTO v_guessed  FROM barghpa.contact WHERE confidence = 'guessed';
    SELECT loaded_at, source_file INTO v_last, v_file
      FROM barghpa.load_batch ORDER BY id DESC LIMIT 1;

    IF c = 0 THEN
        RETURN 'آینهٔ نمایشگاه خالی است. روی سرور: bash 03_ops/load_exhibitors.sh';
    END IF;

    RETURN '📊 آینهٔ فهرست نمایشگاه' || E'\n' ||
           'شرکت: ' || c || ' · تماس: ' || k || ' · مشارکت: ' || p ||
           E'\n' || 'پرچم: ' || f || ' · پایلوت: ' || pl || E'\n' ||
           'اطمینان تماس: ' || v_official || ' رسمی، ' || v_guessed || ' حدسی' ||
           -- COALESCE لازم است: اگر آینه دستی (بدون load_batch) بارگذاری شده باشد،
           -- to_char(NULL) کل رشته را NULL می‌کرد و /c پاسخ **خالی** می‌داد؛
           -- بله ۴۰۰ می‌داد و کاربر سکوت می‌دید.
           E'\n' || 'بارگذاری: ' || COALESCE(to_char(v_last AT TIME ZONE 'Asia/Tehran',
                                                    'YYYY-MM-DD HH24:MI'), 'نامشخص') ||
           COALESCE(' از ' || v_file, '');
END $$;

-- ورودی ربات: رشته → پاسخ
CREATE OR REPLACE FUNCTION barghpa.bot_reply(p_arg text) RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_arg  text := btrim(coalesce(p_arg, ''));
    v_n    text;
    v_id   bigint;
    v_hall text;
    v_rows int;
    v_list text;
    v_card text;
BEGIN
    IF to_regclass('barghpa.company') IS NULL THEN
        RETURN 'آینهٔ نمایشگاه ساخته نشده است.';
    END IF;
    IF (SELECT count(*) FROM barghpa.company) = 0 THEN
        RETURN 'آینهٔ نمایشگاه خالی است. روی سرور: bash 03_ops/load_exhibitors.sh';
    END IF;

    IF v_arg = '' THEN
        RETURN barghpa.stats_text() || E'\n\n' ||
               'جست‌وجو: /c ایران ترانسفو' || E'\n' ||
               'کارت با شناسه: /c 12' || E'\n' ||
               'یک سالن: /c 38B';
    END IF;

    v_n := crm.norm_text(barghpa.fa_digits(v_arg));

    -- ۱) شناسهٔ عددی → کارت
    IF v_arg ~ '^[0-9]+$' THEN
        v_card := barghpa.card(v_arg::bigint);
        IF v_card IS NOT NULL THEN
            RETURN v_card;
        END IF;
    END IF;

    -- ۲) نام سالن → فهرست (فقط اگر دقیقاً یک سالن باشد)
    SELECT p.hall INTO v_hall
      FROM barghpa.participation p
     WHERE crm.norm_text(barghpa.fa_digits(p.hall)) = v_n
     LIMIT 1;

    IF v_hall IS NOT NULL THEN
        SELECT count(*) INTO v_rows FROM barghpa.by_hall(v_hall, 40);
        SELECT string_agg(rn || ') ' || name_fa ||
                          CASE WHEN priority > 0 THEN ' [اولویت ' || priority || ']'
                               ELSE '' END, E'\n' ORDER BY rn)
          INTO v_list
          FROM (SELECT row_number() OVER () AS rn, name_fa, priority
                  FROM barghpa.by_hall(v_hall, 15)) t;
        RETURN '🏛 سالن ' || v_hall || ' — ' || v_rows || ' شرکت' || E'\n' ||
               coalesce(v_list, '—') ||
               CASE WHEN v_rows > 15 THEN E'\n' || '(نمایش ۱۵ از ' || v_rows || ')' ELSE '' END ||
               E'\n\n' || 'کارت هر شرکت: /c شناسه';
    END IF;

    -- ۳) جست‌وجوی نام
    SELECT count(*) INTO v_rows FROM barghpa.search(v_arg, 25);
    IF v_rows = 0 THEN
        RETURN 'چیزی با «' || v_arg || '» پیدا نشد.' || E'\n' ||
               'بخش کوتاه‌تری از نام را بفرستید، یا نام سالن: /c 38B';
    END IF;

    SELECT max(company_id) INTO v_id FROM barghpa.search(v_arg, 2);
    IF v_rows = 1 THEN
        RETURN barghpa.card(v_id);
    END IF;

    SELECT string_agg(rn || ') ' || company_id || ' — ' || name_fa || ' | ' || halls,
                      E'\n' ORDER BY rn)
      INTO v_list
      FROM (SELECT row_number() OVER () AS rn, company_id, name_fa, halls
              FROM barghpa.search(v_arg, 8)) t;

    RETURN v_rows || ' نتیجه برای «' || v_arg || '»:' || E'\n' || v_list ||
           CASE WHEN v_rows > 8 THEN E'\n' || '(نمایش ۸ از ' || v_rows || ')' ELSE '' END ||
           E'\n\n' || 'کارت: /c شناسه';
END $$;

COMMENT ON FUNCTION barghpa.bot_reply(text) IS
'ورودی دستور /c — شناسه، نام سالن یا عبارت جست‌وجو را می‌پذیرد.';

-- ── خودآزمایی سمت سرور: عددهایی که باید با SQLite یکی باشند
SELECT iee1405.drop_stale_result('barghpa', 'selftest',
       'TABLE(check_name text, ok boolean, detail text)');
CREATE OR REPLACE FUNCTION barghpa.selftest()
RETURNS TABLE (check_name text, ok boolean, detail text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    c bigint; k bigint; p bigint; v_batch record; v_card text; v_any bigint;
BEGIN
    SELECT count(*) INTO c FROM barghpa.company;
    SELECT count(*) INTO k FROM barghpa.contact;
    SELECT count(*) INTO p FROM barghpa.participation;
    SELECT * INTO v_batch FROM barghpa.load_batch ORDER BY id DESC LIMIT 1;

    RETURN QUERY SELECT 'شرکت‌ها با آخرین بارگذاری می‌خوانند',
        (v_batch.id IS NULL OR c = v_batch.companies), c || ' از ' || coalesce(v_batch.companies::text, '—');
    RETURN QUERY SELECT 'تماس‌ها با آخرین بارگذاری می‌خوانند',
        (v_batch.id IS NULL OR k = v_batch.contacts), k || ' از ' || coalesce(v_batch.contacts::text, '—');
    RETURN QUERY SELECT 'مشارکت‌ها با آخرین بارگذاری می‌خوانند',
        (v_batch.id IS NULL OR p = v_batch.participations), p || ' از ' || coalesce(v_batch.participations::text, '—');

    RETURN QUERY SELECT 'هر شرکت دست‌کم یک سالن دارد',
        NOT EXISTS (SELECT 1 FROM barghpa.company x
                     WHERE NOT EXISTS (SELECT 1 FROM barghpa.participation y
                                        WHERE y.company_id = x.id)),
        (SELECT count(*)::text FROM barghpa.company x
          WHERE NOT EXISTS (SELECT 1 FROM barghpa.participation y WHERE y.company_id = x.id))
        || ' شرکت بی‌سالن';

    -- قاعدهٔ خودِ ایمپورت: booth فقط با الگوی روشن پر می‌شود؛ هر چیز دیگری جعل است
    RETURN QUERY SELECT 'هیچ غرفهٔ ساختگی نیست (booth خالی یا با الگوی «سالن-شماره»)',
        NOT EXISTS (SELECT 1 FROM barghpa.participation
                     WHERE booth IS NOT NULL AND booth !~ '^[0-9]{2}[A-Za-z]?-[0-9]+$'),
        (SELECT count(*)::text FROM barghpa.participation
          WHERE booth IS NOT NULL AND booth !~ '^[0-9]{2}[A-Za-z]?-[0-9]+$')
        || ' غرفهٔ بدشکل از ' ||
        (SELECT count(*)::text FROM barghpa.participation WHERE booth IS NOT NULL);

    RETURN QUERY SELECT 'verified فقط با شاهد (نباید در بارگذاری ساخته شود)',
        NOT EXISTS (SELECT 1 FROM barghpa.company c2
                     WHERE c2.verified
                       AND NOT EXISTS (SELECT 1 FROM barghpa.contact ct
                                        WHERE ct.company_id = c2.id AND ct.verified)),
        (SELECT count(*)::text FROM barghpa.company WHERE verified) || ' شرکت verified';

    RETURN QUERY SELECT 'نام تکراری وجود ندارد',
        NOT EXISTS (SELECT 1 FROM (SELECT name_norm FROM barghpa.company
                                    GROUP BY name_norm HAVING count(*) > 1) d),
        (SELECT count(*)::text FROM (SELECT name_norm FROM barghpa.company
                                      GROUP BY name_norm HAVING count(*) > 1) d) || ' نام تکراری';

    -- جست‌وجوی عملی روی دادهٔ واقعی: اولین شرکت با بیشترین تماس
    SELECT company_id INTO v_any FROM barghpa.v_card
     WHERE contact_count > 0 ORDER BY contact_count DESC, company_id LIMIT 1;
    v_card := barghpa.card(v_any);
    RETURN QUERY SELECT 'کارت یک شرکت واقعی ساخته می‌شود',
        (v_card IS NOT NULL AND length(v_card) > 30),
        left(regexp_replace(coalesce(v_card, '—'), E'\\s+', ' ', 'g'), 60);

    RETURN QUERY SELECT 'دستور /c پاسخ غیرخالی می‌دهد',
        (length(barghpa.bot_reply('')) > 20), left(barghpa.bot_reply(''), 40);
END $$;

COMMENT ON FUNCTION barghpa.selftest() IS
'بازبینی روی دادهٔ واقعی سرور: شمار ردیف‌ها، نبود غرفهٔ ساختگی، کارت و پاسخ ربات.';

-- ── دستور /c در راهنمای ربات (فقط یک‌بار تزریق می‌شود)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM iee1405.bot_messages WHERE key = 'help') THEN
        UPDATE iee1405.bot_messages
           SET template = template || E'\n' ||
                          '/c نام یا شناسه یا سالن — شرکت از فهرست نمایشگاه',
               updated_at = now()
         WHERE key = 'help'
           AND template NOT LIKE '%/c نام%';
    END IF;
END $$;

-- ── دسترسی برنامه: فقط خواندن
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iee_app') THEN
        GRANT USAGE ON SCHEMA barghpa TO iee_app;
        GRANT SELECT ON ALL TABLES IN SCHEMA barghpa TO iee_app;
        GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA barghpa TO iee_app;
        ALTER DEFAULT PRIVILEGES IN SCHEMA barghpa GRANT SELECT ON TABLES TO iee_app;
        -- هیچ INSERT/UPDATE/DELETE به iee_app داده نمی‌شود: آینه فقط‌خواندنی است
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA barghpa FROM iee_app;
    END IF;
END $$;
