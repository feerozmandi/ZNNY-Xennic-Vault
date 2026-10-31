# فهرست تحویل Xennic Preview Gate

این مسیر، محل عمومی تحویل‌های بازبینی است؛ نسخه‌های این پوشه مجوز اجرا یا استقرار نیستند.

## نسخهٔ جاری برای بازبینی: 1.1.1

همهٔ فایل‌ها دقیقاً در همین مسیر عمومی قرار دارند:

- [صفحهٔ تحویل 1.1.1، TXT کامل، ZIP و checksumها](./README-v1.1.1.fa.md)
- [Changelog مستقل نسخهٔ 1.1.1](./CHANGELOG-v1.1.1.fa.md)
- [TXT کامل ۴۰ فایل نسخهٔ 1.1.1](./xennic-preview-gate-delivery-v1.1.1.txt)
- [ZIP نسخهٔ 1.1.1](./xennic-preview-gate-delivery-2026-10-31-v1.1.1.zip)

**1.1.1 فقط برای بازبینی ایستا است.** تا بازبین سایت blockerها را تعیین تکلیف کند و مالک مجوز جداگانه بدهد، stack، migration، seed، OAuth، DNS، VPS یا gate فعال را اجرا/تغییر ندهید.

## نسخهٔ 1.1.0 — منسوخ و غیرقابل‌اجرا

**`1.1.0` با `1.1.1` superseded شده است: `SUPERSEDED / DO NOT RUN / برای اجرا ممنوع`.** فایل‌های تاریخی و checksumهایشان حفظ شده‌اند و حذف یا بازنویسی نشده‌اند. این نسخه فقط برای سابقه است؛ از آن برای run، deploy یا config استفاده نکنید. جزئیات در [اعلان deprecation](./DEPRECATED-1.1.0.fa.md) است.

- [TXT کامل تاریخی 1.1.0](./xennic-preview-gate-delivery-v1.1.0.txt)
- [ZIP تاریخی 1.1.0](./xennic-preview-gate-delivery-2026-10-31-v1.1.0.zip)
- [SHA-256 TXT](./xennic-preview-gate-delivery-v1.1.0.txt.sha256)
- [SHA-256 ZIP](./xennic-preview-gate-delivery-2026-10-31-v1.1.0.zip.sha256)

## حدود تحویل

مخزن عمومی است و فایل‌ها برای عموم قابل‌دریافت‌اند. نسخهٔ 1.1.1 می‌گوید چه اصلاح شده و چه چیزی هنوز آزموده نشده؛ static/source review یا checksum را با موفقیت runtime اشتباه نگیرید. هیچ تغییر VPS/DNS/gate فعال در این تحویل انجام نشده است. PR عمومی برای بازبینی: [#73](https://github.com/feerozmandi/ZNNY-Xennic-Vault/pull/73).
