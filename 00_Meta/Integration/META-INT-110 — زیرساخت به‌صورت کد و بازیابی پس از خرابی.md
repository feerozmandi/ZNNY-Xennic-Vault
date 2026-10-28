---
id: META-INT-110
title: زیرساخت به‌صورت کد و بازیابی پس از خرابی
status: review
created: 2026-10-22
tags: [integration, infrastructure, iac, disaster-recovery, docker, governance, git-automation]
layer: Meta
domain: INT
owner: احمد فیروزمندی بندپی
version: 0.4.0
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

> [!success] به‌روزرسانی ۱۴۰۵-۰۸-۰۷ — `[OPS-01]` واقعاً ساخته، تست و فعال شد (v0.4.0)
> بخش ۷ که در v0.3.0 فقط یک **طراحی** بود، این دوره واقعاً گره‌به‌گره روی n8n نصب‌شده روی VPS ساخته و با داده واقعی تست شد (نه شبیه‌سازی). در مسیر ساخت، معماری واقعی در چند نقطهٔ مهم از طراحی اولیه منحرف شد (جزئیات کامل در بخش ۷.۷ جدید) — مهم‌ترین مورد، کشف یک قفل امنیتی عمدی در خودِ کد منبع گرهٔ Git n8n که استفاده از کلید SSH اختصاصی را از طریق `core.sshCommand`/`GIT_SSH_COMMAND` کاملاً مسدود می‌کند و راه‌حل واقعی (فایل `~/.ssh/config`) را می‌طلبد. تست End-to-End کامل (شامل یک Commit/Push واقعی به `xennic-infra-backups` و یک رمزگشایی DR واقعی) با موفقیت انجام شد؛ Workflow اکنون **Active** است و هرشب ساعت ۰۰:۰۰ تهران اجرا می‌شود. علاوه‌بر این، دو Workflow مکمل هم ساخته شد: اطلاع‌رسانی موفقیت/خطا از طریق Bale Messenger، و یک Workflow ناظر مستقل `[OPS-02] Nightly Backup Heartbeat Check` که حتی اگر مکانیزم هشدار خطای خودِ `[OPS-01]` هم ساکت بماند، ظرف نیم‌ساعت تشخیص می‌دهد.

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

> [!success] تأیید شده با ساختار واقعی مخزن (۱۴۰۵-۰۸-۰۷)
> ساختار زیر، خروجی واقعیِ `find` روی مخزن `xennic-infra-backups` بعد از اولین اجرای کامل و موفق `[OPS-01]` است (نه طراحی فرضی). دو تفاوت کلیدی با طراحی اولیهٔ v0.3.0: (۱) نام پوشهٔ SurrealDB واقعاً `open_notebook` (با Underline) است، نه `open-notebook`؛ (۲) پوشه‌های `n8n/` و `open_notebook/` از قبل (از زمان Bootstrap اولیهٔ مخزن) وجود داشتند و هرکدام یک `README.md` مخصوص به خود دارند؛ پوشهٔ `infra/` وجود نداشت و باید **دستی** (`mkdir -p`) ساخته می‌شد، چون گرهٔ `Read/Write Files from Disk` در حالت Write، پوشهٔ مقصد را خودکار نمی‌سازد (بخش ۷.۷، یافتهٔ ۵).

```text
xennic-infra-backups/
├── n8n/
│   ├── README.md                    # از زمان Bootstrap اولیه
│   ├── workflows/                   # پوشهٔ خالی قدیمی/میراثی — توسط [OPS-01] استفاده نمی‌شود
│   ├── workflows.json               # خروجی کامل GET /api/v1/workflows
│   ├── credentials-metadata.json    # فقط id/name/type — خروجی GET /api/v1/credentials (بدون مقدار)
│   └── community-packages.json      # { managedByN8n: [...], manuallyInstalled: [...] } — بخش ۷.۷، یافتهٔ ۲
├── infra/                           # باید دستی ساخته شود (mkdir -p) قبل از اولین اجرا
│   ├── docker-compose.yml           # کپی مستقیم از هاست
│   └── .env.example                 # نام متغیرها بدون مقدار واقعی
├── open_notebook/                   # نام واقعی با Underline، نه open-notebook
│   ├── README.md                    # از زمان Bootstrap اولیه
│   └── surrealdb-open_notebook.sql.enc   # Dump رمزنگاری‌شدهٔ AES-256-GCM — بخش ۷.۴
└── README.md                        # تاریخ آخرین Backup موفق + دستورالعمل بازیابی
```

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

**ت) سه Bind Mount جدید در `docker-compose.yml` (سرویس `n8n`)**
```yaml
    volumes:
      # ... خطوط موجود دست‌نخورده می‌مانند ...
      - /home/xennic/xennic-infra/docker-compose.yml:/data/compose-ro/docker-compose.yml:ro
      - /home/xennic/xennic-infra/.env:/data/compose-ro/env-source:ro
      - ./n8n_data/nodes/node_modules:/data/compose-ro/n8n-nodes:ro
```
> [!warning] ریسک امنیتی آگاهانه‌پذیرفته‌شده
> این یعنی `.env` واقعی (شامل پسورد SurrealDB، کلید رمزگذاری n8n، و غیره) برای اولین بار به‌صورت فقط-خواندنی در دسترس Container n8n قرار می‌گیرد — چیزی که تا امروز اصلاً ممکن نبود. تأیید شد که UID کاربر هاست (`xennic`, uid 1000) و UID پردازهٔ داخل Container (`node`, uid 1000) یکسان است، پس این Mount بدون تغییر Permission کار می‌کند. این ریسک **آگاهانه پذیرفته شده** (تصمیم صریح مالک) چون تنها راه خودکارسازی کامل تولید `.env.example` بدون ابزار خارجی است. محتوای خام این فایل هرگز در هیچ مرحله‌ای به دیسک `xennic-infra-backups` نوشته نمی‌شود — فقط نسخهٔ Sanitize‌شده (بخش ۷.۳، گام ۵).

> [!info] Bind Mount سوم اضافه‌شده حین پیاده‌سازی — شکاف «فهرست بسته‌های Community» را واقعاً حل می‌کند
> طراحی اولیهٔ v0.3.0 فقط دو Bind Mount پیش‌بینی کرده بود و فرض می‌کرد `GET /api/v1/community-packages` کافی است. تست واقعی نشان داد این Endpoint فقط بسته‌های نصب‌شده از طریق خودِ رابط n8n را برمی‌گرداند و `n8n-nodes-bale-messenger-alpha` (نصب‌شده دستی/آفلاین، همان گرهٔ Bale Messenger که `[KNW-02]` به آن وابسته است) را اصلاً نشان نمی‌دهد (Endpoint بدون خطا مقدار `[]` برمی‌گرداند). راه‌حل: Mount فقط‌خواندنیِ سوم به پوشهٔ واقعی `node_modules` خودِ n8n، و خواندن `package.json` هر بستهٔ `n8n-nodes-*` مستقیماً از دیسک (بخش ۷.۳، گره‌های `Read Community Package Files`/`Normalize Community Packages`).

**ث) بازسازی Mount کلید SSH Deploy Key به یک پوشهٔ کامل (نه یک فایل تکی)**
Mount قبلی (از زمان Bootstrap اولیهٔ `xennic-infra-backups`، مستند در META-INT-140) فقط خودِ فایل کلید را Mount می‌کرد:
```yaml
      - ~/xennic-infra-backups-deploy:/home/node/.ssh/xennic-infra-backups-deploy:ro
```
این باید با Mount یک پوشهٔ کامل جایگزین شود (دلیل دقیق در بخش ۷.۷، یافتهٔ ۸ — قفل امنیتی گرهٔ Git n8n):
```yaml
      - ~/xennic-infra-ssh:/home/node/.ssh:ro
```
با این محتوای از پیش آماده‌شده روی هاست در `~/xennic-infra-ssh/` (مالکیت `1000:1000`، مجوز `600`):
- `xennic-infra-backups-deploy` — همان کلید خصوصی قبلی (فقط منتقل‌شده)
- `config`:
  ```sshconfig
  Host github.com
      IdentityFile /home/node/.ssh/xennic-infra-backups-deploy
      IdentitiesOnly yes
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
  ```

**ج) اعمال تغییرات**
```bash
cd /home/xennic/xennic-infra
docker compose up -d n8n   # نه restart ساده — برای اعمال واقعی متغیرهای محیطی و Mountهای جدید
# تأیید:
docker exec xennic-infra-n8n-1 printenv | grep -E 'NODE_FUNCTION_ALLOW_BUILTIN|N8N_RESTRICT_FILE_ACCESS_TO|INFRA_BACKUP_ENC_KEY'
docker exec xennic-infra-n8n-1 ls -la /data/compose-ro
docker exec xennic-infra-n8n-1 ls -la /home/node/.ssh/
docker exec xennic-infra-n8n-1 ssh -T git@github.com   # باید پیام "successfully authenticated" بدهد
```

### ۷.۳ طراحی گره‌به‌گره Workflow `[OPS-01] Nightly Infra Export` (نسخهٔ واقعی ساخته‌شده و تست‌شده)

> منبع واقعیِ این Workflow خودِ n8n است (ساخته‌شده از طریق UI)؛ هیچ فایل JSON این Workflow در Vault نگهداری نمی‌شود — چون خروجی همین Workflow (نسخهٔ JSON واقعی‌اش) هرشب به‌صورت خودکار در `xennic-infra-backups/n8n/workflows.json` ذخیره می‌شود (یعنی خودش هم جزو دارایی‌هایی است که Backup می‌کند).

> [!success] این جدول، معماری **واقعاً ساخته‌شده** است (نه طراحی اولیه)
> نسبت به طراحی اولیهٔ v0.3.0 (۱۹ گرهٔ خطی)، نسخهٔ واقعی ۲۵ گره دارد و به‌صورت ۴ شاخهٔ موازی از `Schedule Trigger` سازماندهی شده که قبل از Git در یک گرهٔ `Merge` به‌هم می‌رسند. دلایل افزایش تعداد گره‌ها (نیاز به `Convert to File` قبل از هر نوشتن متنی، گرهٔ دفاعی `Normalize Community Packages`، گرهٔ کمکی `Read Community Package Files`) در بخش ۷.۷ توضیح داده شده است.

**شاخهٔ A — Export اطلاعات n8n (Workflows/Credentials/Community-Packages):**

| # | گره | نوع | پیکربندی کلیدی |
|---|---|---|---|
| ۱ | Schedule Trigger | Schedule Trigger | Cron: `0 0 * * *`، Timezone: `Asia/Tehran` (اجرا هر شب ساعت ۰۰:۰۰ — طبق تصمیم مالک) |
| ۲ | List Workflows | HTTP Request (GET) | URL: `http://localhost:5678/api/v1/workflows?limit=250`؛ Auth: Predefined Credential Type → «n8n API» (Credential: `n8n API - OPS-01`) |
| ۳ | List Credentials Metadata | HTTP Request (GET) | URL: `http://localhost:5678/api/v1/credentials`؛ همان Credential «n8n API»؛ فقط id/name/type برمی‌گردد، هرگز مقدار Secret |
| ۴ | List Community Packages | HTTP Request (GET) | URL: `http://localhost:5678/api/v1/community-packages`؛ همان Credential «n8n API»؛ **«Always Output Data» باید روشن باشد** (بخش ۷.۷، یافتهٔ ۳) |
| ۵ | Normalize Community Packages | Code | گرهٔ دفاعی: همیشه دقیقاً ۱ آیتم تولید می‌کند، چه API آرایهٔ خالی برگرداند چه `alwaysOutputData` یک Fallback تهی تولید کند؛ کد کامل در ادامه |
| ۶ | Read Community Package Files | Read/Write Files from Disk (Read) | File Selector: `/data/compose-ro/n8n-nodes/n8n-nodes-*/package.json` — کشف بسته‌های نصب‌شدهٔ دستی که در API دیده نمی‌شوند |
| ۷ | Format n8n Exports | Code | سه ورودی بالا (Workflows/Credentials/Community-Packages ترکیبی) را به سه آیتم `{ json: { fileName, content } }` تبدیل می‌کند؛ کد کامل در ادامه |
| ۸ | Convert to File (n8n Exports) | Convert to File | Operation: Convert to Text File؛ Text Input Field: `content` |
| ۹ | Write n8n Export Files | Read/Write Files from Disk (Write) | File Name (Expression): `/data/xennic-infra-backups/n8n/{{ $('Format n8n Exports').item.json.fileName }}` — Item-Linking تضمین می‌کند هر آیتم به نام فایل خودش نوشته شود |

**شاخهٔ B — کپی `docker-compose.yml`:**

| # | گره | نوع | پیکربندی کلیدی |
|---|---|---|---|
| ۱۰ | Read docker-compose.yml | Read/Write Files from Disk (Read) | File Selector: `/data/compose-ro/docker-compose.yml` |
| ۱۱ | Write docker-compose.yml | Read/Write Files from Disk (Write) | File Name: `/data/xennic-infra-backups/infra/docker-compose.yml` (مقدار ثابت، Input Binary Field: `data`) |

**شاخهٔ C — Sanitize و نوشتن `.env.example`:**

| # | گره | نوع | پیکربندی کلیدی |
|---|---|---|---|
| ۱۲ | Read .env (raw) | Read/Write Files from Disk (Read) | File Selector: `/data/compose-ro/env-source` |
| ۱۳ | Sanitize .env to .env.example | Code | هر خط با الگوی `KEY=VALUE` را به `KEY=` تبدیل می‌کند (مقدار حذف، کامنت/خط خالی دست‌نخورده)؛ کد کامل در ادامه |
| ۱۴ | Convert to File | Convert to File | Operation: Convert to Text File؛ Text Input Field: `content` |
| ۱۵ | Write .env.example | Read/Write Files from Disk (Write) | File Name: `/data/xennic-infra-backups/infra/.env.example` (مقدار ثابت) |

**شاخهٔ D — Export و رمزنگاری SurrealDB:**

| # | گره | نوع | پیکربندی کلیدی |
|---|---|---|---|
| ۱۶ | Export SurrealDB | HTTP Request (POST) | URL: `http://xennic-infra-surrealdb-1:8000/export`؛ Body: `{}` (JSON)؛ Headers: `Surreal-NS: open_notebook`, `Surreal-DB: open_notebook`, `Content-Type: application/json`؛ Authentication: **Generic Credential Type → Basic Auth** (نه Predefined — بخش ۷.۷، یافتهٔ ۹) → Credential «SurrealDB Root»؛ Response Format: `text` |
| ۱۷ | Encrypt SurrealDB Dump | Code | AES-256-GCM با `require('crypto')` و `$env.INFRA_BACKUP_ENC_KEY`؛ کد کامل در ادامه |
| ۱۸ | Convert Encrypted Dump to File | Convert to File | Operation: Convert to Text File؛ Text Input Field: `content` |
| ۱۹ | Write Encrypted Dump | Read/Write Files from Disk (Write) | File Name: `/data/xennic-infra-backups/open_notebook/surrealdb-open_notebook.sql.enc` (توجه: `open_notebook` با Underline، نه `open-notebook`) |

**اتصال نهایی — Merge و Git:**

| # | گره | نوع | پیکربندی کلیدی |
|---|---|---|---|
| ۲۰ | Merge Before Commit | Merge | Number of Inputs: ۴ (از هر چهار گرهٔ نهاییِ شاخه‌های A–D)؛ Mode: Combine |
| ۲۱ | Git Pull | Git | Repository Path: `/data/xennic-infra-backups` |
| ۲۲ | Git Add | Git | Repository Path: `/data/xennic-infra-backups`؛ Paths to Add: `.` |
| ۲۳ | Git Commit | Git | Message: `chore: nightly infra snapshot {{ $now.setZone('Asia/Tehran').toFormat('yyyy-LL-dd') }}`؛ **Continue On Fail: روشن** (اگر شبی هیچ تغییری نباشد، «nothing to commit» نباید کل Workflow را Fail نشان دهد) |
| ۲۴ | Git Push | Git | Authentication: **None** (کلید SSH از طریق فایل `~/.ssh/config`‌ خودِ Container مدیریت می‌شود، نه Credential این گره — بخش ۷.۷، یافتهٔ ۸) |
| ۲۵ | Notify Bale (Backup Success) | `n8n-nodes-bale-messenger-alpha.baleMessenger` | Chat ID: `{{ $env.BALE_CHAT_ID }}`؛ پیام موفقیت؛ Credential: `BaleMessenger account` (بخش ۷.۵) |

**کد گرهٔ Normalize Community Packages:**
```javascript
const items = $input.all();
const raw = items.length > 0 ? items[0].json : [];
const packages = Array.isArray(raw) ? raw : (Array.isArray(raw?.data) ? raw.data : []);
return [{ json: { packages } }];
```

**کد گرهٔ Format n8n Exports — نسخهٔ واقعی تأییدشده** (توجه: همهٔ فیلدهای خروجی باید داخل `json` تو در تو باشند، نه در سطح بالا — بخش ۷.۷، یافتهٔ ۴):
```javascript
const workflows = $('List Workflows').first().json.data;
const credentials = $('List Credentials Metadata').first().json.data;
const apiPackages = $('Normalize Community Packages').first().json.packages;

const manualPackages = [];
const items = $input.all();
for (let i = 0; i < items.length; i++) {
  const item = items[i];
  if (item.binary && item.binary.data) {
    const buffer = await this.helpers.getBinaryDataBuffer(i, 'data');
    try {
      const pkg = JSON.parse(buffer.toString('utf8'));
      manualPackages.push({ name: pkg.name, version: pkg.version, description: pkg.description ?? null, source: 'manual-install' });
    } catch (e) {
      manualPackages.push({ error: `parse failed: ${e.message}` });
    }
  }
}

const communityPackages = { managedByN8n: Array.isArray(apiPackages) ? apiPackages : [], manuallyInstalled: manualPackages };

return [
  { json: { fileName: 'workflows.json', content: JSON.stringify(workflows, null, 2) } },
  { json: { fileName: 'credentials-metadata.json', content: JSON.stringify(credentials, null, 2) } },
  { json: { fileName: 'community-packages.json', content: JSON.stringify(communityPackages, null, 2) } },
];
```
(شکل واقعی پاسخ Public API تأیید شد: `GET /api/v1/workflows` و `GET /api/v1/credentials` هر دو در `{"data": [...]}` بسته‌شده‌اند، اما `GET /api/v1/community-packages` یک آرایهٔ خام `[...]` برمی‌گرداند — ناهماهنگی فرمت بین این سه Endpoint.)

**کد گرهٔ Sanitize .env to .env.example — نسخهٔ واقعی تأییدشده:**
```javascript
const buffer = await this.helpers.getBinaryDataBuffer(0, 'data');
const text = buffer.toString('utf8');

const sanitized = text.split('\n').map(line => {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith('#')) return line;
  const eqIdx = line.indexOf('=');
  if (eqIdx === -1) return line;
  const key = line.slice(0, eqIdx);
  return `${key}=`;
}).join('\n');

return [{ json: { fileName: '.env.example', content: sanitized } }];
```

**کد گرهٔ Encrypt SurrealDB Dump (AES-256-GCM) — نسخهٔ واقعی تأییدشده:**
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

return [{ json: { fileName: 'surrealdb-open_notebook.sql.enc', content: payload } }];
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

> [!success] تست DR واقعی انجام شد (۱۴۰۵-۰۸-۰۷)
> دستور بالا (با اجرا از داخل `xennic-infra-n8n-1` به‌جای یک ماشین جدا، برای سادگی تست) روی Dump واقعی تولیدشدهٔ همان‌شب اجرا شد: ۳۵۱٬۳۹۱ بایت متن خام SurrealQL با موفقیت رمزگشایی شد و محتوایش (`DEFINE FUNCTION ...`) تأیید شد. چرخهٔ کامل رمزنگاری/رمزگشایی (کلید، IV، AuthTag، GCM) صحیح است.

### ۷.۵ هشدار خطا — پیاده‌سازی واقعی (Bale Messenger دوطرفه + ناظر مستقل Heartbeat)

مطابق [[META-INT-120 — نظارت، هشدار و مدیریت خطا|META-INT-120]]، کانال واقعی هشدار پروژه Bale Messenger است (الگوی موجود در `[KNW-02]`)، نه Telegram. برای `[OPS-01]` سه لایهٔ مستقل ساخته شد:

**لایهٔ ۱ — اطلاع موفقیت:** گرهٔ `Notify Bale (Backup Success)` در انتهای خودِ `[OPS-01]` (بعد از `Git Push`، بخش ۷.۳).

**لایهٔ ۲ — اطلاع خطا از طریق Global Error Workflow:** یک Workflow جداگانه به نام `[OPS-00] Global Error Alert (Bale)` ساخته شد:

| # | گره | نوع | پیکربندی کلیدی |
|---|---|---|---|
| ۱ | Error Trigger | Error Trigger | بدون پارامتر؛ فقط باید اولین گرهٔ Workflow باشد |
| ۲ | Format Error Alert | Code | استخراج امن نام Workflow/گرهٔ خطا/شناسهٔ اجرا/پیام خطا از ساختار متغیر خروجی Error Trigger؛ کد کامل زیر |
| ۳ | Bale (Error Alert) | `n8n-nodes-bale-messenger-alpha.baleMessenger` | Chat ID: `{{ $env.BALE_CHAT_ID }}`؛ Text: `{{ $json.text }}`؛ Credential: `BaleMessenger account` |

```javascript
const data = $input.first().json;
const workflowName = data.workflow?.name ?? 'نامشخص';
const executionId = data.execution?.id ?? 'نامشخص';
const errorMessage = data.execution?.error?.message ?? data.trigger?.error?.message ?? JSON.stringify(data).slice(0, 300);
const nodeName = data.execution?.lastNodeExecuted ?? data.trigger?.error?.node?.name ?? 'نامشخص';

const text = `⚠️ خطا در Workflow «${workflowName}»\nگره خطا: ${nodeName}\nشناسهٔ اجرا: ${executionId}\nپیام خطا: ${errorMessage}`;

return [{ json: { text } }];
```

سپس در `[OPS-01]` → منوی `...` → **Settings** → فیلد **Error Workflow** روی `[OPS-00] Global Error Alert (Bale)` تنظیم شد. **هر دو Workflow باید Active باشند** وگرنه این اتصال به‌صورت خاموش (بدون هیچ خطای قابل‌مشاهده) نادیده گرفته می‌شود (بخش ۷.۷، یافتهٔ ۱۱).

**لایهٔ ۳ — ناظر مستقل Heartbeat (Dead Man's Switch):** حین تست واقعی مشخص شد که لایهٔ ۲ به‌تنهایی کافی نیست — یک اجرای واقعاً ناموفق (در تب Executions قابل‌مشاهده) ممکن است به هر دلیلی (تنظیمات/هم‌زمانی Reactivation، بخش ۷.۷ یافتهٔ ۱۱) هیچ پیامی تولید نکند. برای پوشش این شکاف، یک Workflow کاملاً مستقل ساخته شد که از **بیرون** زیرساخت را چک می‌کند، نه از داخل `[OPS-01]`:

**`[OPS-02] Nightly Backup Heartbeat Check`:**

| # | گره | نوع | پیکربندی کلیدی |
|---|---|---|---|
| ۱ | Schedule Trigger | Schedule Trigger | Cron: `30 0 * * *`، Timezone: `Asia/Tehran` (نیم‌ساعت بعد از `[OPS-01]`) |
| ۲ | Get Last Commit | Git (Log) | Repository Path: `/data/xennic-infra-backups` |
| ۳ | Check Backup Freshness | Code | چک می‌کند آخرین Commit واقعاً مربوط به چند ساعت اخیر و پیام «nightly infra snapshot» است یا نه |
| ۴ | IF Backup Missing | IF | شرط: `{{ $json.ok }}` برابر `false` |
| ۵ | Bale (Heartbeat Alert) | `n8n-nodes-bale-messenger-alpha.baleMessenger` | فقط روی شاخهٔ «مشکل تأیید نشد» اجرا می‌شود؛ پیام شامل دلیل دقیق |

```javascript
const items = $input.all();
if (items.length === 0) {
  return [{ json: { ok: false, reason: 'هیچ Commitی در مخزن پیدا نشد' } }];
}

const lastCommit = items[0].json;
const commitDateStr = lastCommit.date || lastCommit.author_date || lastCommit.when;
const commitMessage = lastCommit.message || lastCommit.summary || '';

if (!commitDateStr) {
  return [{ json: { ok: false, reason: 'فیلد تاریخ در خروجی گره Git یافت نشد: ' + JSON.stringify(lastCommit) } }];
}

const commitDate = new Date(commitDateStr);
const now = new Date();
const hoursSinceCommit = (now.getTime() - commitDate.getTime()) / (1000 * 60 * 60);

const isFresh = hoursSinceCommit <= 3;
const isTonightsBackup = commitMessage.includes('nightly infra snapshot');

return [{
  json: {
    ok: isFresh && isTonightsBackup,
    reason: isFresh && isTonightsBackup ? 'تأیید شد' : `آخرین Commit: "${commitMessage}" در ${commitDateStr} (${hoursSinceCommit.toFixed(1)} ساعت پیش)`,
  },
}];
```

هر سه لایه (موفقیت/خطا/Heartbeat) با داده واقعی تست و تأیید شدند.

### ۷.۶ جدول خلاصه مسئولیت هر جزء

| جزء | کجا اجرا می‌شود | چرا آنجا |
|---|---|---|
| خواندن Workflow/Credential-metadata/Community-packages | n8n Public API (`HTTP Request`) | Execute Command غیرفعال است؛ Public API راه رسمی و امن جایگزین |
| کشف بسته‌های Community نصب‌شدهٔ دستی | `Read/Write Files from Disk` (Read) روی Bind Mount سوم `node_modules` | API به‌تنهایی بسته‌های نصب‌شدهٔ دستی را نمی‌بیند (بخش ۷.۷، یافتهٔ ۲) |
| نوشتن فایل‌های JSON/متنی در مخزن Backup | `Convert to File` (toText) → `Read/Write Files from Disk` (Write) | گرهٔ Write فقط داده باینری می‌پذیرد؛ محتوای متنی باید اول تبدیل شود (بخش ۷.۷، یافتهٔ ۶) |
| کپی `docker-compose.yml` و تولید `.env.example` | همان گره‌های فایل + Bind Mountهای فقط-خواندنی | بدون نیاز به Execute Command یا دسترسی مستقیم shell |
| Export خام SurrealDB | `HTTP Request` به Endpoint بومی `POST /export` خود SurrealDB v2، با Authentication از نوع Generic Credential Type → Basic Auth | جایگزین کامل `surreal export` CLI؛ نوع Auth درست باید Generic باشد نه Predefined (بخش ۷.۷، یافتهٔ ۹) |
| رمزنگاری Dump سورئال | Code Node با `require('crypto')` (AES-256-GCM) | جایگزین ابزار خارجی `age`؛ کلید در `.env`/مدیریت رمز مالک |
| Commit/Push به Git | گره بومی **Git** در همان Workflow n8n، با احراز هویت SSH از طریق فایل `~/.ssh/config` Container (نه Credential گره) | گرهٔ Git n8n عمداً `core.sshCommand`/`GIT_SSH_COMMAND` را نادیده می‌گیرد (بخش ۷.۷، یافتهٔ ۸) |
| هشدار موفقیت/شکست | گرهٔ Bale در انتهای `[OPS-01]` + Global Error Workflow (`[OPS-00]`) → Bale Messenger | طبق META-INT-120، با الگوی از پیش تست‌شدهٔ `[KNW-02]` |
| ناظر مستقل عدم‌اجرای خاموش | Workflow جداگانهٔ `[OPS-02]` که از بیرون Git Log مخزن Backup را چک می‌کند | پوشش شکافی که Global Error Workflow به‌تنهایی نمی‌پوشاند (بخش ۷.۷، یافتهٔ ۱۱) |

### ۷.۷ یافته‌های کلیدی حین پیاده‌سازی (درس‌آموخته‌ها)

این بخش تفاوت‌های واقعی بین طراحی اولیهٔ v0.3.0 و پیاده‌سازی واقعی v0.4.0 را مستند می‌کند — برای این‌که این کشفیات (که هرکدام با آزمون‌وخطای واقعی روی VPS به‌دست آمدند) در ساخت Workflowهای آیندهٔ مشابه تکرار نشوند.

| # | یافته | توضیح |
|---|---|---|
| ۱ | فرمت پاسخ Public API ناهماهنگ است | `GET /api/v1/workflows` و `GET /api/v1/credentials` در `{"data": [...]}` بسته‌شده‌اند؛ `GET /api/v1/community-packages` یک آرایهٔ خام `[...]` برمی‌گرداند. کد ترکیب‌کننده نباید فرض یکنواخت `.data` بگذارد. |
| ۲ | بسته‌های Community نصب‌شدهٔ دستی/آفلاین برای Public API نامرئی‌اند | `n8n-nodes-bale-messenger-alpha` با وجود نصب و فعال‌بودن (همان گرهٔ Bale در `[KNW-02]`)، در `GET /api/v1/community-packages` اصلاً دیده نمی‌شود. راه‌حل: Bind Mount سوم فقط‌خواندنی به `node_modules` + خواندن مستقیم `package.json` هر `n8n-nodes-*`. |
| ۳ | `alwaysOutputData` به‌تنهایی برای مدیریت آرایهٔ خالی کافی نیست | یک گرهٔ HTTP Request با `alwaysOutputData: true` که پاسخ `[]` معتبر برمی‌گرداند، می‌تواند در یک اجرای کامل Workflow با ۰ آیتم خروجی بدهد و زنجیرهٔ بعدی را **بدون هیچ خطا** (وضعیت «موفق») به‌صورت خاموش متوقف کند. علاوه‌بر این، این تنظیم روی گره می‌تواند به‌صورت خاموش به `false` برگردد. الگوی مطمئن‌تر: یک گرهٔ Code دفاعی بلافاصله بعد از چنین HTTP Requestای که همیشه دقیقاً ۱ آیتم تولید کند (`Normalize Community Packages`). |
| ۴ | خروجی گرهٔ Code باید همهٔ فیلدها را داخل `json` تو در تو کند | قراردادن فیلد سفارشی (مثلاً `fileName`) در سطح بالای آیتم به‌جای داخل `json` باعث خطای «Invalid output format» می‌شود؛ n8n فقط `{ json, binary }` را در سطح بالا می‌پذیرد. |
| ۵ | گرهٔ Write در «Read/Write Files from Disk» پوشهٔ مقصد را خودکار نمی‌سازد | یک باگ مستند در n8n (Issue #41766): اگر پوشهٔ والدِ مسیر مقصد از قبل وجود نداشته باشد، نوشتن با خطای `ENOENT` شکست می‌خورد. پوشه‌ها (مثل `infra/`) باید از قبل، دستی روی هاست ساخته شوند. |
| ۶ | نوشتن محتوای متنی/JSON نیازمند `Convert to File` قبل از `Write` است | گرهٔ Write فقط دادهٔ باینری می‌پذیرد (پیام خطا: «expects ... binary file»)؛ باید اول یک گرهٔ `Convert to File` (Operation: Convert to Text File) بین Code node تولیدکنندهٔ متن و گرهٔ Write قرار گیرد. |
| ۷ | فعال‌سازی Expression باید با آیکون `fx` باشد، نه تایپ‌کردن دستی `=` | اگر کاربر خودش ابتدای یک فیلد ثابت علامت `=` تایپ کند (به‌جای کلیک روی آیکون Expression)، n8n آن را رشتهٔ تحت‌اللفظی می‌خواند و مسیر نامعتبر می‌سازد (دیده‌شده در خطای `realpath '=/data/...'`). |
| ۸ | **گرهٔ Git در n8n عمداً `core.sshCommand` را قفل می‌کند — مهم‌ترین یافتهٔ این دوره** | بررسی کد منبع `Git.node.ts` نشان داد: برای هر عملیات Git، n8n با فلگ `-c core.sshCommand=ssh` این مقدار را به رشتهٔ سادهٔ `ssh` Pin می‌کند — این مقدار از هر چیزی که در `.git/config` (`git config core.sshCommand ...`) یا متغیر محیطی `GIT_SSH_COMMAND` تنظیم شود مهم‌تر است (یک سخت‌گیری امنیتی عمدی، نه باگ). **نتیجه: گرهٔ Git بومی n8n هرگز نمی‌تواند از طریق تنظیمات Git یک کلید SSH اختصاصی (غیر پیش‌فرض) استفاده کند.** تنها راه حل باقی‌مانده، تنظیم کلید از طریق فایل استاندارد خودِ کلاینت SSH (`~/.ssh/config` با بلوک `Host <دامنه>` و `IdentityFile`) است، چون n8n فقط دستور را به `ssh` سادهٔ بدون `-F`/`-i` محدود می‌کند و خودِ `ssh` همچنان این فایل را می‌خواند. این نیازمند Mount کردن کل پوشهٔ `~/.ssh` (نه فقط فایل کلید) بود تا کاربر `node` بتواند `config` را هم در کنار کلید ببیند. |
| ۹ | Credential از نوع Basic Auth باید از طریق «Generic Credential Type» انتخاب شود | در گرهٔ HTTP Request، فیلد **Authentication → Predefined Credential Type** فقط انواع اختصاصی سرویس (مثل «n8n API») را نشان می‌دهد. برای Credentialهای عمومی (Basic Auth، Header Auth، OAuth...) باید **Authentication → Generic Credential Type** انتخاب شود و سپس در فیلد **Generic Auth Type** نوع موردنظر (مثلاً Basic Auth) مشخص گردد. |
| ۱۰ | نام واقعی پوشه‌های مخزن ممکن است با طراحی اولیه فرق کند | طراحی اولیه فرض `open-notebook` (خط‌تیره) کرده بود؛ ساختار واقعیِ از‌پیش‌بوت‌استرپ‌شده `open_notebook` (Underline) بود. همیشه باید ساختار واقعی را با `find`/`ls` تأیید کرد، نه فقط به مستند طراحی تکیه کرد. |
| ۱۱ | Error Workflow فقط برای اجراهای Production فعال می‌شود، نه اجرای دستی | کلیک روی «Test workflow»/«Execute workflow» از ویرایشگر، هرگز Error Workflow متصل را فعال نمی‌کند — این فقط برای اجراهای واقعی (Schedule/Webhook) کار می‌کند؛ این رفتار رسمی خودِ n8n است. همچنین تغییر Cron یک Trigger روی یک Workflow از‌پیش‌Active، آن را خودکار دوباره زمان‌بندی نمی‌کند (نیاز به یک چرخهٔ Deactivate→Activate). حتی با رعایت این نکات، یک بار یک اجرای واقعاً ناموفق (قابل‌مشاهده در تب Executions) هیچ پیام خطایی تولید نکرد که با تنظیم مجدد دستی Settings رفع شد — به همین دلیل لایهٔ سوم مستقل (`[OPS-02]` Heartbeat) به‌عنوان Defense-in-Depth اضافه شد، نه به‌عنوان جایگزین لایهٔ دوم. |

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

> [!warning] وضعیت فعلی این برنامه — جزئاً تست شده
> مرحلهٔ ۶ (رمزگشایی `surrealdb-open_notebook.sql.enc`) با داده واقعی تست و تأیید شد (بخش ۷.۴). مراحل ۱ تا ۵ و ۷ تا ۸ (بازسازی کامل محیط از صفر روی یک ماشین مستقل) **هنوز هرگز به‌صورت End-to-End تست نشده‌اند**. تا زمانی‌که یک بازیابی آزمایشی کامل انجام نشود، نمی‌توان ادعا کرد کل سیستم (نه فقط رمزگشایی) واقعاً قابل بازیابی است. این مورد همچنان در بخش ۱۱ به‌عنوان اقدام باز ثبت است.

---

## ۹. نقشه راه اجرایی

این بخش مستقیماً فاز C از نقشه راه فنی ۵‌فازه [[META-INT-130 — معماری هدف و نقشه راه مدرن‌سازی زیرساخت اتوماسیون و RAG|META-INT-130]] را به گام‌های ریزتر تقسیم می‌کند:

| گام | اقدام | خروجی |
|---|---|---|
| C.۱ | ✅ ساخت مخزن خصوصی `xennic-infra-backups` با ساختار بخش ۷.۱ | مخزن آماده دریافت Backup — انجام شد |
| C.۲ | ✅ نوشتن `infra/docker-compose.yml` با نسخه‌های دقیق فعلی (جدول بخش ۲) | امکان بازسازی زیرساخت با یک دستور — انجام شد (هرشب خودکار به‌روز می‌شود) |
| C.۳ | ✅ اعمال پیش‌نیازهای یک‌بارهٔ دستی: فعال‌سازی n8n Public API + API Key، Credential «SurrealDB Root»، افزودن `NODE_FUNCTION_ALLOW_BUILTIN`/`N8N_RESTRICT_FILE_ACCESS_TO`/`INFRA_BACKUP_ENC_KEY` به `.env`، سه Bind Mount، بازسازی Mount کلید SSH، `docker compose up -d n8n` (بخش ۷.۲) | زیرساخت آماده برای ساخت Workflow، بدون نیاز به Execute Command — انجام شد |
| C.۴ | ✅ ساخت Workflow `[OPS-01] Nightly Infra Export` با ۲۵ گره طبق جدول بخش ۷.۳ (Public API → Format → Write Files → Git) | Export خودکار شبانهٔ Workflow/Credentials/Community-packages/docker-compose.yml/.env.example — ساخته، تست End-to-End شد و **Active** است |
| C.۵ | ✅ افزودن گره‌های Export + رمزنگاری AES-256-GCM برای SurrealDB (بخش ۷.۳–۷.۴) به همان Workflow | Backup امن Open Notebook بدون افشای Corporate، بدون ابزار خارجی `age` — انجام و تست DR شد |
| C.۶ | ✅ اتصال Workflow `[OPS-01]` به Global Error Workflow + افزودن ناظر مستقل `[OPS-02]` (بخش ۷.۵) | هشدار فوری در صورت شکست هر مرحله Backup، با لایهٔ دوم Defense-in-Depth — انجام شد |
| C.۷ | ⏳ یک بار اجرای کامل بازیابی روی یک محیط تست (VM جداگانه) برای اعتبارسنجی برنامه DR (بخش ۸)، شامل تست واقعی دستور رمزگشایی بخش ۷.۴ | تست رمزگشایی (بخش ۷.۴) انجام شد؛ بازسازی کامل محیط از صفر هنوز باز است — اثبات واقعی قابلیت بازیابی کامل، نه فقط ادعا |

---

## ۱۰. شکاف‌های شناسایی‌شده

| # | شکاف | تأثیر |
|---|---|---|
| ۱ | ✅ **حل شد** — هیچ Docker Compose یا IaC در مخزن نبود | `infra/docker-compose.yml` هرشب خودکار به‌روز می‌شود (`[OPS-01]`) |
| ۲ | ✅ **حل شد** — Workflowهای n8n در هیچ‌جا Export/Commit نمی‌شدند | `n8n/workflows.json` هرشب خودکار به‌روز می‌شود (`[OPS-01]`) |
| ۳ | ✅ **حل شد** — فهرست بسته‌های Community (مثلاً Bale Messenger) هیچ‌جا ثبت نشده بود | `n8n/community-packages.json` هرشب خودکار به‌روز می‌شود، شامل بسته‌های نصب‌شدهٔ دستی (بخش ۷.۷، یافتهٔ ۲) |
| ۴ | ⚠️ **جزئاً حل شد** — برنامه DR تست نشده بود | تست رمزگشایی SurrealDB انجام شد (بخش ۷.۴)؛ بازسازی کامل محیط از صفر هنوز تست نشده (C.۷ باز است) |
| ۵ | وابستگی کامل به یک کامپیوتر شخصی (نه سرور) | ✅ حل شد با مهاجرت به VPS (META-INT-140) |
| ۶ | وابستگی کامل به حافظه یک نفر برای بازسازی | مغایر با هدف جدید مالک: تبدیل‌شدن به یک تیم کامل با چند بخش تخصصی — با مستندسازی کامل بخش ۷ این وابستگی کاهش یافته اما هنوز کاملاً رفع نشده |
| ۷ | 🆕 گرهٔ Git بومی n8n اجازهٔ استفاده از کلید SSH اختصاصی را از طریق تنظیمات Git نمی‌دهد | راه‌حل یافت و اعمال شد (Mount فایل `~/.ssh/config`، بخش ۷.۷ یافتهٔ ۸)؛ برای هر مخزن Git جدیدی که در آینده به این instance اضافه شود باید همین الگو تکرار شود |
| ۸ | 🆕 اطمینان از اجرای واقعی Error Workflow در تمام سناریوها اثبات‌نشده است | یک بار یک اجرای ناموفق هیچ پیامی تولید نکرد (علت دقیق کاملاً شناسایی نشد)؛ لایهٔ سوم مستقل `[OPS-02]` اضافه شد اما ریشهٔ این رفتار نامنظم هنوز به‌طور کامل تشخیص داده نشده است |

---

## ۱۱. اقدامات

- [x] ساخت مخزن `xennic-infra-backups` (خصوصی) با ساختار بخش ۷.۱ — بوت‌استرپ شده با Git node بومی + SSH Deploy Key
- [x] تصمیم‌گیری درباره انتقال به سرور — انجام شد، VPS لینوکسی در حال استفاده (META-INT-140)
- [x] اعمال پیش‌نیازهای یک‌بارهٔ دستی `[OPS-01]` روی VPS (بخش ۷.۲: Public API Key، دو Credential جدید، سه متغیر `.env`، سه Bind Mount، بازسازی Mount کلید SSH، `docker compose up -d n8n`)
- [x] ساخت Workflow `[OPS-01] Nightly Infra Export` با ۲۵ گره طبق بخش ۷.۳ (n8n Public API + Code + Convert to File + Read/Write Files + Git، بدون Execute Command) — تست End-to-End موفق، **Active** و اجرای شبانه در حال انجام
- [x] پیاده‌سازی رمزنگاری AES-256-GCM برای Export SurrealDB در همان Workflow (بخش ۷.۴) و تست واقعی چرخهٔ رمزنگاری/رمزگشایی — انجام شد (۳۵۱٬۳۹۱ بایت با موفقیت رمزگشایی شد)
- [x] اتصال `[OPS-01]` به Global Error Workflow برای هشدار Bale Messenger در صورت شکست (بخش ۷.۵) + افزودن ناظر مستقل `[OPS-02] Nightly Backup Heartbeat Check`
- [ ] نوشتن اسکریپت ساخت Qdrant Collection (نام، ابعاد، Distance، Indexها طبق META-INT-020)
- [ ] اجرای یک بازیابی آزمایشی کامل روی محیط جدا و ثبت نتیجه در این نود (بخش ۸، گام C.۷ — هنوز باز)
- [ ] 🆕 چرخش (Rotate) اعتبارنامه‌های زیر که حین این دوره پیاده‌سازی عیناً در چت/لاگ‌های اشتراکی ظاهر شدند: پسورد Root سورئال، `INFRA_BACKUP_ENC_KEY`، پسورد Postgres، Open Notebook، کلید رمزگذاری n8n، Qdrant، توکن ربات بله — طبق META-INT-100
- [ ] 🆕 تشخیص ریشه‌ای علت یک‌بار عدم‌ارسال پیام خطا با وجود اجرای ناموفق قابل‌مشاهده در Executions (بخش ۱۰، شکاف ۸)

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

- **v0.4.0 (۱۴۰۵-۰۸-۰۷):** `[OPS-01] Nightly Infra Export` از طراحی به **پیاده‌سازی واقعی، تست‌شده و Active** رسید (بخش ۷ کاملاً بازنویسی شد). معماری نهایی ۲۵ گره دارد (نه ۱۹ طراحی اولیه) در ۴ شاخهٔ موازی + Merge + زنجیرهٔ Git؛ تفاوت‌های کلیدی با طراحی اولیه در بخش ۷.۷ جدید («یافته‌های کلیدی حین پیاده‌سازی») با ۱۱ یافتهٔ مستند ثبت شد، مهم‌ترین‌شان کشف این‌که گرهٔ Git بومی n8n به‌صورت عمدی (نه باگ) هر `core.sshCommand`/`GIT_SSH_COMMAND` سفارشی را نادیده می‌گیرد و فقط از طریق فایل `~/.ssh/config` خودِ کلاینت SSH می‌توان کلید Deploy Key اختصاصی را معرفی کرد. سه Bind Mount (نه دو) لازم بود چون `GET /api/v1/community-packages` بسته‌های نصب‌شدهٔ دستی (`n8n-nodes-bale-messenger-alpha`) را نشان نمی‌دهد. تست End-to-End کامل (Export → Sanitize → رمزنگاری → Git Commit/Push واقعی) و یک تست DR واقعی (رمزگشایی ۳۵۱٬۳۹۱ بایت Dump سورئال) با موفقیت انجام شد. اطلاع‌رسانی دوطرفه (موفقیت/خطا) از طریق Bale Messenger با الگوی موجود `[KNW-02]` پیاده شد؛ یک Workflow جدید `[OPS-00] Global Error Alert (Bale)` به‌عنوان Global Error Workflow ساخته شد؛ یک Workflow مستقل سوم `[OPS-02] Nightly Backup Heartbeat Check` به‌عنوان Dead Man's Switch اضافه شد تا سناریوی کشف‌شدهٔ «اجرای ناموفق بدون هیچ پیام هشدار» را هم پوشش دهد. ساختار واقعی مخزن (بخش ۷.۱)، بخش‌های ۸ تا ۱۱ همگی با وضعیت واقعی جدید به‌روزرسانی شدند؛ یک اقدام جدید (چرخش اعتبارنامه‌های افشاشده حین این دوره) و دو شکاف جدید (قفل SSH گرهٔ Git، قابلیت‌اطمینان ناشناختهٔ Error Workflow) ثبت شد.
- **v0.3.0 (۱۴۰۵-۰۸-۰۶):** بازنویسی کامل بخش ۷ («روش پیاده‌سازی پیشنهادی») برای معماری واقعی VPS: طراحی کامل Workflow `[OPS-01] Nightly Infra Export` با ۱۹ گره مبتنی بر **n8n Public API** (نه CLI/Execute Command که غیرفعال است)، **Read/Write Files from Disk** (پس از گسترش `N8N_RESTRICT_FILE_ACCESS_TO`)، و **رمزنگاری AES-256-GCM درون Code Node** (نه ابزار خارجی `age`) برای Dump سورئال؛ پوشش کامل دامنهٔ اصلی درخواست‌شده (Workflowها، Credential-metadata، Community-packages، `docker-compose.yml`/`.env.example`، Dump رمزنگاری‌شدهٔ SurrealDB) در یک Workflow واحد؛ مستندسازی پیش‌نیازهای یک‌بارهٔ دستی (API Key، دو Credential جدید، سه متغیر محیطی جدید، دو Bind Mount جدید)؛ جایگزینی گام Commit/Push مبتنی بر PowerShell/Task Scheduler ویندوز با گره بومی Git (همان الگوی از پیش ساخته‌شدهٔ `xennic-infra-backups`)؛ افزودن یادداشت‌های تاریخی روی بخش‌های ۱ و ۲ برای حفظ ردیابی تصمیم بدون حذف محتوای گذشته؛ افزودن وابستگی به META-INT-140؛ به‌روزرسانی بخش‌های ۸، ۹ و ۱۱ متناسب با طراحی جدید.
- **v0.2.2 (۱۴۰۵-۰۸-۰۱):** به‌روزرسانی یادداشت بخش ۷.۴ («جایگزین برای آینده») برای ارجاع به تصمیم قطعی مالک در نود جدید [[META-INT-140 — نقشه مهاجرت زیرساخت اتوماسیون به سرور اختصاصی (VPS)|META-INT-140]] (مهاجرت دیگر فقط یک گزینهٔ احتمالی نیست، بلکه تصمیم‌شده است).
- **v0.2.1 (۱۴۰۵-۰۸-۰۱):** رفع اشکال رندر جدول‌ها — Escape کردن `|` داخل لینک‌های Wiki در جدول‌های بخش‌های ۲ و ۸ که باعث شکستن ستون‌بندی جدول در رندررهای استاندارد Markdown (از جمله GitHub) می‌شد؛ بدون تغییر محتوایی.
- **v0.2.0 (۱۴۰۵-۰۷-۳۰):** افزودن دستورالعمل اجرایی مشخص (بخش ۷) برای Backup خودکار n8n (Workflow/Credentials/Community Packages)، Hermes (`config.yaml`) و Open Notebook (SurrealDB رمزنگاری‌شده با `age`) به یک مخزن Git مجزا (`xennic-infra-backups`)؛ کشف و ثبت شکاف جدید «فهرست بسته‌های Community نصب‌شده هیچ‌جا ثبت نشده»؛ افزودن بخش توضیح الگوی مرجع Obsidian؛ تفکیک نقشه راه اجرایی ریزدانه (فاز C) از نقشه راه کلان META-INT-130؛ تغییر وضعیت به `review`.
- **v0.1.0 (۱۴۰۵-۰۷-۳۰):** ایجاد اولیه در پی ممیزی کامل پوشه `00_Meta/Integration` — مستندسازی شکاف «عدم وجود Infrastructure as Code و برنامه بازیابی پس از خرابی» و ریسک تک‌نقطه‌ای بودن زیرساخت روی یک کامپیوتر شخصی.
