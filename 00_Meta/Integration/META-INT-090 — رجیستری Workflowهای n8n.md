---
id: META-INT-090
title: رجیستری Workflowهای n8n
status: review
created: 2026-10-22
tags: [integration, n8n, registry, governance, automation]
layer: Meta
domain: INT
owner: احمد فیروزمندی بندپی
version: 0.2.0
dependencies: [META-INT-080, META-INT-020, META-INT-033, META-INT-034, META-INT-060, META-INT-100]
---

# رجیستری Workflowهای n8n

> [!abstract] هدف
> این نود مرجع یکتای **فهرست همه Workflowهای n8n** در زیرساخت Xennic است: نام، شناسه فنی، نوع Trigger، وضعیت فعال/غیرفعال، مالک و آخرین بازبینی. بدون این رجیستری، هیچ‌کس — نه انسان و نه عامل هوشمند (Hermes) — تصویر کاملی از این‌که «چه اتوماسیون‌هایی در حال اجرا هستند» ندارد.

## فهرست

| # | بخش | # | بخش |
|---|---|---|---|
| ۱ | هدف (Why) | ۶ | قاعده ثبت Workflow جدید (SOP) |
| ۲ | چرا این نود لازم شد | ۷ | شکاف‌های شناسایی‌شده |
| ۳ | جدول رجیستری | ۸ | اقدامات |
| ۴ | وضعیت‌های ممکن | ۹ | ارجاعات |
| ۵ | معیار Deactivate/Archive | ۱۰ | Changelog |

---

## ۱. هدف (Why)

این نود مرجع یکتای **فهرست همه Workflowهای n8n** در زیرساخت Xennic است: نام، شناسه فنی، نوع Trigger، وضعیت فعال/غیرفعال، مالک و آخرین بازبینی. بدون این رجیستری، هیچ‌کس — نه انسان و نه عامل هوشمند (Hermes) — تصویر کاملی از این‌که «چه اتوماسیون‌هایی در حال اجرا هستند» ندارد.

این نود پیاده‌سازی عملی مفهوم «رجیستری عامل‌های هوشمند سازمانی» (بند ۶ در [[META-INT-080 — معماری کلان سیستم‌عامل هوشمند سازمانی Xennic|META-INT-080]]) برای لایه خاص Workflowهای n8n است و خروجی فاز ۰ (شناخت وضع موجود) در همان معماری محسوب می‌شود.

---

## ۲. چرا این نود لازم شد

در بررسی نودهای [[META-INT-020 — RAG مشترک Obsidian + Open Notebook → Qdrant|META-INT-020]]، [[META-INT-033 — ادغام Hermes با MCP n8n-official|META-INT-033]]، [[META-INT-034 — ادغام Hermes با RAG مشترک|META-INT-034]] و [[META-INT-060 — تست RAG با FND-009|META-INT-060]] مشخص شد که فقط **یک** Workflow شناسه فنی ثبت‌شده داشت (`RAG-01`) و بقیه فقط با نام نمایشی ذکر شده بودند — بدون ID، بدون تاریخ، بدون مالک مشخص. این سطح از ابهام دقیقاً همان ریسکی است که META-INT-080 (بند ۱۲) با عنوان «ساخت سرویس‌های تکراری» هشدار می‌دهد.

> [!success] به‌روزرسانی ۱۴۰۵-۰۷-۳۰ — داده واقعی استخراج شد
> با اجرای `docker exec xennic-n8n n8n export:workflow --all` (چون n8n در این زیرساخت به‌صورت کانتینر Docker اجرا می‌شود، نه نصب native — بنابراین دستورات CLI مستقیم مثل `n8n list:workflow` روی هاست کار نمی‌کنند)، فهرست کامل و واقعی ۸ Workflow موجود استخراج شد. جدول بخش ۳ اکنون بر اساس این داده واقعی است، نه حدس.

---

## ۳. جدول رجیستری

> [!info] منبع داده
> خروجی کامل `docker exec xennic-n8n n8n export:workflow --all --output=/tmp/workflows.json` در تاریخ ۱۴۰۵-۰۷-۳۰. تمام Workflowها متعلق به پروژه شخصی «Ahmad Feerozmandi» در n8n هستند (تک‌مالکی — ریسک مرتبط در بخش ۷).

| نام نمایشی | ID فنی | Active | Trigger | هدف | ایجاد / آخرین تغییر | وضعیت توصیه‌شده |
|---|---|---|---|---|---|---|
| `[RAG-01] Obsidian Founder → Qdrant` | `DlHi16COhc9f0IkQ` | ❌ false | Manual | ایندکس نودهای `01_Founder/*.md` در Qdrant (طبق [[META-INT-020 — RAG مشترک Obsidian + Open Notebook → Qdrant\|META-INT-020]]) | ایجاد ۲۰۲۶-۱۰-۱۰ / تغییر ۲۰۲۶-۱۰-۱۷ | فعال (دستی) — availableInMCP: true — ⚠️ **باگ احتمالی**: گره Code با نام «Parse & Chunk» حاوی خط `for (const block offileBlocks)` است (به‌نظر فاقد فاصله/کلمه کلیدی `of` صحیح — در صورت اجرای واقعی خطای Syntax جاوااسکریپت می‌دهد)؛ نیاز به بررسی و اصلاح مستقیم در n8n توسط مالک (این نود فقط مستندسازی می‌کند و Workflow را ویرایش نمی‌کند) |
| `[RAG-02] Open Notebook → Qdrant` | `4KWc6FUbJrK9aOSU` | ❌ false | Manual | ایندکس Sourceهای Open Notebook در Qdrant | ایجاد ۲۰۲۶-۱۰-۱۳ / تغییر ۲۰۲۶-۱۰-۱۵ | فعال (دستی) — availableInMCP: نامشخص؛ پوشش واقعی ناقص (بخش ۷) |
| `[API-01] Semantic Search` (نسخه **زنده**) | `iB4FcmXQxCsI5by9` | ✅ **true** | Webhook GET `/search` | جستجوی معنایی زنده — همانی که Hermes و `/webhook/search` استفاده می‌کنند | ایجاد و تغییر ۲۰۲۶-۱۰-۱۷ | **فعال — Production** — availableInMCP: true |
| `[API-01] Semantic Search` (نسخه قدیمی) | `JTzPnp11wUFYPaMd` | ❌ false, isArchived: **true** | Webhook GET | نسخه قبلی همین جستجو؛ خود n8n آن را بایگانی کرده | ایجاد ۲۰۲۶-۱۰-۱۵ | منسوخ — از قبل درست بایگانی شده، اقدامی لازم نیست |
| `[KNW-02] Smart Source Downloader (Fixed)` | `KbZkNJsqsQCxP7SX` | ❌ false | Manual | دانلود خودکار منابع فهرست‌شده در [[L1-KNW-001 — فهرست جامع منابع مهندسی برق\|L1-KNW-001]]، تفکیک رایگان/غیررایگان، آپلود به Open Notebook، اطلاع‌رسانی نتیجه | ایجاد و تغییر ۲۰۲۶-۱۰-۱۸ | فعال (دستی) — **🆕 قبلاً در هیچ نود META-INT مستند نشده بود** |
| `My workflow` | `4Rab1lMRwaGlfUTe` | ❌ false | Manual | بدون نام/هدف مشخص؛ کپی ناقص از منطق RAG-02 (فقط دریافت فهرست Sourceها) | ایجاد و تغییر ۲۰۲۶-۱۰-۱۳ | **کاندید حذف** — باقی‌مانده آزمایشی بدون نام‌گذاری استاندارد |
| `[TEST] Open Notebook Connection` | `gmAPeHeg5c68XBON` | ❌ false | Manual | تست اولیه اتصال به API Open Notebook | ایجاد و تغییر ۲۰۲۶-۱۰-۱۰ | **کاندید حذف** — هدفش با ساخت RAG-02 محقق شد |
| `[TEST] Open Notebook API` | `u2NQHmHbnK6VOXWO` | ❌ false | Manual | تست endpointهای `/api/notebooks`, `/api/credentials`, `/api/sources` | ایجاد ۲۰۲۶-۱۰-۱۳ | **کاندید حذف** — همان دلیل بالا |

> [!warning] اطلاع‌رسانی خطا از طریق Bale Messenger است، نه Telegram
> در Workflow `[KNW-02]`، اعلان موفقیت/خطا از طریق **Bale Messenger** (پیام‌رسان ایرانی) پیاده‌سازی شده (گره‌های `n8n-nodes-bale-messenger-alpha.baleMessenger`)، نه Telegram که در پیشنهاد اولیه META-INT-020 (اتوماسیون ۷) ذکر شده بود. [[META-INT-120 — نظارت، هشدار و مدیریت خطا|META-INT-120]] بر این اساس اصلاح شد.

### Workflowهای کاندید حذف/بایگانی

سه Workflow (`My workflow`، `[TEST] Open Notebook Connection`، `[TEST] Open Notebook API`) باقی‌مانده آزمایشی اولیه هستند که هدفشان با ساخت نسخه نهایی RAG-02 محقق شده. طبق [[META-CONV-001 — قواعد توسعه پروژه|META-CONV-001]] (قاعده ۹، جلوگیری از شلوغی/موازی‌کاری)، پیشنهاد می‌شود پس از تأیید مالک، این سه حذف یا در n8n به‌صورت Archived علامت‌گذاری شوند. **این نود فقط ثبت می‌کند، حذف نمی‌کند** — تصمیم نهایی با مالک انسانی است.

---

## ۴. وضعیت‌های ممکن

| وضعیت | معنی |
|---|---|
| `فعال` | در n8n روشن است و طبق Trigger خودش اجرا می‌شود |
| `فعال (دستی)` | در n8n موجود است اما Trigger آن Manual است و کسی باید دستی اجرا کند |
| `غیرفعال` | در n8n خاموش شده اما حذف نشده |
| `منسوخ` | دیگر استفاده نمی‌شود؛ باید از n8n حذف و اینجا آرشیو شود |
| `نامشخص` | وضعیت واقعی در n8n بررسی نشده — نیاز به ممیزی |

---

## ۵. معیار Deactivate/Archive

- اگر Workflowای بیش از ۹۰ روز اجرا نشده و جایگزین مستند دارد → وضعیت آن به `منسوخ` تغییر کند و از n8n غیرفعال/حذف شود.
- پیش از حذف هر Workflow، باید export JSON آن (طبق [[META-INT-110 — زیرساخت به‌صورت کد و بازیابی پس از خرابی|META-INT-110]]) در مخزن نگهداری شود تا تاریخچه از دست نرود.

---

## ۶. قاعده ثبت Workflow جدید (SOP)

1. **پیش از ساخت هر Workflow جدید**، این جدول بررسی شود تا از ساخت نسخه تکراری جلوگیری شود (طبق قاعده ۹ در [[META-CONV-001 — قواعد توسعه پروژه|META-CONV-001]]).
2. بلافاصله پس از ساخت، یک ردیف جدید اینجا با نام، ID واقعی n8n، Trigger، هدف، مالک و تاریخ اضافه شود.
3. Credential استفاده‌شده در Workflow نباید در این نود ذکر شود — فقط نام Credential، طبق سیاست [[META-INT-100 — مدیریت Secrets و Credentials|META-INT-100]].
4. تغییر وضعیت (فعال/غیرفعال/منسوخ) باید همزمان با تغییر واقعی در n8n، در این جدول هم ثبت شود.

---

## ۷. شکاف‌های شناسایی‌شده

| # | شکاف | وضعیت |
|---|---|---|
| ۱ | ID فنی Workflowها نامشخص بود | ✅ **برطرف شد** — همه ۸ ID واقعی در بخش ۳ ثبت شد |
| ۲ | مشخص نبود Workflow «Backup به GitHub» ساخته شده یا نه | ✅ **برطرف شد** — تأیید شد چنین Workflowای در n8n وجود ندارد؛ Backup واقعی فقط از طریق افزونه `obsidian-git` انجام می‌شود (طبق [[META-INT-050 — راه‌اندازی کامل Hermes\|META-INT-050]]) |
| ۳ | هیچ Workflowای در Git نسخه‌بندی (export) نشده بود | ⚠️ **همچنان باز** — فایل `workflows.json` فقط در ترمینال محلی دیده شد، هنوز در مخزن Commit نشده (رجوع کنید به [[META-INT-110 — زیرساخت به‌صورت کد و بازیابی پس از خرابی\|META-INT-110]]) |
| ۴ | `RAG-02` فقط یک ID دارد اما پوشش واقعی آن نامشخص بود | ⚠️ **تشدید شد** — طبق Qdrant (`notebook_id` فقط روی ۱ از ۷۸ point ایندکس شده)، `RAG-02` عملاً فقط برای ۱ سند اجرا شده، نه برای محتوای ۷ Notebook تخصصی توصیف‌شده در [[META-INT-070 — نقشه Open Notebook برای n8n و Hermes\|META-INT-070]] |
| ۵ | ۳ Workflow آزمایشی بلااستفاده در n8n باقی مانده‌اند | 🆕 **یافته جدید** — `My workflow`، `[TEST] Open Notebook Connection`، `[TEST] Open Notebook API` (جدول بالا) |
| ۶ | یک Workflow واقعی (`[KNW-02]`) هیچ‌جا مستند نبود | 🆕 **یافته جدید، اکنون ثبت شد** در بخش ۳ |
| ۷ | تمام Workflowها زیر پروژه شخصی یک کاربر n8n هستند | ⚠️ **تأیید شد** — ریسک تک‌نفره بودن واقعی است، نه فرضی |

---

## ۸. اقدامات

- [x] ورود به n8n (از طریق `docker exec`) و استخراج ID، Trigger، وضعیت واقعی همه Workflowها
- [x] بررسی این‌که آیا Workflow «Backup به GitHub» واقعاً ساخته شده است — تأیید شد که نه
- [ ] **فوری:** اصلاح باگ Syntax (`for (const block offileBlocks)`) در گره Code «Parse & Chunk» از Workflow `[RAG-01]` مستقیماً در n8n (خارج از دامنه این Vault)
- [ ] Export JSON هر Workflow فعال و Commit در مخزن (پوشه `infra/n8n-workflows/`، پیش‌نیاز META-INT-110)
- [ ] تصمیم‌گیری درباره حذف/بایگانی ۳ Workflow آزمایشی بلااستفاده (نیازمند تأیید مالک انسانی)
- [ ] بررسی چرا `RAG-02` فقط ۱ point در Qdrant ایندکس کرده و اجرای کامل آن برای هر ۷ Notebook
- [ ] تعیین مالک مشخص برای هر Workflow (در حال حاضر همه روی یک نفر متمرکزند — ریسک تک‌نفره بودن)
- [ ] افزودن این رجیستری به‌عنوان منبع ارجاع در System Prompt یا ابزار MCP مربوط به Hermes

---

## ۹. ارجاعات

- [[META-INT-080 — معماری کلان سیستم‌عامل هوشمند سازمانی Xennic|META-INT-080]] — چارچوب رجیستری عامل‌های هوشمند (بند ۶)
- [[META-INT-020 — RAG مشترک Obsidian + Open Notebook → Qdrant|META-INT-020]]
- [[META-INT-033 — ادغام Hermes با MCP n8n-official|META-INT-033]]
- [[META-INT-034 — ادغام Hermes با RAG مشترک|META-INT-034]]
- [[META-INT-060 — تست RAG با FND-009|META-INT-060]]
- [[META-INT-070 — نقشه Open Notebook برای n8n و Hermes|META-INT-070]]
- [[L1-KNW-001 — فهرست جامع منابع مهندسی برق|L1-KNW-001]] — منبع ورودی Workflow جدید `[KNW-02]`
- [[META-INT-100 — مدیریت Secrets و Credentials|META-INT-100]]
- [[META-INT-110 — زیرساخت به‌صورت کد و بازیابی پس از خرابی|META-INT-110]]
- [[META-INT-120 — نظارت، هشدار و مدیریت خطا|META-INT-120]]

---

## ۱۰. Changelog

- **v0.2.0 (۱۴۰۵-۰۷-۳۰):** تکمیل کامل جدول رجیستری با داده واقعی استخراج‌شده از `docker exec xennic-n8n n8n export:workflow --all` — همه ۸ ID واقعی، وضعیت Active، و تاریخ ثبت شد؛ کشف و ثبت Workflow قبلاً مستندنشده `[KNW-02] Smart Source Downloader`؛ شناسایی ۳ Workflow آزمایشی کاندید حذف؛ تصحیح کانال اطلاع‌رسانی خطا از Telegram به Bale Messenger (واقعیت پیاده‌سازی‌شده)؛ تأیید عدم وجود Workflow «Backup به GitHub»؛ شناسایی شکاف پوشش ناقص `RAG-02` (فقط ۱ point ایندکس‌شده در Qdrant)؛ ثبت باگ Syntax احتمالی در گره Code از `[RAG-01]`؛ تغییر وضعیت به `review`.
- **v0.1.0 (۱۴۰۵-۰۷-۳۰):** ایجاد اولیه در پی ممیزی کامل پوشه `00_Meta/Integration` — مستندسازی شکاف «عدم وجود رجیستری رسمی Workflowها» که در META-INT-080 پیش‌بینی شده بود اما پیاده نشده بود.
