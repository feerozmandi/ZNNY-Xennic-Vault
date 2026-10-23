---
id: META-INT-110
title: زیرساخت به‌صورت کد و بازیابی پس از خرابی
status: review
created: 2026-10-22
tags: [integration, infrastructure, iac, disaster-recovery, docker, governance, git-automation]
layer: Meta
domain: INT
owner: احمد فیروزمندی بندپی
version: 0.2.2
dependencies: [META-INT-080, META-INT-050, META-INT-070, META-INT-090, META-INT-100, META-INT-130]
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

> [!success] به‌روزرسانی ۱۴۰۵-۰۷-۳۰ — از «برنامه‌ریزی» به «دستورالعمل اجرایی»
> نسخه قبلی این نود فقط شکاف‌ها را فهرست می‌کرد. این نسخه یک **روش مشخص، قابل‌اجرا و متناسب با محیط واقعی مالک** (Windows + Docker Desktop + تک‌اپراتور) ارائه می‌دهد (بخش ۷)، چون این زیرساخت قرار است پایه توسعه آینده و پیوستن افراد جدید به تیم باشد — نه فقط یک آزمایش شخصی (طبق تصمیم مالک، ثبت‌شده در بخش ۹ META-INT-130).

---

## ۲. وضعیت فعلی (As-Is)

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
| **فهرست بسته‌های Community نصب‌شده** (مثلاً `n8n-nodes-bale-messenger-alpha`) | n8n | 🆕 **تاکنون هیچ‌جا ثبت نشده بود** | ✅ `n8n/community-packages.txt` + ترجیحاً `Dockerfile` سفارشی که این بسته‌ها را از ابتدا نصب کند | 🔴 ضروری (بدون این، بازسازی کانتینر یعنی شکستن `[KNW-02]` به‌خاطر نبود گره Bale Messenger) |
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
> پیشنهاد می‌شود این Backupها در یک **مخزن Git کاملاً جدا** (مثلاً `xennic-infra-backups`، خصوصی) نگهداری شوند، **نه در همین مخزن `ZNNY-Xennic-Vault`**. دلیل:
> - این مخزن (Vault) برای **محتوای مرور و تأییدشده** است که هر تغییرش از طریق PR بررسی می‌شود (طبق [[META-CONV-001 — قواعد توسعه پروژه|META-CONV-001]])؛ Backup خام JSON/SurrealQL هرشب نیازی به بازبینی انسانی ندارد و فقط شلوغی تاریخچه Git و PRها را زیاد می‌کند.
> - امکان سیاست دسترسی/نگهداری جدا (مثلاً نگهداری فقط ۳۰ نسخه آخر) بدون اثرگذاری روی مخزن اصلی مستندات.
> - با قانون «هیچ Automation نباید مستقیماً روی `dev`/`main` همین Vault Commit کند» (یک قاعده ثابت این پروژه) کاملاً سازگار است — چون اصلاً مخزن دیگری است، نه این‌که Automation مجوز Commit مستقیم به `dev` همین Vault را بگیرد.

### ۷.۱ ساختار پیشنهادی مخزن Backup

```text
xennic-infra-backups/
├── n8n/
│   ├── workflows/                   # یک فایل JSON به‌ازای هر Workflow
│   ├── credentials-manifest.json    # فقط نام/نوع، مقدار همیشه رمزگذاری‌شده
│   └── community-packages.txt
├── hermes/
│   ├── config.yaml
│   └── mcp-list-snapshot.txt
├── open-notebook/
│   └── surrealdb-dump.surql.age     # رمزنگاری‌شده با age — بخش ۷.۳
├── infra/
│   ├── docker-compose.yml
│   └── .env.example
└── README.md                        # تاریخ آخرین Backup موفق + دستورالعمل بازیابی
```

### ۷.۲ گام Export (داخل n8n — بدون نصب ابزار جدید)

یک Workflow جدید در خود n8n بسازید (پیشنهاد نام‌گذاری: `[OPS-01] Nightly Infra Export`)، با **Schedule Trigger** (مثلاً ساعت ۰۳:۰۰ هر شب، زمانی که هیچ‌کس از سیستم استفاده نمی‌کند):

1. گره **Execute Command** (دقیقاً همان الگویی که در `[RAG-01]` برای خواندن فایل‌های Obsidian استفاده شده):
   ```bash
   n8n export:workflow --all --separate --output=/backup/n8n/workflows/
   n8n export:credentials --all --output=/backup/n8n/credentials-manifest.json
   ```
2. گره دوم برای ثبت فهرست بسته‌های Community نصب‌شده:
   ```bash
   ls /home/node/.n8n/nodes/node_modules | grep n8n-nodes- > /backup/n8n/community-packages.txt
   ```
3. مسیر `/backup` باید در `docker-compose.yml` به یک پوشه روی هاست (Windows) Mount شده باشد، مثلاً: `F:\ahmad\xennic-infra-backups\n8n:/backup/n8n`.
4. این Workflow را به **Global Error Workflow** پیشنهادی در [[META-INT-120 — نظارت، هشدار و مدیریت خطا|META-INT-120]] وصل کنید تا اگر Export شکست خورد، همان لحظه در Bale Messenger اطلاع داده شود — نه این‌که هفته‌ها بعد کشف شود.

> چرا این گام داخل n8n باشد، نه یک اسکریپت جداگانه؟ چون `n8n export:...` یک دستور بومی و از پیش نصب‌شده همان Image رسمی n8n است (بدون نیاز به نصب ابزار اضافه در کانتینر)، و چون این‌طوری شکست آن هم مثل بقیه Workflowها زیر همان چتر نظارتی و هشدار یکپارچه META-INT-120 قرار می‌گیرد.

### ۷.۳ گام Export رمزنگاری‌شده Open Notebook (SurrealDB)

چون Dump کامل SurrealDB می‌تواند شامل محتوای Notebook `Corporate` باشد، این گام **باید** از ابتدا رمزنگاری‌شده روی دیسک بنشیند:

1. یک‌بار برای همیشه یک جفت کلید `age` تولید کنید (ابزار سبک و متن‌باز رمزنگاری فایل):
   ```bash
   age-keygen -o xennic-backup-key.txt   # کلید خصوصی را فقط روی یک محل امن (نه در هیچ Git) نگه دارید
   ```
2. در همان Workflow `[OPS-01]` یا یک Workflow جدا، یک گره Execute Command دیگر:
   ```bash
   docker exec open-notebook-surrealdb-1 surreal export --conn http://localhost:8000 --user root --pass root --ns xennic --db notebook - \
     | age -r <کلید-عمومی-age> > /backup/open-notebook/surrealdb-dump.surql.age
   ```
   نکتهٔ کلیدی: خروجی `surreal export` هرگز به‌صورت متن ساده روی دیسک نمی‌نشیند — مستقیماً از طریق Pipe وارد `age` می‌شود و فقط نسخه رمزنگاری‌شده ذخیره می‌گردد.
3. کلید خصوصی `age` را فقط مالک نگه می‌دارد (مثلاً در یک مدیریت رمز محلی یا یک USB آفلاین) — این کلید هرگز نباید در هیچ مخزن Git (نه Vault، نه `xennic-infra-backups`) قرار گیرد.

### ۷.۴ گام Commit/Push (بیرون از n8n — روی خود ویندوز)

از آنجا که مالک فعلی روی ویندوز و PowerShell کار می‌کند (همان محیطی که همه دستورات تشخیصی قبلی در آن اجرا شد)، ساده‌ترین و کم‌ریسک‌ترین روش یک اسکریپت کوچک PowerShell است که توسط **Task Scheduler ویندوز** چند دقیقه بعد از زمان Export در n8n اجرا می‌شود (مثلاً ساعت ۰۳:۱۵):

```powershell
# backup-commit.ps1
Set-Location "F:\ahmad\xennic-infra-backups"
Copy-Item "C:\Users\Narges\AppData\Local\hermes\config.yaml" "hermes\config.yaml" -Force
git add -A
git commit -m "chore: nightly infra snapshot $(Get-Date -Format 'yyyy-MM-dd')"
git push origin main
```

> [!tip] چرا این مرحله خارج از Docker/n8n باشد؟
> نصب `git` و نگهداری یک GitHub Token داخل کانتینر n8n، سطح حمله (Attack Surface) آن کانتینر را بیشتر می‌کند. نگه‌داشتن این مرحله روی خود ویندوز، GitHub Token را کاملاً جدا از n8n و Docker نگه می‌دارد — دقیقاً همان اصل «دسترسی حداقلی» در [[META-INT-100 — مدیریت Secrets و Credentials|META-INT-100]] (بخش ۴).

> [!note] جایگزین برای آینده (مهاجرت به سرور Linux)
> طبق تصمیم مالک مستندشده در [[META-INT-140 — نقشه مهاجرت زیرساخت اتوماسیون به سرور اختصاصی (VPS)|META-INT-140]]، این زیرساخت به‌زودی به یک VPS لینوکسی منتقل می‌شود؛ در آن حالت Task Scheduler ویندوز وجود نخواهد داشت و همین گام با یک Cron Job سادهٔ لینوکسی یا یک Container کوچک و سبک اختصاصی «Git-Sync» (که فقط یک پوشه را به‌صورت دوره‌ای Commit/Push می‌کند) جایگزین می‌شود — بدون تغییر در بخش‌های ۷.۲ و ۷.۳.

### ۷.۵ جدول خلاصه مسئولیت هر جزء

| جزء | کجا اجرا می‌شود | چرا آنجا |
|---|---|---|
| Export workflow/credentials/community-packages | داخل n8n (Execute Command) | دستور بومی n8n است؛ زیر نظارت Global Error Workflow قرار می‌گیرد |
| Export رمزنگاری‌شده SurrealDB | داخل n8n یا یک Workflow جدا، با Pipe مستقیم به `age` | هرگز نباید نسخه متن‌باز Corporate روی دیسک بنشیند |
| Copy فایل `config.yaml` هرمس | اسکریپت PowerShell روی ویندوز | فایل روی خود ویندوز است، نیازی به عبور از Docker ندارد |
| Commit/Push به Git | اسکریپت PowerShell + Task Scheduler ویندوز | GitHub Token را از Docker/n8n جدا نگه می‌دارد |
| هشدار شکست هرکدام | Global Error Workflow در n8n → Bale Messenger | یک کانال واحد هشدار، طبق META-INT-120 |

---

## ۸. برنامه بازیابی پس از خرابی (DR)

| مرحله | اقدام | پیش‌نیاز |
|---|---|---|
| ۱ | Clone کردن `xennic-infra-backups` و بازسازی `docker-compose.yml` برای n8n + Qdrant + TEI + Open Notebook | وجود `infra/docker-compose.yml` در Git |
| ۲ | نصب بسته‌های Community فهرست‌شده در `n8n/community-packages.txt` پیش از اولین اجرای n8n | وجود این فایل در Git (بخش ۴) |
| ۳ | اجرای اسکریپت ساخت Collection در Qdrant با همان نام/ابعاد/Index | وجود اسکریپت نسخه‌بندی‌شده |
| ۴ | Import مجدد Workflowهای n8n از فایل‌های Export شده | وجود export JSON در Git |
| ۵ | بازسازی Credentialها از محل رسمی (نه از حافظه) طبق META-INT-100 | اجرای کامل META-INT-100 |
| ۶ | رمزگشایی `surrealdb-dump.surql.age` با کلید خصوصی `age` (فقط نزد مالک) و Import به SurrealDB جدید | کلید خصوصی `age` در دسترس باشد |
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
| C.۳ | ساخت Workflow `[OPS-01] Nightly Infra Export` در n8n (بخش ۷.۲) | Export خودکار شبانه Workflow/Credentials/Community packages |
| C.۴ | تولید یک‌باره جفت‌کلید `age` و اتصال مرحله Export رمزنگاری‌شده SurrealDB (بخش ۷.۳) | Backup امن Open Notebook بدون افشای Corporate |
| C.۵ | نوشتن و زمان‌بندی `backup-commit.ps1` در Task Scheduler ویندوز (بخش ۷.۴) | Commit/Push خودکار شبانه، بدون دخالت دستی |
| C.۶ | اتصال Workflow `[OPS-01]` به Global Error Workflow (پیش‌نیاز از فاز B در META-INT-130) | هشدار فوری در صورت شکست هر مرحله Backup |
| C.۷ | یک بار اجرای کامل بازیابی روی یک محیط تست (VM جداگانه) برای اعتبارسنجی برنامه DR (بخش ۸) | اثبات واقعی قابلیت بازیابی، نه فقط ادعا |

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

- [ ] ساخت مخزن `xennic-infra-backups` (خصوصی) با ساختار بخش ۷.۱
- [ ] نوشتن `infra/docker-compose.yml` برای n8n، Qdrant، TEI و Open Notebook با نسخه‌های دقیق فعلی
- [ ] ساخت Workflow `[OPS-01] Nightly Infra Export` در n8n (بخش ۷.۲)
- [ ] تولید جفت‌کلید `age` و پیاده‌سازی Export رمزنگاری‌شده SurrealDB (بخش ۷.۳)
- [ ] نوشتن `backup-commit.ps1` و زمان‌بندی آن در Task Scheduler ویندوز (بخش ۷.۴)
- [ ] نوشتن اسکریپت ساخت Qdrant Collection (نام، ابعاد، Distance، Indexها طبق META-INT-020)
- [ ] اجرای یک بازیابی آزمایشی کامل روی محیط جدا و ثبت نتیجه در این نود
- [ ] تصمیم‌گیری درباره انتقال به سرور (داخلی یا ابری) به‌جای کامپیوتر شخصی — هم‌زمان با فاز E در META-INT-130

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

- **v0.2.2 (۱۴۰۵-۰۸-۰۱):** به‌روزرسانی یادداشت بخش ۷.۴ («جایگزین برای آینده») برای ارجاع به تصمیم قطعی مالک در نود جدید [[META-INT-140 — نقشه مهاجرت زیرساخت اتوماسیون به سرور اختصاصی (VPS)|META-INT-140]] (مهاجرت دیگر فقط یک گزینهٔ احتمالی نیست، بلکه تصمیم‌شده است).
- **v0.2.1 (۱۴۰۵-۰۸-۰۱):** رفع اشکال رندر جدول‌ها — Escape کردن `|` داخل لینک‌های Wiki در جدول‌های بخش‌های ۲ و ۸ که باعث شکستن ستون‌بندی جدول در رندررهای استاندارد Markdown (از جمله GitHub) می‌شد؛ بدون تغییر محتوایی.
- **v0.2.0 (۱۴۰۵-۰۷-۳۰):** افزودن دستورالعمل اجرایی مشخص (بخش ۷) برای Backup خودکار n8n (Workflow/Credentials/Community Packages)، Hermes (`config.yaml`) و Open Notebook (SurrealDB رمزنگاری‌شده با `age`) به یک مخزن Git مجزا (`xennic-infra-backups`)؛ کشف و ثبت شکاف جدید «فهرست بسته‌های Community نصب‌شده هیچ‌جا ثبت نشده»؛ افزودن بخش توضیح الگوی مرجع Obsidian؛ تفکیک نقشه راه اجرایی ریزدانه (فاز C) از نقشه راه کلان META-INT-130؛ تغییر وضعیت به `review`.
- **v0.1.0 (۱۴۰۵-۰۷-۳۰):** ایجاد اولیه در پی ممیزی کامل پوشه `00_Meta/Integration` — مستندسازی شکاف «عدم وجود Infrastructure as Code و برنامه بازیابی پس از خرابی» و ریسک تک‌نقطه‌ای بودن زیرساخت روی یک کامپیوتر شخصی.
