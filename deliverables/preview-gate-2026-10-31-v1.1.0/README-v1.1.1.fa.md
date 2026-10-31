# تحویل بازبینی Xennic Preview Gate — نسخهٔ 1.1.1

**وضعیت:** فقط برای بازبینی ایستا، نه مجوز اجرا.
**مبنای وبسایت:** `feerozmandi/xennic-website@418de2b5b3a272e79a824ccde5411dc25f1002cc`
**PR عمومی:** [#73](https://github.com/feerozmandi/ZNNY-Xennic-Vault/pull/73)

## دریافت فایل‌ها

- [دانلود TXT کامل شامل متن و checksum هر ۴۰ فایل](./xennic-preview-gate-delivery-v1.1.1.txt) — 173,450 bytes
  SHA-256: `71b48c963b08f3f188b1275ca1ab26fdbee242aa7c74f2a6428577e176d58f54`
  [فایل sidecar](./xennic-preview-gate-delivery-v1.1.1.txt.sha256)
- [دانلود ZIP نسخهٔ 1.1.1](./xennic-preview-gate-delivery-2026-10-31-v1.1.1.zip) — 68,400 bytes
  SHA-256: `e12fc73897db7506c2fe27e674b8cec57862161fadc813c24187c1939bae6b67`
  [فایل sidecar](./xennic-preview-gate-delivery-2026-10-31-v1.1.1.zip.sha256)
- [Changelog مستقل](./CHANGELOG-v1.1.1.fa.md) — فهرست دقیق تغییرات و ۱۱ فایل اصلاح‌شده؛ SHA-256: `132bb362d801b67706a3c3f6b6df2438b2d2f0de67a36cef08478860162922bd` ([sidecar](./CHANGELOG-v1.1.1.fa.md.sha256)).

TXT فایل متنی کامل است، نه ZIP با پسوند `.txt`. داخل ZIP نیز `MANIFEST.json` و `SHA256SUMS` برای کنترل محتویات هست. پس از استخراج در ریشهٔ بسته:

```sh
sha256sum -c SHA256SUMS
python3 verify_bundle.py
```

## تغییرات مهم

- Runbook ترتیب DB تازه را به‌صورت readiness → migration صریح → verify → Staff آزمایشی یک‌باره → seed یک‌باره تعریف می‌کند؛ شکست migration مراحل بعد را متوقف می‌کند.
- Payload logout/Bearer بر اساس source واقعی Payload `3.91.0` توضیح داده شده؛ Bearer لغوشده برای `/api/staff/me` با انتظار `HTTP 200` و `user:null` سنجیده می‌شود و آزمون بعدی login تازه می‌گیرد.
- Caddy mock اکنون هر نمونه را از gate synthetic عبور می‌دهد و success، upstream reach و حذف Cookie gate را assert می‌کند.
- Integration test پیشنهادی برای `/api/graphql` و upload/metadata/file retrieval رسانه با gate و بدون gate اضافه/گسترش داده شده؛ writeهای آزمون فقط Staff آزمایشی و PNG مصنوعی هستند.
- egress واقعی GitHub، Compose مؤثر، bypass پورت مستقیم و digest/provenance imageها هنوز بازند.

## آزمون‌ها و محدودیت اجرا

در این تحویل Python/Node/shell syntax، parser Payload `3.91.0`, manifest/hash، ZIP و TXT integrity با دادهٔ مصنوعی بررسی شده‌اند. هیچ Caddy mock، Compose stack، Payload/Postgres integration، migration، seed، OAuth/GitHub، VPS یا DNS اجرا نشده است. جزئیات در `VALIDATION.fa.md` داخل ZIP/TXT است.

نسخهٔ `1.1.0` اکنون **`SUPERSEDED / DO NOT RUN`** است؛ فایل‌های تاریخی و checksumهایش در پوشهٔ والد حفظ شده‌اند. نسخهٔ 1.1.1 هم تا بازبینی دستیار وبسایت، رفع blockerها و تأیید صریح مالک اجرا نشود.
