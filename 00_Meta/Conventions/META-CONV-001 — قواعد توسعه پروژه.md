
---
id: META-CONV-001
title: قواعد توسعه پروژه ZNNY-Xennic-Vault
layer: Meta
domain: Conventions
status: approved
owner: احمد فیروزمندی
created: 2026-10-01
version: 1.0.0
dependencies: []
tags: [meta, conventions, rules, governance]
---

# META-CONV-001 — قواعد توسعه پروژه

## هدف
این سند، مرجع رسمی تمام قواعد، روش‌ها، استانداردها و تصمیم‌های حاکم بر توسعه Vault شرکت زر نور نیرو یکتا (ZNNY-Xennic) است.
هر توسعه‌دهنده جدید، **قبل از شروع کار** باید این سند را مطالعه کند.

---
## قاعده ۱ — ساختار Git Flow و PR اجباری

### شاخه‌ها
| شاخه | هدف | قواعد |
|---|---|---|
| `main` | نسخه پایدار | فقط از `dev` از طریق PR |
| `dev` | شاخه توسعه اصلی | فقط از `feature/*` از طریق PR |
| `feature/<NODE-ID>-<slug>` | یک نود یا قابلیت | فقط یک نود در هر شاخه |

### قواعد PR (اجباری)
- **هیچ کامیتی مستقیم روی `main` مجاز نیست**
- **هیچ کامیتی مستقیم روی `dev` مجاز نیست**
- **همه تغییرات باید از طریق Pull Request (PR) ادغام شوند**
- حتی برای اصلاح یک غلط املایی، PR الزامی است
- برای پروژه‌های کوچک (تنها توسعه‌دهنده)، می‌توانید PR بسازید و خودتان Merge کنید
- برای پروژه‌های تیمی، حداقل یک بازبین (Reviewer) الزامی است

### چرخه کار استاندارد (اجباری)
git checkout dev

git pull origin dev

git checkout -b feature/FND-XXX-slug

[کار روی نود]

git add .

git commit -m "founder(FND-XXX): description"

git push -u origin feature/FND-XXX-slug

رفتن به GitHub → Create Pull Request

base: dev ← compare: feature/FND-XXX-slug

بازبینی و تایید

Merge PR در GitHub

حذف شاخه feature (از GitHub یا محلی)

git checkout dev

git pull origin dev

text

### قواعد نام‌گذاری PR
عنوان PR: <type>(<NODE-ID>): <description>

مثال:
founder(FND-002): add distribution operations experience
docs(META-CONV-001): add mandatory PR rule

text

### قواعد توضیحات PR
هر PR باید شامل:
- **چه چیزی تغییر کرد** (What)
- **چرا** (Why)
- **ارجاعات** (به NODE-ID یا Issue مرتبط)
- **چک‌لیست بازبینی**

---

## قاعده ۲ — نام‌گذاری شاخه‌ها

### الگو
```
<type>/<NODE-ID>-<kebab-case-slug>

انواع:
feature/   → نود یا قابلیت جدید
fix/       → اصلاح
docs/      → مستندسازی
decision/  → ADR
```

### مثال‌ها
```
feature/FND-001-cv-professional
feature/FND-002-distribution-ops
feature/L1-LEG-001-registration
feature/L2-PLT-001-xennic-v1
fix/FND-003-typo-in-live-line
decision/ADR-001-company-type
```

---

## قاعده ۳ — Convention کامیت

### الگو
```
<type>(<NODE-ID>): <description>

انواع:
feat      → قابلیت جدید
docs      → مستندات
fix       → اصلاح
founder   → نودهای Founder
decision  → ADR
chore     → کارهای جانبی
refactor  → بازنویسی
```

### مثال‌ها
```
founder(FND-001): complete professional CV v0.1.0
founder(FND-002): add distribution operations experience
docs(L1-LEG-001): add registration checklist
decision(ADR-001): choose joint stock company
fix(FND-001): correct email address
chore(00_META): update node template
```

### قواعد
- پیام کامیت به انگلیسی
- NODE-ID دقیقاً مطابق ID نود
- توضیح کوتاه و گویا (حداکثر ۷۲ کاراکتر)

---

## قاعده ۴ — ساختار هر نود

### مسیر فایل
```
<layer_folder>/<NODE-ID> — <title>.md

نمونه:
01_Founder/FND-001 — رزومه حرفه‌ای مهندسی.md
02_PreLaunch/L1-LEG-001 — ثبت شرکت سهامی خاص.md
```

### Frontmatter اجباری
```yaml
---
id: <NODE-ID>
title: <عنوان>
layer: <Founder|PreLaunch|Launch|Future|Meta>
domain: <FND|LEG|FIN|BRD|MKT|TEC|PLT|AI|OPS|...>
status: <draft|review|approved|archived>
owner: <نام>
created: <YYYY-MM-DD>
version: <SemVer>
dependencies: [<NODE-ID>, ...]
tags: [tag1, tag2]
---
```

### بخش‌های اجباری
هر نود باید حداقل این بخش‌ها را داشته باشد:
1. هدف (Why)
2. محتوا (اصلی)
3. ارجاعات (References)
4. Changelog

---

## قاعده ۵ — کدگذاری نودها

### فرمت
```
<LAYER>-<DOMAIN>-<NNN>

LAYER: FND | L1 | L2 | L3 | META
DOMAIN: (سه حرف بزرگ)
NNN: شماره سه‌رقمی
```

### کدهای Domain
| کد | حوزه |
|---|---|
| FND | Founder |
| LEG | حقوقی |
| FIN | مالی |
| BRD | برند |
| MKT | بازاریابی |
| TEC | فنی و مهندسی |
| PLT | پلتفرم |
| AI | هوش مصنوعی |
| OPS | عملیات |
| RND | تحقیق و توسعه |
| INT | بین‌المللی |
| CONV | قواعد (Meta) |

### مثال‌ها
```
FND-001  → رزومه بنیان‌گذار
FND-002  → تجربه بهره‌برداری
L1-LEG-001 → ثبت شرکت
L1-BRD-001 → هویت برند
L2-PLT-001 → Xennic v1
META-CONV-001 → همین سند
```

---

## قاعده ۶ — لایه‌بندی پروژه

| لایه | معنی | مثال |
|---|---|---|
| Meta | قواعد و استانداردها | META-CONV-001 |
| Founder | دارایی‌های بنیان‌گذار | FND-001 تا FND-011 |
| PreLaunch | قبل از راه‌اندازی | L1-* |
| Launch | ۰ تا ۱۸ ماه | L2-* |
| Future | ۱۸ ماه به بعد | L3-* |

### قواعد
- هیچ محتوایی بین لایه‌ها تکرار نمی‌شود
- هر نود فقط یک والد دارد
- اتصال از طریق `[[link]]`

---

## قاعده ۷ — مستندسازی در Obsidian

### اصول
- همه نودها در Obsidian نوشته می‌شوند
- فایل‌های Markdown با UTF-8 بدون BOM
- استفاده از `[[wiki-link]]` برای اتصال
- استفاده از frontmatter برای متادیتا
- هر نود در پوشه لایه خود

### ابزار
| ابزار | کاربرد |
|---|---|
| Obsidian | نوشتن، دیدن Graph، لینک‌ها |
| VS Code | ویرایش حرفه‌ای، جستجو |
| ترمینال VS Code | Git |

---

## قاعده ۸ — روش ساخت هر نود (مصاحبه ساختاریافته)

### فرآیند
```
1. تعیین NODE-ID و نام شاخه
2. ساخت شاخه feature/FND-XXX-slug
3. مصاحبه ساختاریافته:
   - بخش‌بندی محتوا (۱۰-۱۲ بخش)
   - پرسش سوالات دقیق
   - پاسخ کاربر
   - تایید کاربر
4. نوشتن نود در Obsidian
5. بازبینی نهایی
6. git add + commit + push
7. Merge به dev
8. حذف شاخه feature
```

### قواعد مصاحبه
- هر بخش جدا پرسیده می‌شود
- پاسخ‌ها تایید نهایی می‌شوند
- از دوباره‌کاری جلوگیری می‌شود
- خروجی یک نود کامل و بدون نقص است

---

## قاعده ۹ — جلوگیری از دوباره‌کاری

### قبل از ساخت هر نود جدید
1. در Obsidian جستجو: `tag:#<موضوع>`
2. در VS Code جستجو: `Ctrl+Shift+F`
3. بررسی `06_Decisions/` برای ADRهای مرتبط
4. بررسی `dependencies` نودهای مشابه

### قواعد
- هر تصمیم استراتژیک → یک ADR در `06_Decisions/`
- هر نود یک بار نوشته می‌شود
- به‌روزرسانی از طریق version bump انجام می‌شود

---

## قاعده ۱۰ — قالب‌های آماده

### محل قالب‌ها
```
00_Meta/Templates/
├── node-template.md
├── decision-record.md  (آینده)
└── meeting-note.md     (آینده)
```

### قالب نود
در فایل `00_Meta/Templates/node-template.md` موجود است.

---

## قاعده ۱۱ — وضعیت‌ها (Status)

| وضعیت | معنی |
|---|---|
| `draft` | پیش‌نویس، در حال کار |
| `review` | آماده بازبینی |
| `approved` | تایید نهایی |
| `archived` | بایگانی‌شده |

### قاعده
- هیچ نودی مستقیماً `approved` نمی‌شود
- چرخه: draft → review → approved → archived

---

## قاعده ۱۲ — زبان و نگارش

### قواعد
- **نام نودها**: فارسی
- **محتوای نودها**: فارسی
- **پیام‌های کامیت**: انگلیسی
- **NODE-ID**: انگلیسی
- **نام شاخه**: انگلیسی
- **Frontmatter keys**: انگلیسی
- **اعداد در متن**: می‌توان فارسی یا لاتین

### قواعد نگارش
- استفاده از نیم‌فاصله در کلمات فارسی
- اعداد در جدول: فارسی
- تاریخ‌ها: شمسی در متن، میلادی در frontmatter (`created`)

---

## قاعده ۱۳ — اتصال به GitHub

### مخزن
```
https://github.com/feerozmandi/ZNNY-Xennic-Vault
```

### شاخه‌های اصلی
```
main   → پایدار
dev    → توسعه
```

### احراز هویت
- حساب GitHub باید `feerozmandi` باشد (نه `feerozmandiha`)
- یا از Personal Access Token استفاده شود

---

## قاعده ۱۴ — فایل‌های حساس

### نباید در Git باشند
```
.obsidian/workspace*
.obsidian/cache
.trash/
*.tmp
.env
secrets/
private/
```

### محل تعریف
فایل `.gitignore` در ریشه پروژه.

---

## قاعده ۱۵ — به‌روزرسانی این سند

### قواعد
- هر قاعده جدید که در توسعه مطرح شود، به این سند اضافه می‌شود
- version bump می‌شود
- Changelog به‌روز می‌شود
- کامیت با `docs(META-CONV-001): ...`

---

## تصمیمات ثبت‌شده (ADR)

| شماره | تصمیم | تاریخ | وضعیت |
|---|---|---|---|
| ADR-000 | استفاده از Git Flow | 2026-10-01 | approved |
| ADR-001 | نام‌گذاری NODE-ID | 2026-10-01 | approved |
| ADR-002 | زبان‌های پروژه | 2026-10-01 | approved |
| ADR-003 | روش ساخت نود (مصاحبه) | 2026-10-01 | approved |

---

## Changelog
- v1.1.0 (2026-10-01): افزودن قاعده PR اجباری
- v1.0.0 (2026-10-01): ایجاد اولیه با ۱۵ قاعده و ۴ ADR
---

## ارجاعات
- [[META-TEMPLATE-001]] قالب نود
- [[FND-001]] نمونه نود Founder
