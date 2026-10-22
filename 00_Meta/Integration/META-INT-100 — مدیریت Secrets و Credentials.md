---
id: META-INT-100
title: مدیریت Secrets و Credentials
status: review
created: 2026-10-22
tags: [integration, security, secrets, credentials, governance]
layer: Meta
domain: INT
owner: احمد فیروزمندی بندپی
version: 0.2.0
dependencies: [META-INT-080, META-INT-050, META-INT-033, META-INT-090, L2-SEC-001]
---

# مدیریت Secrets و Credentials

> [!abstract] هدف
> تعیین سیاست یکتا برای ذخیره‌سازی، دسترسی و چرخش (Rotation) کلیدهای API، توکن‌های OAuth و Credentialهای زیرساخت اتوماسیون (n8n، Hermes، Qdrant، Open Notebook، GitHub) — موضوعی که در سیاست کلی امنیت اطلاعات شرکت ([[L2-SEC-001 — امنیت اطلاعات|L2-SEC-001]]) در سطح عملیاتی پوشش داده نشده است.

## فهرست

| # | بخش | # | بخش |
|---|---|---|---|
| ۱ | هدف (Why) | ۶ | چرخه تعویض (Rotation) |
| ۲ | چرا این نود لازم شد | ۷ | پاسخ به نشت احتمالی |
| ۳ | فهرست Secretهای شناخته‌شده | ۸ | شکاف‌های شناسایی‌شده |
| ۴ | اصول نگهداری | ۹ | اقدامات |
| ۵ | سطح دسترسی | ۱۰ | ارجاعات |
| | | ۱۱ | Changelog |

---

## ۱. هدف (Why)

تعیین سیاست یکتا برای ذخیره‌سازی، دسترسی و چرخش (Rotation) کلیدهای API، توکن‌های OAuth و Credentialهای زیرساخت اتوماسیون (n8n، Hermes، Qdrant، Open Notebook، GitHub) — موضوعی که در سیاست کلی امنیت اطلاعات شرکت ([[L2-SEC-001 — امنیت اطلاعات|L2-SEC-001]]) در سطح عملیاتی پوشش داده نشده است.

این نود، تفصیل عملیاتی اصل «Auditability» و «Human-in-the-loop» از [[META-INT-080 — معماری کلان سیستم‌عامل هوشمند سازمانی Xennic|META-INT-080]] (بند ۲.۳) برای زیرساخت فنی فعلی است.

---

## ۲. چرا این نود لازم شد

در بررسی نودهای فنی موجود، این موارد Secret/Credential بدون سیاست مشخص یافت شد:

- کلید API سرویس `gapgpt.app` (استفاده‌شده در [[META-INT-010 — RAG Obsidian → Qdrant — تکمیل|META-INT-010]]، بایگانی‌شده)
- توکن OAuth 2.1 بین Hermes و n8n (طبق [[META-INT-033 — ادغام Hermes با MCP n8n-official|META-INT-033]])
- دسترسی API به Qdrant (`http://localhost:6333`) و سرویس Embedding محلی TEI (`http://localhost:8001`)
- دسترسی API به Open Notebook (`http://localhost:5055`)
- پیکربندی Hermes در `config.yaml` که شامل اطلاعات Provider مدل است

هیچ‌کدام در مستندات موجود مشخص نمی‌کند این موارد **کجا ذخیره می‌شوند** (در n8n Credentials، در فایل محلی، در متغیر محیطی؟)، **چه کسی** به آن‌ها دسترسی دارد، و **چه زمانی** باید تعویض شوند. از آنجا که تمام این سرویس‌ها فعلاً روی یک کامپیوتر شخصی اجرا می‌شوند (طبق META-INT-050 و META-INT-070)، ریسک قرار گرفتن این Secretها در فایل‌های محلی بدون رمزنگاری بالاست.

> [!success] به‌روزرسانی ۱۴۰۵-۰۷-۳۰ — فهرست واقعی Credentialهای n8n استخراج شد
> با اجرای `docker exec xennic-n8n n8n export:credentials --all` (بدون `--decrypted` — طبق سیاست این نود، مقدار رمزگذاری‌شده Secretها هرگز بازیابی یا در Vault نوشته نمی‌شود)، فهرست کامل و واقعی ۹ Credential ثبت‌شده در n8n استخراج شد. جدول بخش ۳ اکنون شامل این داده واقعی است. **همچنین یک تصحیح مهم:** بررسی مستقیم API سرویس Open Notebook نشان داد که برخلاف فرض اولیه، این سرویس **بدون Auth نیست** — یک Header Auth واقعی (`Header Auth account` در n8n) برای تمام تماس‌ها با آن الزامی است.

---

## ۳. فهرست Secretهای شناخته‌شده

> [!warning] این جدول صرفاً شناسایی می‌کند، مقدار واقعی هیچ Secret را افشا نمی‌کند
> طبق سیاست، مقدار هیچ کلید/توکنی نباید در Git یا در این Vault نوشته شود — فقط **نام**، **نوع** و **کاربرد** Credential.

### ۳.۱ Credentialهای ثبت‌شده در n8n (۹ مورد — منبع: `n8n export:credentials --all`)

| نام در n8n | نوع (Type) | کاربرد واقعی | حساسیت | یادداشت |
|---|---|---|---|---|
| `Header Auth account` | `httpHeaderAuth` | Auth برای تمام تماس‌های n8n با Open Notebook API (`RAG-02`، `KNW-02`، هر دو نسخه `API-01`، هر دو Workflow تست) | 🔴 محرمانه | **تصحیح نسبت به فرض قبلی** — Open Notebook بدون Auth نیست |
| `OpenAI account` | `openAiApi` | ثبت‌شده در n8n اما در هیچ‌یک از ۸ Workflow موجود مصرف نمی‌شود | 🟡 نیازمند بازبینی | احتمالاً باقی‌مانده از آزمایش اولیه، یا مصرف‌شونده مستقیماً توسط خود Open Notebook (خارج از n8n) — نیاز به تأیید مالک |
| `GapGPT API Key` | `httpHeaderAuth` | کلید API ارائه‌دهنده مدل زبانی gapgpt، ذخیره‌شده داخل n8n Credentials Store | 🔴 محرمانه | جدا از Hermes — در `config.yaml` هرمس کلید خام دیده نشد؛ این یکی مستقل است |
| `Xennic Qdrant` | `qdrantApi` | اتصال به Qdrant | 🔴 محرمانه | **تکراری با ردیف بعدی** — بخش ۸ |
| `Qdrant account` | `qdrantRestApi` | اتصال به Qdrant، با نوع متفاوت نسبت به بالا | 🔴 محرمانه | **تکراری با ردیف بالا** — پیشنهاد ادغام به یک Credential واحد |
| `APITemplate.io account` | `apiTemplateIoApi` | **نامشخص** — در هیچ‌یک از ۸ Workflow Export‌شده مصرف نمی‌شود | 🟡 نیازمند بازبینی | سرویس تولید خودکار تصویر/PDF از Template؛ نیاز به توضیح مالک درباره کاربرد فعلی یا آتی |
| `BaleMessenger account` | `baleMessengerApi` | اعلان موفقیت/خطا/لینک ذخیره‌شده در Workflow `[KNW-02]` | 🔴 محرمانه | کانال اطلاع‌رسانی واقعی پروژه (نه Telegram) — رجوع به [[META-INT-120 — نظارت، هشدار و مدیریت خطا\|META-INT-120]] |
| `n8n Assistant model` | `openRouterApi` (`usageScope: instance`) | ویژگی داخلی «AI Assistant» خود n8n (پیشنهاد اصلاح Workflow) | 🟡 داخلی n8n | بی‌ربط به Workflowهای RAG سفارشی؛ دسته‌بندی جدا برای جلوگیری از سردرگمی |
| `n8n Assistant sandbox` | `daytonaApi` (`usageScope: instance`) | Sandbox اجرای کد برای ویژگی AI Assistant داخلی n8n | 🟡 داخلی n8n | همانند بالا — ویژگی پلتفرم n8n، نه بخشی از معماری RAG این پروژه |

### ۳.۲ Secretهای خارج از n8n Credentials Store

| Secret | کاربرد | محل فعلی (برآورد) | محل پیشنهادی | حساسیت |
|---|---|---|---|---|
| OAuth Token (Hermes ↔ n8n) | اتصال MCP (`n8n-official` طبق [[META-INT-033 — ادغام Hermes با MCP n8n-official\|META-INT-033]]) | Local token store | همان، + Rotation خودکار | 🟠 محدود |
| توکن GitHub (برای Backup/CI) | Push خودکار Vault | نامشخص | GitHub Actions Secrets (نه فایل محلی) | 🔴 محرمانه |
| کلید API Local REST در Obsidian (پلاگین Local REST API) | دسترسی n8n/Hermes به محتوای Vault از طریق `host.docker.internal:27124` | فایل تنظیمات پلاگین Obsidian (محلی) | بدون تغییر، مشروط به چرخش دوره‌ای | 🔴 محرمانه — **این کلید و RSA/CA Private Keyهای مرتبط با آن قبلاً به‌صورت متن ساده در گفتگوی تشخیصی دیده شدند؛ توصیه فوری: تعویض (Rotate) این کلید و گواهی‌ها در اولین فرصت، اگر هنوز انجام نشده** |

---

## ۳.۳ شکاف Auth روی سرویس‌های دیگر

| سرویس | وضعیت Auth واقعی |
|---|---|
| Qdrant (`http://localhost:6333`) | بدون Auth، فقط محدود به `localhost` |
| TEI Embedding (`xennic-embedding`) | بدون Auth، فقط محدود به شبکه داخلی Docker |
| Open Notebook API (`:5055`) | **دارای Auth** (`Header Auth account`) — تصحیح‌شده، بخش ۲ |

---

## ۴. اصول نگهداری

| # | اصل | شرح |
|---|---|---|
| ۱ | هیچ Secret در Git نوشته نمی‌شود | نه در کد، نه در مستندات Obsidian، نه در فایل‌های پیکربندی Commit‌شده |
| ۲ | هر Secret دقیقاً یک محل ذخیره رسمی دارد | طبق اصل Single Source of Truth در META-INT-080 |
| ۳ | دسترسی حداقلی (Least Privilege) | هر Workflow/Agent فقط به Credentialهایی که واقعاً لازم دارد دسترسی داشته باشد |
| ۴ | Secret مخصوص Corporate Notebook هرگز به API خارجی ارسال نمی‌شود | طبق [[META-INT-070 — نقشه Open Notebook برای n8n و Hermes|META-INT-070]] (ردیف Corporate) |

---

## ۵. سطح دسترسی

به‌جای این‌که همه Secretها در دسترس یک حساب باشند، دسترسی باید بر اساس نقش تعریف شود — منطبق با رجیستری عامل‌ها در META-INT-080 (بند ۶):

| نقش | دسترسی مجاز |
|---|---|
| مدیرعامل (مالک انسانی) | دسترسی کامل به همه Secretها |
| Hermes Agent | فقط توکن‌های لازم برای ابزارهای مجاز خودش (MCP obsidian، MCP n8n) |
| n8n Workflow | فقط Credential مشخص‌شده در همان Workflow، نه دسترسی سراسری |
| عامل‌های آینده (فروش، بازاریابی، ...) | هیچ دسترسی مستقیم به Secretهای زیرساختی؛ فقط از طریق API داخلی با سطح اختیار محدود (L0–L2 طبق Authority Matrix) |

---

## ۶. چرخه تعویض (Rotation)

| Secret | دوره پیشنهادی تعویض | محرک تعویض فوری |
|---|---|---|
| OAuth Token Hermes↔n8n | خودکار توسط پروتکل OAuth | نشت احتمالی، تغییر دستگاه |
| کلید API مدل زبانی | هر ۹۰ روز یا تغییر ارائه‌دهنده | نشت، تغییر پلن |
| توکن GitHub | هر ۱۸۰ روز | تغییر دسترسی ریپازیتوری، خروج همکار |
| Credential n8n داخلی | بازبینی سالانه | تغییر سرویس مقصد |

---

## ۷. پاسخ به نشت احتمالی

۱. **توقف فوری** Workflow یا Agent مرتبط.
۲. **ابطال (Revoke)** Secret نشت‌یافته در سرویس مبدأ.
۳. **صدور Secret جدید** و به‌روزرسانی محل ذخیره رسمی.
۴. **ثبت رخداد** طبق رویه پاسخ به حادثه در [[L2-SEC-001 — امنیت اطلاعات|L2-SEC-001]].
۵. **بازبینی** این‌که آیا Secret دیگری هم در همان کانال نشت در معرض خطر بوده است.

---

## ۸. شکاف‌های شناسایی‌شده

| # | شکاف | وضعیت |
|---|---|---|
| ۱ | محل دقیق نگهداری کلید API gapgpt و توکن GitHub هنوز تأیید نشده بود | ✅ **تا حدی برطرف شد** — کلید gapgpt در n8n Credentials Store تأیید شد (`GapGPT API Key`)؛ محل توکن GitHub همچنان نامشخص |
| ۲ | هیچ سیاست Rotation واقعی اجرا نشده؛ تاریخ آخرین تعویض هیچ Secret ثبت نشده | ⚠️ **همچنان باز** |
| ۳ | چون همه سرویس‌ها روی `localhost` بدون Auth اجرا می‌شوند، ریسک دسترسی غیرمجاز وجود دارد | ⚠️ **تفکیک شد** — Open Notebook واقعاً Auth دارد؛ Qdrant و TEI همچنان بدون Auth هستند (بخش ۳.۳) |
| ۴ | دو Credential جداگانه (`Xennic Qdrant` و `Qdrant account`) برای همان سرویس Qdrant وجود دارد | 🆕 **یافته جدید** — ریسک سردرگمی درباره این‌که کدام Credential «رسمی» است؛ پیشنهاد ادغام |
| ۵ | کاربرد Credential `APITemplate.io account` نامشخص و در هیچ Workflow فعلی دیده نمی‌شود | 🆕 **یافته جدید** — نیازمند توضیح مالک: سرویس فعال است یا باقی‌مانده از آزمایش؟ |
| ۶ | کلید API محلی Obsidian (Local REST API) و کلیدهای RSA/CA مرتبط در یک گفتگوی تشخیصی به‌صورت متن ساده مشاهده شدند | 🔴 **باز و حیاتی** — تأیید نشده که این کلید/گواهی‌ها تاکنون Rotate شده باشند؛ تا تأیید، این مورد باید بالاترین اولویت امنیتی تلقی شود |

---

## ۹. اقدامات

- [x] تأیید محل دقیق ذخیره Credentialهای داخل n8n (با export مستقیم از `docker exec xennic-n8n n8n export:credentials --all`)
- [x] تصحیح فرض نادرست «Open Notebook بدون Auth است»
- [ ] **اولویت بالا:** تأیید این‌که کلید Local REST API و گواهی‌های RSA/CA مرتبط Obsidian Rotate شده‌اند یا نه؛ در صورت عدم انجام، Rotate فوری
- [ ] ادغام دو Credential تکراری Qdrant (`Xennic Qdrant` و `Qdrant account`) به یک Credential واحد
- [ ] دریافت توضیح از مالک درباره کاربرد فعلی/آتی `APITemplate.io account`
- [ ] تأیید این‌که آیا `OpenAI account` واقعاً استفاده می‌شود (مثلاً توسط خود Open Notebook) یا باید حذف شود
- [ ] افزودن Auth حداقلی (حتی Token ساده) روی Qdrant/TEI پیش از هرگونه دسترسی از خارج از شبکه داخلی Docker
- [ ] تعیین تاریخ شروع چرخه Rotation برای هر Secret و ثبت آن
- [ ] تأیید محل دقیق نگهداری توکن GitHub برای Backup/CI

---

## ۱۰. ارجاعات

- [[META-INT-080 — معماری کلان سیستم‌عامل هوشمند سازمانی Xennic|META-INT-080]]
- [[META-INT-050 — راه‌اندازی کامل Hermes|META-INT-050]]
- [[META-INT-033 — ادغام Hermes با MCP n8n-official|META-INT-033]]
- [[META-INT-070 — نقشه Open Notebook برای n8n و Hermes|META-INT-070]]
- [[META-INT-090 — رجیستری Workflowهای n8n|META-INT-090]]
- [[META-INT-120 — نظارت، هشدار و مدیریت خطا|META-INT-120]]
- [[L2-SEC-001 — امنیت اطلاعات|L2-SEC-001]]

---

## ۱۱. Changelog

- **v0.2.0 (۱۴۰۵-۰۷-۳۰):** تکمیل جدول Credentialها با داده واقعی استخراج‌شده از `docker exec xennic-n8n n8n export:credentials --all` (۹ مورد، بدون افشای مقدار رمزگذاری‌شده)؛ تصحیح فرض نادرست «Open Notebook بدون Auth است» (واقعاً `Header Auth account` دارد)؛ شناسایی تکرار دو Credential Qdrant؛ شناسایی Credential ناشناخته `APITemplate.io account`؛ ثبت یادآوری حیاتی درباره Rotation کلید Local REST API و گواهی‌های RSA/CA Obsidian که قبلاً به‌صورت متن ساده مشاهده شدند؛ تغییر وضعیت به `review`.
- **v0.1.0 (۱۴۰۵-۰۷-۳۰):** ایجاد اولیه در پی ممیزی کامل پوشه `00_Meta/Integration` — مستندسازی شکاف «عدم وجود سیاست مدیریت Secrets برای زیرساخت اتوماسیون».
