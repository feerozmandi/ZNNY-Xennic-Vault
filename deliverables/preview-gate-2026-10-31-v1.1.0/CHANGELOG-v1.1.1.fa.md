# Changelog — بستهٔ بازبینی Xennic Preview Gate

## نسخهٔ `1.1.1` — اصلاحی برای بازبینی مجدد، نه مجوز اجرا

نسخهٔ 1.1.1 برای پاسخ به موانع بازبینی 1.1.0 ساخته شده است. **1.1.0 به‌عنوان نسخهٔ اجرا منسوخ و `SUPERSEDED / DO NOT RUN` است.** 1.1.1 نیز تا بازبینی دستیار وبسایت، رفع blockerهای ثبت‌شده و تأیید صریح مالک اجرا نمی‌شود.

### فایل‌های اصلاح‌شده و تغییرات

- `RUNBOOK.fa.md` — ترتیب DB تازه را صریح کرد: PostgreSQL healthy، اجرای مستقل `npm run preview:migrate`، بررسی exit code و query read-only، توقف کامل روی شکست، شروع app/gate، Staff مصنوعی یک‌باره از first-register، آزمون یکپارچه، سپس `npm run preview:seed` فقط یک‌بار. محدودیت seed بدون ledger دائمی و عدم retry خودکار ثبت شد.
- `test_payload_caddy.mjs` — پس از Payload logout همان Bearer را نامعتبر می‌داند، بر اساس endpoint واقعی `/api/staff/me` انتظار `HTTP 200` با `user:null` دارد، برای آزمون‌های بعدی login تازه می‌کند، استقلال gate و Payload را جدا می‌آزماید و GraphQL و upload/metadata/file retrieval رسانه را با gate معتبر و بدون gate می‌سنجد. Staff تصادفی `example.invalid` و PNG مصنوعی تنها داده‌های نوشتنی این تست‌اند.
- `test_caddy_mock.py` — دو نمونهٔ Cookie که به‌خاطر syntax/fixture gate پیش از رسیدن به فیلتر رد می‌شدند، اکنون در همان header یک gate cookie معتبر دارند؛ case نام مشابه نیز gate معتبر دارد. هر نمونه حالا موفقیت synthetic gate، افزایش شمار درخواست upstream و نبود Cookie gate در هدر upstream را assert می‌کند. مسیر `/api/graphql` نیز با/بدون gate پوشش داده شده است.
- `REVIEW-REPORT.fa.md` — نتیجهٔ source review برای Payload `3.91.0` را از نتیجهٔ runtime جدا کرد و موارد egress به GitHub، Compose مؤثر، bypass برنامه و digestها را blocker باز نگه داشت.
- `FILES-FOR-WEBSITE-ASSISTANT.fa.md` — فهرست فایل‌ها/سؤال‌های باز و درخواست بازبینی صرفاً ایستا را به‌روز کرد.
- `VALIDATION.fa.md` — static review، syntax/integrity و آزمون‌های واقعاً اجراشده را از integration/migration/seed/Compose اجرا‌نشده جدا می‌کند.
- `VERSIONS-DIGESTS.fa.md` — ارجاع source-level به logout/JWT/`/me` از Payload `3.91.0` را ثبت می‌کند؛ digest imageها همچنان تأییدنشده هستند.
- `README.fa.md` — توقف اجرا و منسوخ‌شدن صریح 1.1.0 را اعلام می‌کند.
- `MANIFEST.json` و `SHA256SUMS` — با نسخهٔ 1.1.1 و محتوای اصلاح‌شده بازتولید می‌شوند.

### موارد باز، نه اصلاح‌شده

- egress واقعی gate/OAuth2 Proxy به GitHub هنوز آزموده یا policy نشده است؛ overlay فعلی stub مصنوعی و network داخلی بدون egress دارد.
- Compose merge/پیکربندی مؤثر با Docker Compose اجرا نشده است؛ حذف port مستقیم app در YAML هدف است، نه اثبات نبود bypass در runtime/IPv6/host.
- digest/provenance imageهای Caddy و Python مستقل تأیید نشده؛ Node/Postgres در baseline فقط tag دارند.
- OAuth scope نهایی، رفتار حساب دوم، DNS/TLS، outage با نشست معتبر، restore و عملیات VPS همچنان باز/خارج از دامنه‌اند.

هیچ stack، migration، seed، Caddy، OAuth/GitHub، DNS یا VPS در تهیهٔ نسخهٔ 1.1.1 اجرا/تغییر نشده است. آزمون برنامه‌ای اجرا نشده؛ جزئیات دقیق در `VALIDATION.fa.md` است.

## نسخهٔ `1.1.0` — آرشیو قبلی

آرشیو 1.1.0 و checksumهای اصلی برای سابقه حفظ شده‌اند؛ فایل‌ها بی‌توضیح حذف نشده‌اند. از این نسخه برای اجرا استفاده نکنید. اعلام deprecation در پوشهٔ تحویل عمومی و PR کنار فایل‌های اصلی قرار دارد؛ ZIP قدیمی immutable نگه داشته شده تا checksum تاریخی‌اش تغییر نکند.
