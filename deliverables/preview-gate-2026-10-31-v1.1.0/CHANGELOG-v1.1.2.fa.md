# Changelog — Xennic Preview Gate `1.1.2`

## نسخهٔ جاری: `1.1.2` — اصلاحات پس از بازبینی ایستای دستیار وبسایت

این نسخه برای رفع دو نقص قطعی گزارش‌شده در بازبینی ایستای v1.1.1 ساخته شد؛ به‌معنای پذیرش آزمون یکپارچه یا تأیید اجرا نیست. **نسخه‌های `1.1.1` و `1.1.0` `SUPERSEDED / DO NOT RUN` هستند.** نسخهٔ 1.1.2 نیز فقط برای بازبینی است و هنوز تأیید اجرای محلی/عملیاتی ندارد.

### موارد اصلاح‌شده

- **Runbook migration:** `::text` از query حذف شد تا `psql -At` مقدار boolean به‌شکل `t`/`f` چاپ کند و با `test "$MIGRATION_OK" = t` ناسازگار نباشد. توضیح خروجی نیز به‌روزرسانی شد. Query در این بسته اجرا نشده است.
- **Payload media upload:** metadata فرم اکنون در `_payload` به‌صورت JSON فرستاده می‌شود، نه در field جداگانهٔ `alt`.
- **PNG fixture:** دادهٔ 1x1 RGBA با CRC معتبر برای همهٔ chunkها و IDAT zlib stream معتبر جایگزین fixture قبلی شد.
- **Payload media retrieval:** انتظار URL به مسیر `/api/media/file/...` تغییر کرد؛ همان مسیر برای retrieval با gate معتبر و denial بدون gate استفاده می‌شود.
- **Caddy mock:** مسیر `/api/media/file/synthetic.png` بدون gate باید در API gate با 401 رد شود.
- اصلاحات قبلی logout/Bearer، login تازه، Cookie mock و `/api/graphql` حفظ شده‌اند.

### فایل‌های اصلاح‌شده داخل package

`README.fa.md`, `CHANGELOG.fa.md`, `RUNBOOK.fa.md`, `FILES-FOR-WEBSITE-ASSISTANT.fa.md`, `REVIEW-REPORT.fa.md`, `VALIDATION.fa.md`, `VERSIONS-DIGESTS.fa.md`, `test_caddy_mock.py`, `test_payload_caddy.mjs`, `MANIFEST.json`, `SHA256SUMS`.

### موارد باز

- Compose مؤثر و حذف پورت مستقیم app هنوز اثبات نشده‌اند.
- OAuth واقعی و egress gate به GitHub در overlay stub/internal بررسی نمی‌شود.
- digestهای Caddy/Python مستقل تأیید نشده‌اند؛ Node/Postgres هنوز فقط tag دارند.
- این بسته query migration یا Payload media endpoint را اجرا نکرده؛ acceptance برای آزمون ایزوله هنوز وابسته به digest review و تأیید مالک است.

هیچ stack، Caddy، Compose، Payload/Postgres، migration، seed، OAuth/GitHub، VPS یا DNS در تهیهٔ 1.1.2 اجرا/تغییر نشده است. فایل‌های v1.1.0 و v1.1.1 و checksumهایشان در مسیر تحویل عمومی بدون تغییر حفظ می‌شوند؛ deprecation آنها در همان مسیر اعلام شده است.
