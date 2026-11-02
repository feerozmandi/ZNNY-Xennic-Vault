# IEE 1405 — استقرار PostgreSQL + اتوماسیون n8n

> بسته اجرایی برای نمایشگاه بیست‌وششم صنعت برق (۱۶–۱۹ آبان ۱۴۰۵).
> همه داده‌ها در **یک پایگاه‌داده PostgreSQL دائمی** می‌مانند؛ n8n فقط لوله است.
> مستندات پروژه: `ZNNY-Xennic-Vault/04_Projects/IEE_1405/PRJ-IEE-015 — اتوماسیون n8n و اتصال به PostgreSQL.md`

---

## ۰. شروع سریع (روی خودِ سرور)

> [!warning] مهم
> این دستورها **روی VPS** اجرا می‌شوند، نه روی لپ‌تاپ.
> اگر همین حالا داخل سرور هستید (`xennic@server2085:~$`)، دستور `ssh` لازم نیست —
> از سرور به خودش SSH زدن با `Connection timed out` شکست می‌خورد.

```bash
# ۱) گرفتن فایل‌ها (مخزن عمومی است؛ نیازی به توکن نیست)
cd ~
git clone --branch arena/011e185b-znny-xennic-vault --single-branch \
    https://github.com/feerozmandi/ZNNY-Xennic-Vault.git
cd ZNNY-Xennic-Vault/iee1405-deploy

# ۲) بررسی پیش‌نیازها — در یک نگاه می‌گوید چه چیزی کم است
bash 03_ops/preflight.sh
```

> [!note] کشف خودکار محیط
> روی این سرور، هیچ‌کدام از پیش‌فرض‌های معمول درست نیستند و لازم نیست دستی تنظیم شوند:
> کانتینر `xennic-infra-postgres-1` · کاربر دیتابیس `n8n` (نه `postgres`) ·
> دیتابیس برنامه وجود ندارد و **در گام استقرار ساخته می‌شود** (`xennic`).
> دیتابیس `n8n` هیچ‌وقت دست نمی‌خورد.

`preflight.sh` نام واقعی کانتینرها، نام دیتابیس، نسخه n8n، وضعیت متغیرها و
فضای دیسک را بررسی می‌کند و در پایان **دستور بعدی را با مقادیر واقعی** چاپ می‌کند:

توکن بله در `.env` با کلید `BALE_TOKEN_BOT` نگه داشته می‌شود و `BALE_API_URL`
در فایل override از همان ساخته می‌شود — توکن در هیچ فایل مخزن یا JSON نیست.

```bash
bash 03_ops/setup_env.sh          # پر کردن BALE_TOKEN_BOT و متغیرهای لازم
bash 00_audit/audit_postgres.sh                                  # فقط خواندن
APP_PASSWORD="$(openssl rand -base64 18)" bash 03_ops/deploy_sql.sh  # ساختار + منطق
bash 03_ops/import_workflows.sh import     # فقط گردش‌کارها را وارد می‌کند
bash 03_ops/activate_all.sh                # کارت اعتبارنامه + انتشار + ری‌استارت + بررسی
bash 03_ops/smoke_test.sh                  # آزمون دود: توکن، گردش‌کارها، تازگی دریافت
```

> [!tip] اگر `preflight.sh` گفت «هیچ سرویس در حال اجرا نیست»
> این یعنی PostgreSQL واقعاً بالاست یا نه — نه اینکه اسکریپت اشتباه کرده باشد.
> `docker ps` را ببینید؛ اگر کانتینر `postgres` هست ولی `exited` است، لاگش را بخوانید:
> `docker logs --tail 30 <container>`. سپس `cd ~/xennic-infra && docker compose up -d`.

رمز ساخته‌شده در `~/.iee1405-app-password` ذخیره می‌شود تا کارت اعتبارنامه n8n را با آن بسازید.

> [!note] چرا `--branch`
> این بسته فعلاً روی شاخه `arena/011e185b-znny-xennic-vault` است (PR #75).
> با `git clone` ساده، شاخه `dev` گرفته می‌شود و پوشه `iee1405-deploy` **وجود ندارد**.
> پس از ادغام PR، دستور ساده `git clone` کافی خواهد بود.

### اگر قبلاً مخزن را روی سرور دارید

```bash
cd ~/ZNNY-Xennic-Vault
git fetch origin arena/011e185b-znny-xennic-vault
git checkout arena/011e185b-znny-xennic-vault
git pull --ff-only origin arena/011e185b-znny-xennic-vault
cd iee1405-deploy && bash 03_ops/preflight.sh
```

> [!important] بعد از هر به‌روزرسانی، SQL را دوباره اعمال کنید
> فایل‌های `01_sql/` **بی‌خطر و تکرارپذیر** هستند (بدون حذف داده). تغییر توابع
> ربات و سلامت فقط با اجرای دوباره اعمال می‌شود:
>
> ```bash
> bash 03_ops/deploy_sql.sh
> bash 03_ops/import_workflows.sh import
> bash 03_ops/activate_all.sh
> ```

---

## ۰.۱. جدول مراحل

| مرحله | دستور | زمان |
|---|---|---|
| ۰. بررسی پیش‌نیازها | `bash 03_ops/preflight.sh` | ۳۰ ثانیه |
| ۱. بازرسی وضعیت فعلی | `bash 00_audit/audit_postgres.sh` | ۱ دقیقه |
| ۲. استقرار ساختار + منطق | `PG_DB=<db> bash 03_ops/deploy_sql.sh` | ۱ دقیقه |
| ۳. ایمپورت گردش‌کارها | `bash 03_ops/import_workflows.sh import` | ۲ دقیقه |
| ۴. اعتبارنامه + انتشار + ری‌استارت | `bash 03_ops/activate_all.sh` | ۲ دقیقه |
| ۵. آزمون دود | `bash 03_ops/smoke_test.sh` | ۳۰ ثانیه |
| ۶. ثبت گوشی‌ها | ارسال `/start` از بله، سپس `UPDATE crm.users …` | ۲ دقیقه |

---

## ۰.۲. خطاهای رایج در گام صفر

| پیام | معنا | راه‌حل |
|---|---|---|
| `ssh: connect ... port 33878: Connection timed out` | از داخل سرور به خودش SSH زده‌اید (یا از شبکه‌ای که پورت بسته است) | اگر `whoami` = `xennic` و `hostname` = `server2085`، همین‌جا هستید؛ `ssh` را حذف کنید |
| `fatal: repository '…' does not exist` | جای‌نگهدار `…` عیناً وارد شده | آدرس کامل را از بخش ۰ کپی کنید |
| `bash: 00_audit/...: No such file or directory` | clone انجام نشده یا از پوشه اشتباه اجرا شده | `cd ~/ZNNY-Xennic-Vault/iee1405-deploy` سپس دوباره |
| `iee1405-deploy` بعد از clone نیست | شاخه پیش‌فرض (`dev`) گرفته شده | `--branch arena/011e185b-znny-xennic-vault --single-branch` |

---

## ۱. بازرسی (بدون هیچ تغییری)## ۱. بازرسی (بدون هیچ تغییری)

```bash
cd ~/iee1405-deploy
bash 00_audit/audit_postgres.sh
```

خروجی در `00_audit/out/<timestamp>/`:

| فایل | کاربرد |
|---|---|
| `audit-report.md` | خلاصه خوانا + یافته‌های خودکار + گام بعدی |
| `audit-raw.txt` | خروجی کامل psql (برای پیوست به مستندات) |
| `audit-*.json` | داده ساخت‌یافته برای مقایسه قبل/بعد |
| `host-info.txt` | وضعیت Docker، نسخه n8n، دیسک، فایروال |

**چه چیزی بررسی می‌شود:** نسخه PostgreSQL، پسوندها، دیتابیس‌ها، نقش‌ها،
schemaهای موجود (تعارض با `crm`/`iee1405`)، محدودیت اتصال، تنظیمات کلیدی،
`listen_addresses` (نباید عمومی باشد)، وضعیت بکاپ، و نسخه n8n.

روی این سرور اطلاعات از پیش موجود، خروجی گزارش تعیین می‌کند که
استقرار بی‌خطر است یا اول باید پشتیبان گرفت.

---

## ۲. استقرار ساختار پایگاه‌داده

```bash
# نام دیتابیس فعلی سرویس postgres را تأیید کنید:
docker compose -f ~/xennic-infra/docker-compose.yml exec -T postgres psql -U postgres -l

# سپس (اگر نام دیتابیس xennic نیست، PG_DB را عوض کنید):
PG_DB=xennic APP_PASSWORD='<رمز-قوی>' bash 03_ops/deploy_sql.sh
```

چه چیزی ساخته می‌شود:

| فایل | محتوا |
|---|---|
| `01_schema_core.sql` | ۲ schema (`crm` دائمی + `iee1405` نمایشگاهی)، ۲۰+ جدول، enumها، تریگرها، ممیزی |
| `02_seed_reference.sql` | ۱۵ دسته محصول (همان کدهای فرم‌های PRJ-IEE-014)، رکورد نمایشگاه ۱۴۰۵، کاربران سرویس |
| `03_views.sql` | نماهای گزارش: کارت شرکت، وظایف باز، خلاصه روز، کیفیت داده، خروجی اکسل |
| `04_bot_logic.sql` | منطق کامل ربات + متن پیام‌ها در جدول `bot_messages` |
| `05_ops_helpers.sql` | offset، صف ارسال، یادآور، خلاصه، سلامت، تحویل تضمین‌شده |
| `06_roles.sql` | نقش `iee_app` (بدون DDL و بدون DELETE)، `iee_panel`، `iee_report` |

همه فایل‌ها **idempotent** هستند: اجرای دوباره چیزی را خراب نمی‌کند.

### چرا منطق ربات در SQL است؟

چون می‌توان آن را **واقعاً آزمایش کرد** — کاری که در طراحی همین بسته انجام شد
(۲۴ آزمون سرتاسری روی PostgreSQL واقعی). مزیت‌های دیگر:

- یک منبع حقیقت: ربات، پنل WordPress و Field API آینده همه از یک منطق استفاده می‌کنند
- تغییر متن پیام‌ها با یک `UPDATE` در `bot_messages`، بدون استقرار مجدد
- n8n ساده می‌ماند (۹ گره) و خطای پیکربندی در آن کم می‌شود

---

## ۳. ایمپورت گردش‌کارهای n8n

### پیش‌نیاز: متغیرهای محیطی

```bash
cd ~/xennic-infra
cp /path/to/iee1405-deploy/03_ops/docker-compose.override.yml .
cp /path/to/iee1405-deploy/03_ops/env.example .env    # و مقادیر را پر کنید
docker compose up -d n8n
```

حداقل‌های لازم در `.env`:

```env
BALE_API_URL=https://tapi.bale.ai/bot<TOKEN>
N8N_BLOCK_ENV_ACCESS_IN_NODE=false
GENERIC_TIMEZONE=Asia/Tehran
```

### ایمپورت

```bash
bash 03_ops/import_workflows.sh import
bash 03_ops/import_workflows.sh list
```

چهار گردش‌کار:

| فایل | نام در n8n | زمان‌بندی | کار |
|---|---|---|---|
| `wf-01-bale-ingest.json` | IEE1405-01 — دریافت پیام‌های بله | هر ۲۰ ثانیه | getUpdates → ثبت در PG → پاسخ |
| `wf-02-reminders.json` | IEE1405-02 — یادآور پیگیری‌ها | روزانه ۰۷:۳۰ | پیگیری‌های سررسید تا ۳ روز |
| `wf-03-digest.json` | IEE1405-03 — خلاصه پایان روز | روزانه ۲۰:۳۰ | آمار روز + نزدیک‌ترین پیگیری‌ها |
| `wf-04-health.json` | IEE1405-04 — پایش سلامت | هر ۳۰ دقیقه | فقط وقتی مشکل هست هشدار می‌دهد |

### اتصال اعتبارنامه + فعال‌سازی (یک دستور)

در n8n 2.x دستور `update:workflow --active=true` منسوخ شده و کار نمی‌کند؛
راه درست `publish:workflow` است و **بعد از انتشار باید n8n ری‌استارت شود**،
وگرنه تغییرات اعمال نمی‌شوند. `activate_all.sh` همین‌ها را انجام می‌دهد:

1. کارت اعتبارنامه `Xennic PostgreSQL` (شناسه `XENNIC-PG-CREDENTIAL`) را با
   رمز `~/.iee1405-app-password` داخل کانتینر n8n می‌سازد
2. هر چهار گردش‌کار `IEE1405*` را منتشر می‌کند
3. `docker compose restart n8n` و انتظار تا بالا آمدن
4. تعداد گردش‌کارهای فعال و تازگی `last_poll_at` را بررسی می‌کند

```bash
bash 03_ops/activate_all.sh
```

خروجی موفق:

```
[ OK ] اعتبارنامه XENNIC-PG-CREDENTIAL
[ OK ] انتشار: 4 گردش‌کار
[ OK ] فعال: 4 از 4
[ OK ] دریافت پیام‌ها فعال است (last_poll_at تازه شد)
```

> [!important] اگر «فعال: 0 از 4» دیدید
> یعنی `publish` انجام شده ولی n8n ری‌استارت نشده، یا متغیر
> `N8N_RUNNERS_ENABLED`/`N8N_BLOCK_ENV_ACCESS_IN_NODE` در `.env` مانع شده است.
> `docker compose restart n8n` را دستی بزنید و دوباره اسکریپت را اجرا کنید.

---

## ۳.۵. آزمون دود (بعد از هر تغییر)

```bash
bash 03_ops/smoke_test.sh                    # فقط بررسی
bash 03_ops/smoke_test.sh --test-message     # + یک پیام آزمایشی به بله
```

چه چیزهایی را چک می‌کند:

| بررسی | معنی خطا |
|---|---|
| `getMe` بله | توکن نامعتبر است — **یا** سرور به `tapi.bale.ai` دسترسی ندارد (اسکریپت این دو را تفکیک می‌کند) |
| گردش‌کارهای فعال | `activate_all.sh` اجرا نشده یا n8n ری‌استارت نشده |
| تازگی `last_poll_at` | wf-01 اجرا نمی‌شود؛ اگر «تازه است ولی خطا دارد» یعنی بله پاسخ نمی‌دهد |
| کاربران با `bale_chat_id` | گوشی‌ها ثبت نشده‌اند (بخش ۴) |
| شمارش داده‌ها | ساختار سالم است، هنوز چیزی ثبت نشده |

> [!tip] «سکوت» با «قطعی» اشتباه نمی‌شود
> wf-01 در هر اجرا — حتی وقتی هیچ پیام جدیدی نیست — زمان دریافت را ثبت می‌کند
> (`poll_advance`). اگر `getUpdates` خطا بدهد، شاخه خطا آن را در `bot_errors`
> ثبت می‌کند و `/status` علت را نشان می‌دهد.

---

## ۳.۶. اگر ربات جواب نمی‌دهد — تشخیص یک‌دستوری

```bash
bash 03_ops/diagnose_n8n.sh        # فقط خواندن
```

این اسکریپت به **دیتابیس خود n8n** نگاه می‌کند (نه به خروجی CLI) و پنج چیز را می‌گوید:

| بخش | چه چیزی را نشان می‌دهد |
|---|---|
| ۱ | هر گردش‌کار: `active` و `activeVersionId` — «فعال ولی بدون نسخه منتشرشده» یعنی انتشار اثر نکرده |
| ۲ | آیا کارت `XENNIC-PG-CREDENTIAL` در `credentials_entity` هست؟ نبودنش = خطای همه گره‌های SQL |
| ۳ | آخرین اجراها و **نام گره + متن خطا** (مثلاً `password authentication failed`) |
| ۴ | `last_poll_at` / `last_error` / شمار پیام‌ها |
| ۳.۱ | متن خام `execution_data` آخرین اجراهای ناموفق — برای دیدن پیام دقیق خطا |
| ۵ | گام بعدی بر اساس همان تشخیص |

> [!warning] ایمپورت دوباره، گردش‌کار تکراری می‌سازد مگر شناسه ثابت باشد
> فایل‌های `02_n8n/wf-*.json` از این نسخه شناسه ثابت دارند (`IEE1405-01` … `IEE1405-04`).
> بدون شناسه ثابت، هر ایمپورت یک گردش‌کار **تازه** می‌ساخت و نسخه قبلی هم فعال می‌ماند
> (دو بار `getUpdates` و پیام تکراری). `activate_all.sh` گردش‌کارهای تکراری قدیمی را
> غیرفعال می‌کند و شناسه‌ها را از خود فایل‌ها می‌خواند، نه از خروجی CLI.

> [!important] چرا «فعال» بودن در CLI کافی نیست
> سه حالت مختلف، یک نشانه دارند (ربات ساکت است و `last_poll_at` خالی):
> ۱) انتشار انجام شده ولی n8n ری‌استارت نشده؛ ۲) کارت اعتبارنامه ساخته نشده؛
> ۳) رمز `iee_app` با رمز داخل کارت یکی نیست. `diagnose_n8n.sh` این سه را از هم جدا می‌کند.

---

## ۴. ثبت گوشی‌ها

هر گوشی یک‌بار به بله وصل می‌شود:

1. در بله، ربات را باز کنید و `/start` بفرستید
2. ربات پاسخ می‌دهد: «این حساب مجاز نیست. شناسه گفت‌وگوی شما: **12345678**»
3. روی VPS:

```sql
-- گوشی اول (مدیر)
UPDATE crm.users SET bale_chat_id = 12345678 WHERE username = 'ahmad';
-- گوشی دوم (همکار)
UPDATE crm.users SET bale_chat_id = <شناسه دوم> WHERE username = 'field-1';
```

اجرا:

```bash
docker compose -f ~/xennic-infra/docker-compose.yml exec -T postgres \
  psql -U postgres -d xennic -c "UPDATE crm.users SET bale_chat_id=12345678 WHERE username='ahmad';"
```

سپس در بله `/help` بفرستید. اگر راهنما آمد، همه‌چیز وصل است.

**دو گوشی، یک منبع داده:** هر دو گوشی به همان دیتابیس می‌نویسند.

---

## ۵. دستورهای ربات

| دستور | کار | میان‌بر |
|---|---|---|
| `/new` | ثبت شرکت جدید (نام → دسته → غرفه) | ن |
| `/find نام` | جست‌وجوی شرکت | ج |
| `/org ORG-000123` | پرونده شرکت | ع |
| `/log ORG-000123 \| خلاصه \| اقدام بعدی` | ثبت مذاکره (+ پیگیری خودکار) | م |
| `/cap ORG-000123 \| متن توانمندی` | ثبت توانمندی (سطح: reported) | — |
| `/visit ORG-000123` | ثبت بازدید | و |
| `/task ORG-000123 \| عنوان \| ۳` | پیگیری با سررسید | پ |
| `/today` | خلاصه امروز | — |
| `/cancel` | لغو جریان جاری | — |

**اصول داده (PRJ-IEE-012):** هر ادعا سطح دارد (`verified | reported | inferred | observed`).
ربات همیشه `reported` می‌نویسد — چیزی که در نمایشگاه شنیده شده، تأییدشده نیست.
هیچ خروجی هوش مصنوعی به‌عنوان واقعیت ثبت نمی‌شود.

---

## ۶. آزمایش پس از استقرار

```bash
# ۱) بررسی ساختار و سلامت
PG_DB=xennic bash 03_ops/deploy_sql.sh --verify-only

# ۲) اجرای آزمون‌های محلی (نیاز به پایگاه‌داده آزمایشی ندارد اگر روی VPS اجرا شود)
#    این آزمون‌ها تراکنشی هستند و همه‌چیز را ROLLBACK می‌کنند.

# ۳) آزمون دستی از بله:
/start
/new            → نام یک شرکت آزمایشی
1               → دسته
12-34           → غرفه
/org ORG-000001
/log ORG-000001 | آزمون | پیگیری آزمایشی
/today
```

پس از آزمون، داده آزمایشی را پاک کنید:

```sql
BEGIN;
DELETE FROM crm.interactions WHERE organization_id IN
  (SELECT id FROM crm.organizations WHERE legal_name LIKE '%آزمون%');
DELETE FROM crm.tasks WHERE organization_id IN
  (SELECT id FROM crm.organizations WHERE legal_name LIKE '%آزمون%');
DELETE FROM iee1405.participations WHERE organization_id IN
  (SELECT id FROM crm.organizations WHERE legal_name LIKE '%آزمون%');
DELETE FROM crm.claims WHERE subject_id IN
  (SELECT id FROM crm.organizations WHERE legal_name LIKE '%آزمون%');
DELETE FROM crm.organizations WHERE legal_name LIKE '%آزمون%';
COMMIT;
```

---

## ۷. بازگشت (Rollback)

| چه چیزی | چگونه |
|---|---|
| گردش‌کار n8n | در رابط n8n غیرفعال کنید؛ یا `bash 03_ops/import_workflows.sh activate` روی نسخه قبلی |
| داده | `bash 03_ops/backup_now.sh` قبل از هر تغییر؛ آزمون بازگردانی با `bash 03_ops/restore_test.sh` |
| ساختار | ساختار additive است؛ برای حذف کامل فقط در محیط آزمایشی: `DROP SCHEMA iee1405 CASCADE;` — `crm` را حذف نکنید |

بازگردانی آزمایشی (هرگز مستقیم روی تولید):

```bash
docker compose -f ~/xennic-infra/docker-compose.yml exec -T postgres \
  psql -U postgres -c "CREATE DATABASE restore_test;"
docker compose -f ~/xennic-infra/docker-compose.yml exec -T postgres \
  pg_restore -U postgres -d restore_test --no-owner < ~/xennic-backups/iee-*.dump
```

---

## ۸. عیب‌یابی

| نشانه | علت محتمل | راه‌حل |
|---|---|---|
| ربات جواب نمی‌دهد | گردش‌کار ۰۱ فعال نیست | `bash 03_ops/activate_all.sh` |
| `401 Unauthorized` از بله | `BALE_API_URL` غلط | توکن را در `.env` بررسی و `docker compose up -d n8n` |
| `Access to env vars denied` | `N8N_BLOCK_ENV_ACCESS_IN_NODE` تنظیم نشده | override را اعمال و ری‌استارت کنید |
| `password authentication failed` | رمز `iee_app` | `APP_PASSWORD=... bash 03_ops/deploy_sql.sh` دوباره |
| پیام تکراری می‌آید | `delivered_at` ثبت نشده | گردش‌کار ۰۱ را بررسی کنید؛ `pending_replies` تمیز می‌شود |
| زمان‌بندی جابه‌جاست | TZ | `GENERIC_TIMEZONE=Asia/Tehran` |
| `permission denied for table` | اجرای دستی با `iee_app` | با `postgres` اجرا کنید؛ `iee_app` فقط توابع را اجرا می‌کند |
| `/status` می‌گوید «دریافت پیام‌ها در ۱۰ دقیقه گذشته اجرا نشده» | wf-01 غیرفعال، n8n ری‌استارت‌نشده، یا خطای گره | `bash 03_ops/diagnose_n8n.sh` |
| `/status` می‌گوید «آخرین دریافت خطا داد» | سرور به `tapi.bale.ai` نمی‌رسد (فیلتر/شبکه) | `bash 03_ops/smoke_test.sh` و سپس بررسی DNS/پروکسی |
| `activate_all.sh`: «رمز یافت نشد» | `~/.iee1405-app-password` نیست | `bash 03_ops/deploy_sql.sh` را یک بار اجرا کنید |

بررسی سریع سلامت:

```sql
SELECT iee1405.health_text();
SELECT * FROM iee1405.pending_replies();
SELECT count(*), status FROM iee1405.bot_updates GROUP BY 2;
SELECT * FROM iee1405.bot_errors ORDER BY occurred_at DESC LIMIT 5;
```

---

## ۹. ساختار پوشه‌ها

```
iee1405-deploy/
├── 00_audit/          بازرسی فقط-خواندنی PostgreSQL
├── 01_sql/            ساختار، بذر، نماها، منطق ربات، توابع عملیاتی، نقش‌ها
├── 02_n8n/            سازنده و اعتبارسنج گردش‌کارها + ۴ فایل JSON
└── 03_ops/            استقرار، پشتیبان، ایمپورت، آزمون‌ها، .env نمونه
```

---

## ۱۰. قواعد ثابت این بسته

- هیچ رمز یا توکنی در فایل‌های این پوشه نیست (فقط `<TOKEN>` جای‌نگهدار)
- PostgreSQL هرگز روی اینترنت باز نمی‌شود (فقط `127.0.0.1` و شبکه Docker)
- WordPress هرگز مستقیم به PostgreSQL وصل نمی‌شود (فقط Field API)
- یک پایگاه‌داده، یک منبع حقیقت — دیتابیس موقت نمایشگاهی ساخته نمی‌شود
- همه نوشتن‌ها در `crm.audit_events` ثبت می‌شود
