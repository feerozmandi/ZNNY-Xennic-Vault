# تحویل بازبینی Xennic Preview Gate — نسخهٔ 1.1.2

**وضعیت:** فقط بازبینی ایستا؛ مجوز آزمون/اجرا نیست.
**مبنای وبسایت:** `feerozmandi/xennic-website@418de2b5b3a272e79a824ccde5411dc25f1002cc`
**PR عمومی:** [#73](https://github.com/feerozmandi/ZNNY-Xennic-Vault/pull/73)

## دریافت فایل‌ها

- [TXT کامل ۴۰ فایل](./xennic-preview-gate-delivery-v1.1.2.txt) — 163,773 بایت. TXT یک export کامل متنی است، نه ZIP با پسوند `.txt`.
  SHA-256: `0de0b209e79eca583580fa5356455c1fc6f54a768fef1371182df9c1136689ad` ([sidecar](./xennic-preview-gate-delivery-v1.1.2.txt.sha256))
- [ZIP نسخهٔ 1.1.2](./xennic-preview-gate-delivery-2026-10-31-v1.1.2.zip) — 64,806 بایت.
  SHA-256: `63f6f07ae46ed05494d8caff10f84e2b4755fd901bdf30d1c648fcda3e6d760c` ([sidecar](./xennic-preview-gate-delivery-2026-10-31-v1.1.2.zip.sha256))
- [Changelog مستقل](./CHANGELOG-v1.1.2.fa.md) — SHA-256: `77417e04f16727be076f08e7ea82519ee93b80ae84a2de90467a0b80104459bb` ([sidecar](./CHANGELOG-v1.1.2.fa.md.sha256)).

## اصلاحات نسخهٔ 1.1.2

- migration query cast `::text` ندارد تا `psql -At` خروجی `t/f` با شرط shell بدهد.
- media multipart از `_payload` JSON استفاده می‌کند؛ PNG تستی 1x1 RGBA از نظر CRC/zlib ایستا بررسی شده است.
- media file retrieval مسیر `/api/media/file/...` را هدف می‌گیرد؛ در Caddy mock test انتظار 401 برای همین مسیر بدون gate ثبت شده است (test اجرا نشده).
- اصلاحات قبلی logout/Bearer، login تازه، Cookie filtering و `/api/graphql` حفظ شده‌اند.

## بررسی‌ها و محدودیت اجرا

ایستا موفق: syntax برای ۸ فایل Python، `node --check` برای ۳ فایل، `bash -n` برای ۱۷ بلوک Runbook، PNG CRC/zlib، manifest/SHA، تطبیق بایت همهٔ ۴۰ ورودی ZIP و ۴۰ رکورد TXT. package test یا script runtime اجرا نشده است.

**اجرا نشده:** Caddy mock، Compose merge/stack، Payload/Postgres integration، migration/SQL، Staff bootstrap، seed، OAuth/GitHub، browser، VPS، DNS یا gate فعال. اصلاحات کد مساوی موفقیت runtime نیست.

## نسخه‌های پیشین و blockerها

نسخه‌های 1.1.1 و 1.1.0 **`SUPERSEDED / DO NOT RUN`** هستند؛ artifacts تاریخی‌شان بدون تغییر حفظ شده‌اند. Compose مؤثر، حذف پورت مستقیم app و bypass IPv4/IPv6، egress واقعی gate به GitHub، digest/provenance imageها و media endpoint runtime هنوز بازند. پذیرش برای آزمایش ایزوله به بازبینی دستیار وبسایت، digest review و تأیید صریح مالک وابسته است.
