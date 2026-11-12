-- ═══════════════════════════════════════════════════════════════════════
-- IEE 1405 — داده مرجع (Seed)
-- idempotent: استفاده از ON CONFLICT DO NOTHING / DO UPDATE
-- اجرا: psql -v ON_ERROR_STOP=1 -f 02_seed_reference.sql
-- ═══════════════════════════════════════════════════════════════════════

-- ── دسته‌بندی محصول (کدها همان کدهای کارت مرجع PRJ-IEE-014) ──
INSERT INTO crm.product_categories (code, title_fa, title_en, sort_order) VALUES
    ('TAB_MV', 'تابلو MV و سلول',                 'MV Switchgear',       10),
    ('TAB_LV', 'تابلو LV و توزیع',                'LV Switchboard',      20),
    ('CAP',    'خازن، راکتور و کیفیت توان',        'Power Quality',       30),
    ('PV',     'خورشیدی و اینورتر',                'Solar / PV',          40),
    ('BESS',   'ذخیره‌ساز باتری',                  'Battery Storage',     50),
    ('PRT',    'حفاظت و رله',                      'Protection Relay',    60),
    ('TRF',    'ترانسفورماتور',                    'Transformer',         70),
    ('CBL',    'کابل و هادی',                      'Cable & Conductor',   80),
    ('MOT',    'موتور و ماشین الکتریکی',           'Electrical Machine',  90),
    ('AUT',    'اتوماسیون، PLC و SCADA',           'Automation',         100),
    ('MET',    'اندازه‌گیری و پایش',                'Measurement',        110),
    ('EQP',    'تجهیزات جانبی (برقگیر، سکسیونر)',   'Auxiliary Equipment',120),
    ('SW',     'نرم‌افزار و هوش مصنوعی',            'Software / AI',      130),
    ('SRV',    'پیمانکار، مشاور و خدمات',          'Services',           140),
    ('OTH',    'سایر',                             'Other',              999)
ON CONFLICT (code) DO UPDATE
    SET title_fa = EXCLUDED.title_fa,
        title_en = EXCLUDED.title_en,
        sort_order = EXCLUDED.sort_order;

-- ── نمایشگاه ۱۴۰۵ ──
INSERT INTO iee1405.exhibitions (code, title, start_date, end_date, venue, city)
VALUES (
    'IEE1405',
    'بیست‌وششمین نمایشگاه بین‌المللی صنعت برق ایران',
    '2026-11-07', '2026-11-10',
    'محل دائمی نمایشگاه‌های بین‌المللی تهران', 'تهران'
)
ON CONFLICT (code) DO UPDATE
    SET title = EXCLUDED.title,
        start_date = EXCLUDED.start_date,
        end_date = EXCLUDED.end_date,
        venue = EXCLUDED.venue;

-- ── کاربران: مالک + دو گوشی میدانی ──
-- ⚠️ مقدار bale_chat_id باید پس از دریافت از ربات جای‌گذاری شود:
--    UPDATE crm.users SET bale_chat_id = <chat_id> WHERE username = 'ahmad';
INSERT INTO crm.users (username, display_name, role) VALUES
    ('ahmad',    'احمد فیروزمندی بندپی', 'owner'),
    ('field-1',  'گوشی ۱ — میدانی',        'field_agent'),
    ('field-2',  'گوشی ۲ — میدانی',       'field_agent'),
    ('wp',       'پنل WordPress',          'service'),
    ('n8n',      'اتوماسیون n8n',          'service')
ON CONFLICT (username) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        role = EXCLUDED.role;
