---
id: META-INT-110
title: زیرساخت به‌صورت کد و بازیابی پس از خرابی
status: review
created: 2026-10-22
tags: [integration, infrastructure, iac, disaster-recovery, docker, governance, git-automation]
layer: Meta
domain: INT
owner: احمد فیروزمندی بندپی
version: 0.3.0
dependencies: [META-INT-080, META-INT-050, META-INT-070, META-INT-090, META-INT-100, META-INT-130, META-INT-140]
---

# زیرساخت به‌صورت کد و بازیابی پس از خرابی

> [!abstract] هدف
> مستندسازی وضعیت فعلی زیرساخت اتوماسیون (n8n، Qdrant، TEI Embedding، Open Notebook، Hermes) و تعریف **دستورالعمل اجرایی مشخص** برای نسخه‌بندی خودکار همه تنظیمات ضروری این ابزارها در Git — دقیقاً با همان الگویی که `obsidian-git` برای خود Vault پیاده کرده، اما برای بقیه ابزارها.

## فهرست

| # | بخش | # | بخش |
|---|---|---|---|
| ۱ | هدف (Why) | ۷ | روش پیاده‌سازی پیشنهادی (دستورالعمل اجرایی) |
| ۲ | وضعیت فعلی (As-Is) | ۸ | برنامه بازیابی پس از خرابی (DR) |
| ۳ | ریسک تک‌نقطه‌ای بودن | ۹ | نقشه راه اجرایی |
| ۴ | دارایی‌هایی که باید در Git نسخه‌بندی شوند | ۱۰ | شکاف‌های شناسایی‌شده |
| ۵ | دارایی‌هایی که نباید در Git باشند (یا باید رمزنگاری‌شده باشند) | ۱۱ | اقدامات |
| ۶ | چرا Obsidian الگوی مرجع است | ۱۲ | ارجاعات |
| | | ۱۳ | Changelog |

---

## ۱. هدف (Why)

مستندسازی وضعیت فعلی زیرساخت اتوماسیون (n8n، Qdrant، TEI Embedding، Open Notebook، Hermes) و تعریف **دستورالعمل اجرایی مشخص** برای نسخه‌بندی خودکار همه تنظیمات ضروری این ابزارها در Git — دقیقاً با همان الگویی که `obsidian-git` برای خود Vault پیاده کرده، اما برای بقیه ابزارها.

این نود خروجی مستقیم فاز ۰ («شناخت اتصال واقعی چهار ابزار، نسخه‌ها، دسترسی‌ها ... و نقاط شکست») در [[META-INT-080 — معماری کلان سیستم‌عامل هوشمند سازمانی Xennic|META-INT-080]] (بند ۱۱) است و پیاده‌سازی عملی فاز C نقشه راه فنی در [[META-INT-130 — معماری هدف و نقشه راه مدرن‌سازی زیرساخت اتوماسیون و RAG|META-INT-130]] محسوب می‌شود.

> [!success] به‌روزرسانی ۱۴۰۵-۰۸-۰۶ — بخش ۷ کاملاً بازنویسی شد برای معماری واقعی VPS
> نسخهٔ قبلی بخش ۷ (v0.2.x) بر پایهٔ محیط Windows + Docker Desktop + گره `Execute Command` + ابزار خارجی `age` نوشته شده بود. پس از مهاجرت کامل به VPS لینوکسی (طبق [[META-INT-140 — نقشه مهاجرت زیرساخت اتوماسیون به سرور اختصاصی (VPS)|META-INT-140]]) و تصمیم معماری ثابت «غیرفعال نگه‌داشتن گره `Execute Command`»، آن روش دیگر **قابل اجرا نیست**. بخش ۷ اکنون طراحی کامل `[OPS-01] Nightly Infra Export` را بر پایهٔ **n8n Public API + گره Git بومی (همان الگوی از پیش ساخته‌شده و تست‌شدهٔ مخزن `xennic-infra-backups`)** ارائه می‌دهد — بدون نیاز به هیچ ابزار CLI خارجی یا باز کردن گره‌های پرخطر.

> [!success] به‌روزرسانی ۱۴۰۵-۰۷-۳۰ — از «برنامه‌ریزی» به «دستورالعمل اجرایی»
> نسخه قبلی این نود فقط شکاف‌ها را فهرست می‌کرد. این نسخه یک **روش مشخص، قابل‌اجرا و متناسب با محیط واقعی مالک** (Windows + Docker Desktop + تک‌اپراتور) ارائه می‌دهد (بخش ۷)، چون این زیرساخت قرار است پایه توسعه آینده و پیوستن افراد جدید به تیم باشد — نه فقط یک آزمایش شخصی (طبق تصمیم مالک، ثبت‌شده در بخش ۹ META-INT-130).
> 
> ⚠️ **یادداشت تاریخی:** جملهٔ «Windows + Docker Desktop» در بالا دیگر صادق نیست؛ زیرساخت از آن زمان به یک VPS لینوکسی منتقل شده (META-INT-140). این Callout فقط برای حفظ تاریخچهٔ تصمیم نگه داشته شده است.

---

## ۲. وضعیت فعلی (As-Is)

> [!warning] جدول زیر مربوط به دوران قبل از مهاجرت است
> جدول این بخش عکس‌وضعیت دورهٔ «یک کامپیوتر شخصی Windows» است و **عمداً دست‌نخورده نگه داشته شده** تا سیر تحول معماری قابل ردیابی بماند (اصل Auditability، META-INT-080 بند ۲.۳). وضعیت واقعی و به‌روز زیرساخت (VPS لینوکسی، نام‌های Container فعلی مثل `xennic-infra-n8n-1`/`xennic-infra-surrealdb-1`/`xennic-infra-open_notebook-1`، و مخزن `xennic-infra-backups` از پیش بوت‌استرپ‌شده) در [[META-INT-140 — نقشه مهاجرت زیرساخت اتوماسیون به سرور اختصاصی (VPS)|META-INT-140]] مستند است. بخش ۷ همین نود (OPS-01) بر پایهٔ معماری **فعلی** VPS طراحی شده، نه جدول زیر.

بر اساس [[META-INT-050 — راه‌اندازی کامل Hermes|META-INT-050]] و [[META-INT-070 — نقشه Open Notebook برای n8n و Hermes|META-INT-070]]، زیرساخت فعلی چنین است:

| سرویس | نسخه | محل اجرا | نحوه نصب |
|---|---|---|---|
| n8n | v2.42.6 | کانتینر Docker (`xennic-n8n` + `xennic-n8n-db` Postgres) روی یک کامپیوتر Windows | Docker (تأییدشده — طبق [[META-INT-090 — رجیستری Workflowهای n8n\|META-INT-090]]) |
| Qdrant | v1.18.3 | همان کامپیوتر، `localhost:6333` | Docker |
| TEI (Text Embeddings Inference) | v1.9.4 | همان کامپیوتر، `localhost:8001` | Docker |
| Open Notebook | v1.15.0 | کانتینر Docker (`open-notebook-open_notebook-1` + `open-notebook-surrealdb-1`) | Docker |
| Hermes Desktop App | نسخه نصب‌شده نامشخص | همان کامپیوتر (Windows، کاربر Narges)، `config.yaml` محلی | نصب دستی برنامه Desktop |
| Obsidian Vault (این مخزن) | — | همان کامپیوتر + GitHub | Git، Commit خودکار هر ۱۰ دقیقه (`obsidian-git`) |

**نتیجه**: از ۶ مؤلفه اصلی، فقط Obsidian Vault واقعاً در کنترل نسخه و قابل بازسازی خودکار است. بقیه (شامل تمام Workflowها، Credentialها، بسته‌های Community نصب‌شده و تنظیمات Hermes) فقط در دیتابیس داخلی هر ابزار یا یک فایل محلی زندگی می‌کنند.

---

## ۳. ریسک تک‌نقطه‌ای بودن (Single Point of Failure)

> [!danger] ریسک اصلی
> اگر این یک کامپیوتر خراب شود، دزدیده شود یا سیستم‌عامل آن نیاز به نصب مجدد پیدا کند، **تمام زیرساخت RAG، n8n و Open Notebook از بین می‌رود** و فقط محتوای متنی Obsidian (که در GitHub است) قابل بازیابی است. پیکربندی Qdrant Collection، Workflowهای n8n، بسته‌های Community نصب‌شده و تنظیمات Open Notebook باید از صفر و از حافظه بازسازی شوند.

این دقیقاً همان ریسکی است که اصل «Auditability» و «Continuous Improvement» در META-INT-080 (بند ۲.۳) برای جلوگیری از آن طراحی شده‌اند. علاوه بر ریسک فنی، این وابستگی کامل به حافظه یک نفر مستقیماً با هدف جدید مالک («تبدیل‌شدن به یک تیم کامل») در تضاد است: بدون IaC واقعی، هیچ عضو جدید تیم نمی‌تواند این زیرساخت را بدون نشستن کنار مالک فعلی بازسازی یا درک کند.

---

## ۴. دارایی‌هایی که باید در Git نسخه‌بندی شوند

| دارایی | ابزار | وضعیت فعلی | وضعیت هدف | ضروری؟ |
|---|---|---|---|---|
| Workflowهای n8n (export JSON) | n8n | ❌ نسخه‌بندی نمی‌شوند | ✅ هر Workflow به‌صورت JSON در `n8n/workflows/` | 🔴 ضروری |
| فهرست Credentialهای n8n (نام/نوع، بدون مقدار) | n8n | ❌ نسخه‌بندی نمی‌شوند | ✅ `n8n/credentials-manifest.json` (همان خروجی `export:credentials` — مقدار همیشه رمزگذاری‌شده می‌ماند) | 🔴 ضروری |
| **فهرست بسته‌های Community نصب‌شده** (مثلاً `n8n-nodes-bale-messenger-alpha`) | n8n | ✅ از نسخهٔ ۰.۳.۰ این نود، طراحی `[OPS-01]` این را پوشش می‌دهد (بخش ۷.۳) | ✅ `n8n/community-packages.json` (خروجی `GET /api/v1/community-packages`) | 🔴 ضروری (بدون این، بازسازی کانتینر یعنی شکستن `[KNW-02]` به‌خاطر نبود گره Bale Messenger) |
| `docker-compose.yml` برای n8n + Qdrant + TEI + Open Notebook (نسخه‌های دقیق Image) | همه | ❌ وجود ندارد | ✅ `infra/docker-compose.yml` واحد | 🔴 ضروری |
| اسکیمای Qdrant Collection (نام، ابعاد، Distance، Indexها) | Qdrant | ✅ در META-INT-020 به‌صورت متن مستند است، ❌ اسکریپت اجرایی ندارد | ✅ اسکریپت ایجاد Collection در `00_Meta/Scripts/` یا `infra/scripts/` | 🟡 مهم |
| نقشه Notebook IDs (`notebook_map.json`، به‌جز بخش Corporate) | Open Notebook | ✅ در META-INT-070 به‌صورت متن مستند است؛ فایل اصلی فقط محلی است | ✅ خود فایل JSON (غیرمحرمانه) در مخزن | 🟡 مهم |
| Dump کامل SurrealDB (ساختار Notebookها، Sourceها، تنظیمات مدل) | Open Notebook | ❌ وجود ندارد | ✅ فقط **رمزنگاری‌شده** (بخش ۵) | 🔴 ضروری، ولی مشروط به رمزنگاری |
| `config.yaml` هرمس | Hermes | ❌ نسخه‌بندی نمی‌شود | ✅ `hermes/config.yaml` (قبلاً تأیید شد که کلید خام ندارد — META-INT-100) | 🔴 ضروری |
| خروجی `hermes mcp list` (عکس وضعیت ابزارهای مجاز) | Hermes | ❌ ثبت نمی‌شود | ✅ `hermes/mcp-list-snapshot.txt` — سند شواهد برای Authority Matrix (META-INT-080 بند ۷) | 🟡 مهم |
| قالب `.env.example` (بدون مقدار واقعی) برای همه سرویس‌ها | همه | ❌ وجود ندارد | ✅ لیست متغیرهای محیطی لازم بدون مقدار، برای بازسازی سریع | 🔴 ضروری |

---

## ۵. دارایی‌هایی که نباید در Git باشند (یا باید رمزنگاری‌شده باشند)

- هیچ Secret/Credential واقعی به‌صورت متن ساده (طبق [[META-INT-100 — مدیریت Secrets و Credentials|META-INT-100]]) — ارزش رمزگذاری‌شده داخلی n8n Credentials بلامانع است، چون بدون کلید رمزگشایی اصلی n8n قابل استفاده نیست.
- محتوای Notebook `Corporate` (اسناد محرمانه شرکت — طبق META-INT-070) — **هرگز به‌صورت متن ساده در هیچ Dump یا Export قرار نگیرد.**
- Dump کامل SurrealDB: چون این Dump هم شامل Notebookهای عمومی و هم `Corporate` می‌شود و امکان فیلتر دقیق در سطح Export وجود ندارد، **باید همیشه پیش از نوشتن روی دیسک یا Git، با ابزار رمزنگاری رمزنگاری شود** (بخش ۷.۳) — نه این‌که اصلاً نسخه‌بندی نشود.
- داده‌های واقعی Qdrant (Vectorها)، فقط اسکیمای ساخت Collection نسخه‌بندی می‌شود، نه خود Vectorها (قابل بازسازی از Open Notebook + n8n).

---

## ۶. چرا Obsidian الگوی مرجع است

`obsidian-git` دقیقاً سه ویژگی دارد که این نود می‌خواهد برای بقیه ابزارها هم تکرار کند:

۱. **خودکار بودن کامل** — بدون نیاز به یادآوری دستی روزانه (هر ۱۰ دقیقه Commit می‌شود).
۲. **بدون نیاز به دانش عمیق Git از کاربر نهایی** — فقط یک افزونه نصب و فعال شده است.
۳. **مرجع واحد و قابل بازیابی** — در صورت از دست رفتن کامپیوتر، کل Vault از GitHub قابل Clone است.

مشکل این است که n8n، Hermes و Open Notebook معادل `obsidian-git` ندارند. بخش ۷ همین معادل را برای هرکدام طراحی می‌کند.

---

## ۷. روش پیاده‌سازی پیشنهادی (دستورالعمل اجرایی)

> [!important] تصمیم معماری اصلی: یک مخزن Git جداگانه برای Backupهای عملیاتی
> این Backupها در یک **مخزن Git کاملاً جدا** (`xennic-infra-backups`، خصوصی — از پیش بوت‌استرپ‌شده و متصل با Deploy Key اختصاصی) نگهداری می‌شوند، **نه در همین مخزن `ZNNY-Xennic-Vault`**. دلیل:
> - این مخزن (Vault) برای **محتوای مرور و تأییدشده** است که هر تغییرش از طریق PR بررسی می‌شود (طبق [[META-CONV-001 — قواعد توسعه پروژه|META-CONV-001]])؛ Backup خام JSON/SurrealQL هرشب نیازی به بازبینی انسانی ندارد و فقط شلوغی تاریخچه Git و PRها را زیاد می‌کند.
> - امکان سیاست دسترسی/نگهداری جدا بدون اثرگذاری روی مخزن اصلی مستندات.
> - با قانون «هیچ Automation نباید مستقیماً روی `dev`/`main` همین Vault Commit کند» کاملاً سازگار است.

> [!important] تصمیم معماری دوم: n8n Public API به‌جای Execute Command/CLI
> روی این instance از n8n، گره `Execute Command` **عمداً و به‌صورت دائمی غیرفعال نگه داشته شده** (تصمیم امنیتی ثابت پروژه). پس روش قدیمی `n8n export:workflow`/`n8n export:credentials`/`surreal export` (که همگی دستورات CLI هستند) از اساس قابل اجرا نیست. به‌جای آن، `[OPS-01]` از **n8n Public API** (گره‌های `HTTP Request` با Credential از نوع «n8n API») برای خواندن داده‌ها، و از گره بومی **Git** (همان که برای Push اولیهٔ `xennic-infra-backups` ساخته و تست شده) برای Commit/Push استفاده می‌کند. هیچ ابزار CLI خارجی (نه `n8n`, نه `surreal`, نه `age`) در هیچ مرحله‌ای فراخوانی نمی‌شود.

### ۷.۱ ساختار مخزن Backup

```text
xennic-infra-backups/
├── n8n/
│   ├── workflows.json               # خروجی کامل GET /api/v1/workflows
│   ├── credentials-metadata.json    # فقط id/name/type — خروجی GET /api/v1/credentials (بدون مقدار)
│   └── community-packages.json      # خروجی GET /api/v1/community-packages
├── infra/
│   ├── docker-compose.yml           # کپی مستقیم از هاست
│   └── .env.example                 # نام متغیرها بدون مقدار واقعی
├── open-notebook/
│   └── surrealdb-open_notebook.sql.enc   # Dump رمزنگاری‌شدهٔ AES-256-GCM — بخش ۷.۴
└── README.md                        # تاریخ آخرین Backup موفق + دستورالعمل بازیابی
```

(اگر نام پوشه‌های واقعی مخزن از قبل‌ساخته‌شده کمی متفاوت است، همین الگو را روی ساختار موجود منطبق کنید؛ اصل مهم جداسازی per-tool است، نه نام دقیق پوشه.)

### ۷.۲ پیش‌نیازهای یک‌بارهٔ دستی (قبل از ساخت Workflow)

این مرحله فقط یک‌بار و دستی انجام می‌شود (نه بخشی از Workflow):

**الف) فعال‌سازی Public API و ساخت API Key**
در n8n UI: Settings → n8n API → Create an API Key. حداقل Scopeهای لازم: `workflow:list`, `workflow:read`, `credential:list`, `communityPackage:list`. سپس یک Credential جدید از نوع **«n8n API»** بسازید (Base URL: آدرس داخلی خود instance — معمولاً `http://localhost:5678`؛ API Key: مقدار تولیدشده).

**ب) Credential جداگانه برای SurrealDB (Basic Auth)**
یک Credential از نوع **«HTTP Basic Auth»** بسازید (مثلاً با نام `SurrealDB Root`) با `Username=root` و `Password=` مقدار واقعی `SURREAL_PASSWORD` فعلی سرویس. این کار باعث می‌شود پسورد هرگز داخل پارامترهای قابل‌مشاهدهٔ گره ذخیره نشود.

**پ) سه تغییر در `.env` روی هاست (`/home/xennic/xennic-infra/.env`)**
```bash
# افزودن این سه خط به .env (یک 32-بایتی تصادفی برای کلید رمزنگاری بسازید):
echo "NODE_FUNCTION_ALLOW_BUILTIN=crypto" >> .env
echo "N8N_RESTRICT_FILE_ACCESS_TO=/vault;/data/xennic-infra-backups;/data/compose-ro" >> .env
echo "INFRA_BACKUP_ENC_KEY=$(openssl rand -hex 32)" >> .env
```
- `NODE_FUNCTION_ALLOW_BUILTIN=crypto` ماژول built-in `crypto` را فقط برای Code Node مجاز می‌کند (نه `fs`، نه ماژول دیگری) — چون n8n این instance در حالت Task Runner داخلی (`N8N_RUNNERS_MODE=internal`) اجرا می‌شود، این متغیر مستقیماً روی Container اصلی n8n اثر می‌کند (بدون نیاز به فایل جدای `/etc/n8n-task-runners.json`).
- `N8N_RESTRICT_FILE_ACCESS_TO` را از `/vault` تک‌مقداره به سه مسیر (جداشده با `;`) گسترش می‌دهیم: `/vault` (فقط‌خواندنی، بدون تغییر)، `/data/xennic-infra-backups` (مسیر از پیش موجود و قابل‌نوشتن مخزن Backup)، و `/data/compose-ro` (مسیر جدید فقط‌خواندنی که در گام بعد Mount می‌شود).
- `INFRA_BACKUP_ENC_KEY` یک کلید تصادفی ۳۲ بایتی (۶۴ کاراکتر Hex) است که فقط برای رمزنگاری Dump سورئال استفاده می‌شود؛ چون `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` از قبل روی این instance تنظیم شده، Code Node می‌تواند آن را با `$env.INFRA_BACKUP_ENC_KEY` بخواند — بدون نیاز به `fs` یا یک Credential جداگانه.

> پس از اعمال، نسخهٔ قبلی `.env` طبق انضباط همیشگی پروژه باید Backup شود (`cp .env .env.bak.$(date +%Y%m%d-%H%M%S)`) — دقیقاً مثل تغییرات قبلی `.env` در این پروژه.

**ت) دو Bind Mount جدید در `docker-compose.yml` (سرویس `n8n`)**
```yaml
    volumes:
      # ... خطوط موجود دست‌نخورده می‌مانند ...
      - /home/xennic/xennic-infra/docker-compose.yml:/data/compose-ro/docker-compose.yml:ro
      - /home/xennic/xennic-infra/.env:/data/compose-ro/env-source:ro
```
> [!warning] ریسک امنیتی آگاهانه‌پذیرفته‌شده
> این یعنی `.env` واقعی (شامل پسورد SurrealDB، کلید رمزگذاری n8n، و غیره) برای اولین بار به‌صورت فقط-خواندنی در دسترس Container n8n قرار می‌گیرد — چیزی که تا امروز اصلاً ممکن نبود. تأیید شد که UID کاربر هاست (`xennic`, uid 1000) و UID پردازهٔ داخل Container (`node`, uid 1000) یکسان است، پس این Mount بدون تغییر Permission کار می‌کند. این ریسک **آگاهانه پذیرفته شده** (تصمیم صریح مالک) چون تنها راه خودکارسازی کامل تولید `.env.example` بدون ابزار خارجی است. محتوای خام این فایل هرگز در هیچ مرحله‌ای به دیسک `xennic-infra-backups` نوشته نمی‌شود — فقط نسخهٔ Sanitize‌شده (بخش ۷.۳، گام ۵).

**ث) اعمال تغییرات**
```bash
cd /home/xennic/xennic-infra
docker compose up -d n8n   # نه restart ساده — برای اعمال واقعی متغیرهای محیطی و Mountهای جدید
# تأیید:
docker exec xennic-infra-n8n-1 printenv | grep -E 'NODE_FUNCTION_ALLOW_BUILTIN|N8N_RESTRICT_FILE_ACCESS_TO|INFRA_BACKUP_ENC_KEY'
docker exec xennic-infra-n8n-1 ls -la /data/compose-ro
```

### ۷.۳ طراحی گره‌به‌گره Workflow `[OPS-01] Nightly Infra Export`

> منبع واقعیِ این Workflow خودِ n8n است (ساخته‌شده از طریق UI)؛ هیچ فایل JSON این Workflow در Vault نگهداری نمی‌شود — چون خروجی همین Workflow (نسخهٔ JSON واقعی‌اش) هرشب به‌صورت خودکار در `xennic-infra-backups/n8n/workflows.json` ذخیره می‌شود (یعنی خودش هم جزو دارایی‌هایی است که Backup می‌کند).

| # | گره | نوع | پیکربندی کلیدی |
|---|---|---|---|
| ۱ | Schedule Trigger | Schedule Trigger | Cron: `0 0 * * *`، Timezone: `Asia/Tehran` (اجرا هر شب ساعت ۰۰:۰۰ — طبق تصمیم مالک) |
| ۲ | List Workflows | HTTP Request (GET) | URL: `http://localhost:5678/api/v1/workflows?limit=250`؛ Auth: Predefined Credential Type → «n8n API» |
| ۳ | List Credentials Metadata | HTTP Request (GET) | URL: `http://localhost:5678/api/v1/credentials`؛ همان Credential «n8n API»؛ فقط id/name/type برمی‌گردد، هرگز مقدار Secret |
| ۴ | List Community Packages | HTTP Request (GET) | URL: `http://localhost:5678/api/v1/community-packages`؛ همان Credential «n8n API» |
| ۵ | Format n8n Exports | Code | سه ورودی بالا را به سه رشتهٔ JSON (`JSON.stringify(..., null, 2)`) با نام فایل مشخص تبدیل می‌کند؛ از `crypto`/`fs` استفاده نمی‌کند، فقط رشته‌سازی ساده |
| ۶–۸ | Write n8n/*.json ×۳ | Read/Write Files from Disk (Write) | مسیرها: `/data/xennic-infra-backups/n8n/workflows.json`، `.../credentials-metadata.json`، `.../community-packages.json` |
| ۹ | Read docker-compose.yml | Read/Write Files from Disk (Read) | مسیر: `/data/compose-ro/docker-compose.yml` |
| ۱۰ | Write docker-compose.yml | Read/Write Files from Disk (Write) | مسیر: `/data/xennic-infra-backups/infra/docker-compose.yml` |
| ۱۱ | Read .env (خام) | Read/Write Files from Disk (Read) | مسیر: `/data/compose-ro/env-source` |
| ۱۲ | Sanitize .env → .env.example | Code | هر خط با الگوی `KEY=VALUE` را به `KEY=` تبدیل می‌کند (مقدار حذف، کامنت/خط خالی دست‌نخورده)؛ کد نمونه پایین |
| ۱۳ | Write .env.example | Read/Write Files from Disk (Write) | مسیر: `/data/xennic-infra-backups/infra/.env.example` |
| ۱۴ | Export SurrealDB | HTTP Request (POST) | URL: `http://xennic-infra-surrealdb-1:8000/export`؛ Body: `{}` (JSON)؛ Headers: `Surreal-NS: open_notebook`, `Surreal-DB: open_notebook`, `Content-Type: application/json`؛ Auth: Predefined Credential Type → «SurrealDB Root» (Basic Auth)؛ Response Format: `text` |
| ۱۵ | Encrypt SurrealDB Dump | Code | AES-256-GCM با `require('crypto')` و `$env.INFRA_BACKUP_ENC_KEY`؛ کد نمونه پایین |
| ۱۶ | Write Encrypted Dump | Read/Write Files from Disk (Write) | مسیر: `/data/xennic-infra-backups/open-notebook/surrealdb-open_notebook.sql.enc` |
| ۱۷ | Git Pull | Git | عملیات Pull روی مخزن `/data/xennic-infra-backups` (هماهنگ با Remote قبل از Commit) |
| ۱۸ | Git Add + Commit | Git | پیام Commit نمونه: `chore: nightly infra snapshot {{$now.setZone('Asia/Tehran').toFormat('yyyy-LL-dd')}}` |
| ۱۹ | Git Push | Git | Push به همان Remote/Branch از پیش تنظیم‌شده (SSH Deploy Key موجود) |

**کد گره ۵ (Format n8n Exports) — نمونه:**
```javascript
const workflows = $('List Workflows').first().json.data ?? $('List Workflows').first().json;
const credentials = $('List Credentials Metadata').first().json.data ?? $('List Credentials Metadata').first().json;
const packages = $('List Community Packages').first().json.data ?? $('List Community Packages').first().json;

return [
  { json: {}, binary: {}, fileName: 'workflows.json', content: JSON.stringify(workflows, null, 2) },
  { json: {}, binary: {}, fileName: 'credentials-metadata.json', content: JSON.stringify(credentials, null, 2) },
  { json: {}, binary: {}, fileName: 'community-packages.json', content: JSON.stringify(packages, null, 2) },
];
```
(شکل دقیق پاسخ Public API — مستقیم آرایه یا بسته‌شده در `data` — باید بعد از اولین اجرا با داده واقعی instance تأیید/تنظیم شود.)

**کد گره ۱۲ (Sanitize .env → .env.example) — نمونه:**
```javascript
const raw = $input.first().json.data ?? $input.first().binary?.data?.data ?? '';
const text = Buffer.isBuffer(raw) ? raw.toString('utf8') : String(raw);

const sanitized = text.split('\n').map(line => {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith('#')) return line; // کامنت/خط خالی دست‌نخورده
  const idx = line.indexOf('=');
  if (idx === -1) return line;
  return line.slice(0, idx + 1); // فقط KEY= باقی می‌ماند
}).join('\n');

return [{ json: { content: sanitized } }];
```

**کد گره ۱۵ (Encrypt SurrealDB Dump، AES-256-GCM) — نمونه:**
```javascript
const crypto = require('crypto');

const plaintext = $input.first().json.data ?? $input.first().json;
const plaintextStr = typeof plaintext === 'string' ? plaintext : JSON.stringify(plaintext);

const key = Buffer.from($env.INFRA_BACKUP_ENC_KEY, 'hex'); // باید دقیقاً ۳۲ بایت باشد
const iv = crypto.randomBytes(12); // GCM استاندارد: IV ۱۲ بایتی

const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
const encrypted = Buffer.concat([cipher.update(plaintextStr, 'utf8'), cipher.final()]);
const authTag = cipher.getAuthTag();

// قالب فایل خروجی: iv (12 بایت) || authTag (16 بایت) || ciphertext — همه Base64
const payload = Buffer.concat([iv, authTag, encrypted]).toString('base64');

return [{ json: { content: payload } }];
```

### ۷.۴ چرا AES-256-GCM در Code Node به‌جای `age`؟

ابزار `age` یک باینری CLI خارجی است که فراخوانی‌اش نیازمند گره `Execute Command` است — که غیرفعال است. به‌جای آن، چون `require('crypto')` (ماژول built-in خود Node.js) با افزودن `NODE_FUNCTION_ALLOW_BUILTIN=crypto` در Code Node در دسترس است (بخش ۷.۲-پ)، می‌توان رمزنگاری متقارن قوی (AES-256-GCM، همان الگوریتمی که `age` هم داخلش از آن استفاده می‌کند) را کاملاً درون همان Workflow و بدون هیچ وابستگی خارجی انجام داد. کلید رمزگشایی (`INFRA_BACKUP_ENC_KEY`) باید علاوه بر `.env` سرور، در یک محل امن دوم (مثلاً مدیریت رمز مالک) نگه داشته شود — دقیقاً با همان منطق قبلیِ کلید خصوصی `age`: **هرگز در هیچ مخزن Git قرار نگیرد.**

**دستورالعمل رمزگشایی (برای DR، بخش ۸):**
```bash
node -e "
const fs = require('fs');
const crypto = require('crypto');
const key = Buffer.from(process.env.INFRA_BACKUP_ENC_KEY, 'hex');
const raw = Buffer.from(fs.readFileSync('surrealdb-open_notebook.sql.enc', 'utf8'), 'base64');
const iv = raw.subarray(0, 12);
const authTag = raw.subarray(12, 28);
const ciphertext = raw.subarray(28);
const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
decipher.setAuthTag(authTag);
const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
fs.writeFileSync('surrealdb-open_notebook.surql', plaintext);
console.log('OK, decrypted to surrealdb-open_notebook.surql');
"
```
این دستور را روی هر ماشینی با Node.js نصب‌شده (نه لزوماً داخل Container n8n) و با مقدار واقعی `INFRA_BACKUP_ENC_KEY` در `process.env` اجرا کنید.

### ۷.۵ هشدار خطا

مطابق [[META-INT-120 — نظارت، هشدار و مدیریت خطا|META-INT-120]]، Workflow `[OPS-01]` باید به Global Error Workflow موجود وصل شود تا هر شکست (مثلاً خطای احراز هویت API، شکست نوشتن فایل به‌خاطر محدودیت مسیر، یا شکست Git Push به‌خاطر Conflict) همان لحظه در Bale Messenger اطلاع داده شود.

### ۷.۶ جدول خلاصه مسئولیت هر جزء

| جزء | کجا اجرا می‌شود | چرا آنجا |
|---|---|---|
| خواندن Workflow/Credential-metadata/Community-packages | n8n Public API (`HTTP Request`) | Execute Command غیرفعال است؛ Public API راه رسمی و امن جایگزین |
| نوشتن فایل‌های JSON/متنی در مخزن Backup | گره `Read/Write Files from Disk` (پس از افزودن مسیر به `N8N_RESTRICT_FILE_ACCESS_TO`) | تنها گره مجاز برای I/O فایل روی این instance |
| کپی `docker-compose.yml` و تولید `.env.example` | همان گره فایل + یک Bind Mount فقط-خواندنی جدید | بدون نیاز به Execute Command یا دسترسی مستقیم shell |
| Export خام SurrealDB | `HTTP Request` به Endpoint بومی `POST /export` خود SurrealDB v2 | جایگزین کامل `surreal export` CLI، بدون نیاز به Execute Command |
| رمزنگاری Dump سورئال | Code Node با `require('crypto')` (AES-256-GCM) | جایگزین ابزار خارجی `age`؛ کلید در `.env`/مدیریت رمز مالک |
| Commit/Push به Git | گره بومی **Git** در همان Workflow n8n | همان الگوی از پیش ساخته و تست‌شدهٔ `xennic-infra-backups`؛ بدون نیاز به PowerShell/Task Scheduler چون سرور لینوکسی است |
| هشدار شکست هرکدام | Global Error Workflow در n8n → Bale Messenger | یک کانال واحد هشدار، طبق META-INT-120 |

---

## ۸. برنامه بازیابی پس از خرابی (DR)

| مرحله | اقدام | پیش‌نیاز |
|---|---|---|
| ۱ | Clone کردن `xennic-infra-backups` و بازسازی `docker-compose.yml` برای n8n + Qdrant + TEI + Open Notebook | وجود `infra/docker-compose.yml` در Git |
| ۲ | نصب بسته‌های Community فهرست‌شده در `n8n/community-packages.json` پیش از اولین اجرای n8n | وجود این فایل در Git (بخش ۷.۱) |
| ۳ | اجرای اسکریپت ساخت Collection در Qdrant با همان نام/ابعاد/Index | وجود اسکریپت نسخه‌بندی‌شده |
| ۴ | Import مجدد Workflowهای n8n از فایل‌های Export شده | وجود export JSON در Git |
| ۵ | بازسازی Credentialها از محل رسمی (نه از حافظه) طبق META-INT-100 | اجرای کامل META-INT-100 |
| ۶ | رمزگشایی `surrealdb-open_notebook.sql.enc` با `INFRA_BACKUP_ENC_KEY` (دستور Node.js بخش ۷.۴؛ فقط نزد مالک) و Import نتیجه (`.surql`) به SurrealDB جدید | مقدار `INFRA_BACKUP_ENC_KEY` در دسترس باشد (از محل امن دوم، نه از `.env` سرور از‌دست‌رفته) |
| ۷ | اجرای مجدد `RAG-01`/`RAG-02` برای بازسازی ایندکس Qdrant از صفر | وجود [[META-INT-090 — رجیستری Workflowهای n8n\|META-INT-090]] به‌روز |
| ۸ | تست جستجوی معنایی (مطابق تست‌های META-INT-034) برای تأیید صحت بازیابی | — |

> [!warning] وضعیت فعلی این برنامه
> این برنامه **هنوز هرگز تست نشده است**. تا زمانی‌که یک بازیابی آزمایشی کامل انجام نشود، نمی‌توان ادعا کرد سیستم واقعاً قابل بازیابی است. پیشنهاد می‌شود پس از تکمیل فاز C (بخش ۹)، یک بار روی یک ماشین مجازی جداگانه (نه ماشین اصلی) تست شود.

---

## ۹. نقشه راه اجرایی

این بخش مستقیماً فاز C از نقشه راه فنی ۵‌فازه [[META-INT-130 — معماری هدف و نقشه راه مدرن‌سازی زیرساخت اتوماسیون و RAG|META-INT-130]] را به گام‌های ریزتر تقسیم می‌کند:

| گام | اقدام | خروجی |
|---|---|---|
| C.۱ | ساخت مخزن خصوصی `xennic-infra-backups` با ساختار بخش ۷.۱ | مخزن آماده دریافت Backup |
| C.۲ | نوشتن `infra/docker-compose.yml` با نسخه‌های دقیق فعلی (جدول بخش ۲) | امکان بازسازی زیرساخت با یک دستور |
| C.۳ | اعمال پیش‌نیازهای یک‌بارهٔ دستی: فعال‌سازی n8n Public API + API Key، Credential «SurrealDB Root»، افزودن `NODE_FUNCTION_ALLOW_BUILTIN`/`N8N_RESTRICT_FILE_ACCESS_TO`/`INFRA_BACKUP_ENC_KEY` به `.env`، دو Bind Mount جدید، `docker compose up -d n8n` (بخش ۷.۲) | زیرساخت آماده برای ساخت Workflow، بدون نیاز به Execute Command |
| C.۴ | ساخت Workflow `[OPS-01] Nightly Infra Export` با ۱۹ گره طبق جدول بخش ۷.۳ (Public API → Format → Write Files → Git) | Export خودکار شبانهٔ Workflow/Credentials/Community-packages/docker-compose.yml/.env.example |
| C.۵ | افزودن گره‌های Export + رمزنگاری AES-256-GCM برای SurrealDB (بخش ۷.۳–۷.۴) به همان Workflow | Backup امن Open Notebook بدون افشای Corporate، بدون ابزار خارجی `age` |
| C.۶ | اتصال Workflow `[OPS-01]` به Global Error Workflow (پیش‌نیاز از فاز B در META-INT-130) | هشدار فوری در صورت شکست هر مرحله Backup |
| C.۷ | یک بار اجرای کامل بازیابی روی یک محیط تست (VM جداگانه) برای اعتبارسنجی برنامه DR (بخش ۸)، شامل تست واقعی دستور رمزگشایی بخش ۷.۴ | اثبات واقعی قابلیت بازیابی، نه فقط ادعا |

---

## ۱۰. شکاف‌های شناسایی‌شده

| # | شکاف | تأثیر |
|---|---|---|
| ۱ | هیچ Docker Compose یا IaC در مخزن نیست | بازسازی کامل سیستم غیرممکن بدون حافظه انسانی |
| ۲ | Workflowهای n8n در هیچ‌جا Export/Commit نشده‌اند | از دست رفتن کامل منطق اتوماسیون در صورت خرابی |
| ۳ | **فهرست بسته‌های Community (مثلاً Bale Messenger) هیچ‌جا ثبت نشده** | 🆕 بازسازی کانتینر n8n بدون این فهرست یعنی شکست خاموش Workflowهای وابسته به آن گره‌ها (`[KNW-02]`) |
| ۴ | برنامه DR تست نشده | ادعای «قابل بازیابی بودن» اثبات‌نشده است |
| ۵ | وابستگی کامل به یک کامپیوتر شخصی (نه سرور) | Downtime طولانی در صورت هر مشکل سخت‌افزاری |
| ۶ | وابستگی کامل به حافظه یک نفر برای بازسازی | مغایر با هدف جدید مالک: تبدیل‌شدن به یک تیم کامل با چند بخش تخصصی |

---

## ۱۱. اقدامات

- [x] ساخت مخزن `xennic-infra-backups` (خصوصی) با ساختار بخش ۷.۱ — بوت‌استرپ شده با Git node بومی + SSH Deploy Key
- [x] تصمیم‌گیری درباره انتقال به سرور — انجام شد، VPS لینوکسی در حال استفاده (META-INT-140)
- [ ] اعمال پیش‌نیازهای یک‌بارهٔ دستی `[OPS-01]` روی VPS (بخش ۷.۲: Public API Key، دو Credential جدید، سه متغیر `.env`، دو Bind Mount، `docker compose up -d n8n`)
- [ ] ساخت Workflow `[OPS-01] Nightly Infra Export` با ۱۹ گره طبق بخش ۷.۳ (n8n Public API + Code + Read/Write Files + Git، بدون Execute Command)
- [ ] پیاده‌سازی رمزنگاری AES-256-GCM برای Export SurrealDB در همان Workflow (بخش ۷.۴) و تست واقعی چرخهٔ رمزنگاری/رمزگشایی
- [ ] اتصال `[OPS-01]` به Global Error Workflow برای هشدار Bale Messenger در صورت شکست (بخش ۷.۵)
- [ ] نوشتن اسکریپت ساخت Qdrant Collection (نام، ابعاد، Distance، Indexها طبق META-INT-020)
- [ ] اجرای یک بازیابی آزمایشی کامل روی محیط جدا و ثبت نتیجه در این نود (بخش ۸)

---

## ۱۲. ارجاعات

- [[META-INT-080 — معماری کلان سیستم‌عامل هوشمند سازمانی Xennic|META-INT-080]]
- [[META-INT-050 — راه‌اندازی کامل Hermes|META-INT-050]]
- [[META-INT-070 — نقشه Open Notebook برای n8n و Hermes|META-INT-070]]
- [[META-INT-090 — رجیستری Workflowهای n8n|META-INT-090]]
- [[META-INT-100 — مدیریت Secrets و Credentials|META-INT-100]]
- [[META-INT-120 — نظارت، هشدار و مدیریت خطا|META-INT-120]]
- [[META-INT-130 — معماری هدف و نقشه راه مدرن‌سازی زیرساخت اتوماسیون و RAG|META-INT-130]]
- [[META-INT-020 — RAG مشترک Obsidian + Open Notebook → Qdrant|META-INT-020]]

---

## ۱۳. Changelog

- **v0.3.0 (۱۴۰۵-۰۸-۰۶):** بازنویسی کامل بخش ۷ («روش پیاده‌سازی پیشنهادی») برای معماری واقعی VPS: طراحی کامل Workflow `[OPS-01] Nightly Infra Export` با ۱۹ گره مبتنی بر **n8n Public API** (نه CLI/Execute Command که غیرفعال است)، **Read/Write Files from Disk** (پس از گسترش `N8N_RESTRICT_FILE_ACCESS_TO`)، و **رمزنگاری AES-256-GCM درون Code Node** (نه ابزار خارجی `age`) برای Dump سورئال؛ پوشش کامل دامنهٔ اصلی درخواست‌شده (Workflowها، Credential-metadata، Community-packages، `docker-compose.yml`/`.env.example`، Dump رمزنگاری‌شدهٔ SurrealDB) در یک Workflow واحد؛ مستندسازی پیش‌نیازهای یک‌بارهٔ دستی (API Key، دو Credential جدید، سه متغیر محیطی جدید، دو Bind Mount جدید)؛ جایگزینی گام Commit/Push مبتنی بر PowerShell/Task Scheduler ویندوز با گره بومی Git (همان الگوی از پیش ساخته‌شدهٔ `xennic-infra-backups`)؛ افزودن یادداشت‌های تاریخی روی بخش‌های ۱ و ۲ برای حفظ ردیابی تصمیم بدون حذف محتوای گذشته؛ افزودن وابستگی به META-INT-140؛ به‌روزرسانی بخش‌های ۸، ۹ و ۱۱ متناسب با طراحی جدید.
- **v0.2.2 (۱۴۰۵-۰۸-۰۱):** به‌روزرسانی یادداشت بخش ۷.۴ («جایگزین برای آینده») برای ارجاع به تصمیم قطعی مالک در نود جدید [[META-INT-140 — نقشه مهاجرت زیرساخت اتوماسیون به سرور اختصاصی (VPS)|META-INT-140]] (مهاجرت دیگر فقط یک گزینهٔ احتمالی نیست، بلکه تصمیم‌شده است).
- **v0.2.1 (۱۴۰۵-۰۸-۰۱):** رفع اشکال رندر جدول‌ها — Escape کردن `|` داخل لینک‌های Wiki در جدول‌های بخش‌های ۲ و ۸ که باعث شکستن ستون‌بندی جدول در رندررهای استاندارد Markdown (از جمله GitHub) می‌شد؛ بدون تغییر محتوایی.
- **v0.2.0 (۱۴۰۵-۰۷-۳۰):** افزودن دستورالعمل اجرایی مشخص (بخش ۷) برای Backup خودکار n8n (Workflow/Credentials/Community Packages)، Hermes (`config.yaml`) و Open Notebook (SurrealDB رمزنگاری‌شده با `age`) به یک مخزن Git مجزا (`xennic-infra-backups`)؛ کشف و ثبت شکاف جدید «فهرست بسته‌های Community نصب‌شده هیچ‌جا ثبت نشده»؛ افزودن بخش توضیح الگوی مرجع Obsidian؛ تفکیک نقشه راه اجرایی ریزدانه (فاز C) از نقشه راه کلان META-INT-130؛ تغییر وضعیت به `review`.
- **v0.1.0 (۱۴۰۵-۰۷-۳۰):** ایجاد اولیه در پی ممیزی کامل پوشه `00_Meta/Integration` — مستندسازی شکاف «عدم وجود Infrastructure as Code و برنامه بازیابی پس از خرابی» و ریسک تک‌نقطه‌ای بودن زیرساخت روی یک کامپیوتر شخصی.
