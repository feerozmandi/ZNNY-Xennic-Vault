---
id: L2-PLT-001
title: Xennic v1
layer: Launch
domain: PLT
status: draft
owner: احمد فیروزمندی بندپی
created: 2026-10-09
version: 0.1.0
dependencies: [L1-STR-001, L1-BRD-001, L1-BRD-002, L1-FIN-001, L1-MKT-001, L1-MKT-002, FND-008]
tags: [platform, xennic, launch, core-asset]
---

# L2-PLT-001 — Xennic v1 (پلتفرم)

## ۱. هدف (Why)
سند مرجع توسعه پلتفرم Xennic v1. این نود:
- راهنمای توسعه‌دهندگان فعلی و آینده
- تعریف معماری، ابزارها، استانداردها
- تعیین نقشه راه توسعه
- مرجع رسمی محصول Xennic

**رابطه با نودهای دیگر**:
- L1-STR-001: بیانیه ماموریت
- L1-BRD-001: هویت برند
- L1-BRD-002: راهنمای برند
- L1-FIN-001: مدل مالی
- L1-MKT-001: تحلیل بازار
- L1-MKT-002: تحلیل رقبا

## ۲. چشم‌انداز محصول

### ۲.۱. تعریف Xennic v1

> **Xennic v1** یک پلتفرم جامع مهندسی برق است که با تلفیق **هوش مصنوعی**، **بینایی ماشین**، **محاسبات مهندسی**، **کتابخانه استانداردها** و **مدیریت پروژه**، تمامی نیازهای مهندسان، صنایع و دانشجویان را در یک بستر یکپارچه پوشش می‌دهد.

**Xennic v1 شامل ۶ ماژول اصلی**:

| # | ماژول | توضیح |
|---|---|---|
| ۱ | Chat | پرسش و پاسخ مهندسی با AI |
| ۲ | Documents | کتابخانه استانداردها و منابع |
| ۳ | Calculator | محاسبات مهندسی با استانداردها |
| ۴ | Vision | بینایی ماشین (Nameplate + قبض + PDF + بارکد) |
| ۵ | Reports | تولید گزارش‌های تخصصی |
| ۶ | Projects | مدیریت پروژه‌ها |

### ۲.۲. چشم‌انداز ۵ ساله

| سال | Xennic |
|---|---|
| ۱۴۰۵ | Xennic v1 (MVP) — ۶ ماژول اصلی |
| ۱۴۰۶ | Xennic v2 — افزودن فروشگاه (shop.xennic.ir) |
| ۱۴۰۷ | Xennic v3 — اکوسیستم کامل (بازار، آموزش، انجمن) |
| ۱۴۰۸ | Xennic v4 — منطقه‌ای (چندزبانه) |
| ۱۴۰۹ | Xennic v5 — بین‌المللی (AI Agentها) |

### ۲.۳. مزیت رقابتی

| # | مزیت | توضیح |
|---|---|---|
| ۱ | AI یکپارچه | در همه ماژول‌ها |
| ۲ | بینایی ماشین | خواندن Nameplate، قبض، PDF، بارکد |
| ۳ | استانداردها | داخلی و بین‌المللی |
| ۴ | محاسبات | با لینک به منابع |
| ۵ | فروشگاه یکپارچه | shop.xennic.ir |
| ۶ | فارسی و بومی | برای ایران |
| ۷ | ماژولار | توسعه مستقل |

### ۲.۴. مخاطبان

| # | مخاطب | نیاز |
|---|---|---|
| ۱ | مهندسان برق | ابزار، محاسبات، دانش |
| ۲ | دانشجویان | آموزش، تمرین |
| ۳ | صنایع | تجهیزات، مشاوره |
| ۴ | پیمانکاران | طراحی، نظارت |
| ۵ | مشاوران | ابزار محاسبات |
| ۶ | فروشندگان تجهیزات | بازار |
| ۷ | سازمان‌های دولتی | پروژه‌ها |

## ۳. معماری فنی

### ۳.۱. معماری کلان (میکروسرویس + ماژولار)

┌─────────────────────────────────────────────────────────┐
│ Frontend (Next.js) │
│ ┌─────────┬─────────┬─────────┬─────────┬─────────┐ │
│ │ Chat │ Docs │ Calc │ Vision │ Reports │ │
│ └─────────┴─────────┴─────────┴─────────┴─────────┘ │
└─────────────────────────────────────────────────────────┘
│
│ REST API / GraphQL
▼
┌─────────────────────────────────────────────────────────┐
│ API Gateway (FastAPI) │
│ ┌─────────┬─────────┬─────────┬─────────┬─────────┐ │
│ │ Auth │ Rate │ Logs │ Cache │ Docs │ │
│ │ │ Limit │ │ │ │ │
│ └─────────┴─────────┴─────────┴─────────┴─────────┘ │
└─────────────────────────────────────────────────────────┘
│
┌─────────────────┼─────────────────┐
│ │ │
▼ ▼ ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ AI Service │ │ Engineering │ │ Vision │
│ (Python) │ │ Service │ │ Service │
│ │ │ (Python) │ │ (Python) │
└──────────────┘ └──────────────┘ └──────────────┘
│ │ │
└─────────────────┼─────────────────┘
│
┌─────────────────┼─────────────────┐
│ │ │
▼ ▼ ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ PostgreSQL │ │ Qdrant │ │ MinIO │
│ (Main DB) │ │ (Vector DB) │ │ (Storage) │
└──────────────┘ └──────────────┘ └──────────────┘
│ │ │
└─────────────────┼─────────────────┘
│
┌─────────────────┼─────────────────┐
│ │ │
▼ ▼ ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ Redis │ │ RabbitMQ │ │ OpenAI/Claude│
│ (Cache) │ │ (Queue) │ │ (AI) │
└──────────────┘ └──────────────┘ └──────────────┘


### ۳.۲. Frontend Stack

| مورد | تکنولوژی | نسخه |
|---|---|---|
| Framework | Next.js | 15+ |
| UI Library | React | 19+ |
| Language | TypeScript | 5.5+ |
| Styling | Tailwind CSS | 4+ |
| UI Components | shadcn/ui | latest |
| State Management | Zustand | latest |
| Data Fetching | TanStack Query | v5 |
| Forms | React Hook Form | latest |
| Validation | Zod | latest |
| Icons | Lucide React | latest |
| Charts | Recharts | latest |
| PDF Viewer | react-pdf | latest |
| Rich Text | TipTap | latest |
| i18n | next-intl | latest |
| Testing | Vitest + Playwright | latest |

**اصل**: استفاده از کدهای **سبک، دقیق و سریع**.

### ۳.۳. Backend Stack

| مورد | تکنولوژی | نسخه |
|---|---|---|
| Framework | FastAPI | 0.115+ |
| Language | Python | 3.12+ |
| ASGI | Uvicorn | latest |
| ORM | SQLAlchemy | 2.0+ |
| Migration | Alembic | latest |
| Validation | Pydantic | v2 |
| Auth | JWT + OAuth2 | — |
| Task Queue | Celery + RabbitMQ | latest |
| HTTP Client | httpx | latest |
| Testing | pytest | latest |
| Linting | Ruff | latest |
| Type Checking | mypy | latest |
| API Docs | Swagger + ReDoc | — |

### ۳.۴. Database Stack

| نوع | تکنولوژی | کاربرد |
|---|---|---|
| Main DB | PostgreSQL 17 | داده‌های ساخت‌یافته |
| Vector DB | Qdrant | RAG، جستجوی معنایی |
| Cache | Redis 8 | Cache، Session |
| Queue | RabbitMQ 4 | پیام‌رسانی |
| Storage | MinIO | فایل (S3) |
| Search | Meilisearch | جستجوی متن |

### ۳.۵. AI Stack

| نوع | تکنولوژی | کاربرد |
|---|---|---|
| LLM | OpenAI GPT-4 / Claude 3.5 | Chat، تولید محتوا |
| Vision AI | GPT-4 Vision / Claude Vision | Vision |
| Embedding | text-embedding-3-small | RAG |
| Framework | LangChain یا LlamaIndex | Orchestration |
| Vector Store | Qdrant | RAG |
| Agent | LangGraph | AI Agentها |
| OCR | Tesseract + PaddleOCR | Vision |
| Speech | Whisper | صوت (آینده) |
| Local LLM | Ollama (اختیاری) | جایگزین |

### ۳.۶. Deployment Stack

| مورد | تکنولوژی |
|---|---|
| Container | Docker |
| Orchestration | Docker Compose |
| Reverse Proxy | Nginx / Caddy |
| CI/CD | GitHub Actions |
| Monitoring | Grafana + Prometheus |
| Logging | Loki |
| Tracing | Jaeger |
| Error Tracking | Sentry |
| CDN | Cloudflare |
| Hosting | ابر آروان یا Liara |

## ۴. ماژول‌های Xennic v1

### ۴.۱. ماژول Chat

| # | قابلیت | توضیح |
|---|---|---|
| ۱ | Chat با AI | پرسش و پاسخ مهندسی |
| ۲ | Chat با اسناد | RAG |
| ۳ | Chat با استانداردها | IEC, IEEE, ISO |
| ۴ | Chat با مقررات | قوانین ایران |
| ۵ | Chat صوتی | Whisper (آینده) |
| ۶ | تاریخچه Chat | ذخیره و بازیابی |
| ۷ | Export Chat | PDF, Markdown |
| ۸ | Share Chat | اشتراک‌گذاری |
| ۹ | Citation | ارجاع به منبع |
| ۱۰ | Multi-Language | فارسی، انگلیسی |

### ۴.۲. ماژول Documents

| # | قابلیت | توضیح |
|---|---|---|
| ۱ | کتابخانه استانداردها | IEC, IEEE, ISO, مبحث ۱۳ |
| ۲ | کتابخانه مقررات | قوانین ایران |
| ۳ | کتابخانه مقالات | مقالات علمی |
| ۴ | کتابخانه کتاب‌ها | کتاب‌های مرجع |
| ۵ | آپلود اسناد | PDF, Word, Excel |
| ۶ | جستجوی معنایی | با Qdrant |
| ۷ | OCR | برای PDF اسکن‌شده |
| ۸ | خلاصه‌سازی | با AI |
| ۹ | ترجمه | فارسی ↔ انگلیسی |
| ۱۰ | Citation | استناد خودکار |
| ۱۱ | همگام‌سازی با Open Notebook | یکپارچه‌سازی |
| ۱۲ | همگام‌سازی با Obsidian | یکپارچه‌سازی |

### ۴.۳. ماژول Calculator

| # | قابلیت | توضیح |
|---|---|---|
| ۱ | محاسبات ساده | افت ولتاژ، جریان، توان |
| ۲ | محاسبات پیچیده | اتصال کوتاه، پخش بار، پایداری |
| ۳ | تجزیه و تحلیل فرمول‌ها | نمایش مرحله‌به‌مرحله |
| ۴ | استناد به استاندارد | لینک به IEC, IEEE |
| ۵ | پیشنهاد تجهیزات | بر اساس محاسبه |
| ۶ | لینک به فروشگاه | shop.xennic.ir |
| ۷ | ذخیره محاسبات | تاریخچه |
| ۸ | Export محاسبات | PDF, Excel |
| ۹ | مقایسه محاسبات | تحلیل تفاوت‌ها |
| ۱۰ | Visualization | نمودار، دیاگرام |
| ۱۱ | محاسبات خورشیدی | PVsyst-like |
| ۱۲ | محاسبات BESS | ذخیره‌سازی |

### ۴.۴. ماژول Vision

| # | قابلیت | توضیح |
|---|---|---|
| ۱ | خواندن Nameplate | از تصویر |
| ۲ | خواندن قبض برق | از تصویر |
| ۳ | خواندن PDF | Nameplate، قبض، کاتالوگ |
| ۴ | خواندن بارکد | QR، Barcode، DataMatrix |
| ۵ | خواندن RFID/NFC | (آینده) |
| ۶ | استخراج اطلاعات | کلید-مقدار |
| ۷ | تحلیل با استانداردها | مقایسه با IEC |
| ۸ | تحلیل قبض | مصرف، هزینه، بهینه‌سازی |
| ۹ | پیشنهاد بهینه‌سازی | بر اساس داده‌ها |
| ۱۰ | ارائه گزارش | خودکار |
| ۱۱ | Batch Processing | چند فایل همزمان |
| ۱۲ | API | یکپارچه‌سازی |

### ۴.۵. ماژول Reports

| # | قابلیت | توضیح |
|---|---|---|
| ۱ | قالب‌های گزارش | پروپوزال، گزارش فنی، صورت‌جلسه |
| ۲ | تولید خودکار | با AI |
| ۳ | شخصی‌سازی | برای هر مشتری |
| ۴ | Export | PDF, Word, Excel |
| ۵ | امضای دیجیتال | (آینده) |
| ۶ | آرشیو | ذخیره گزارش‌ها |
| ۷ | Share | اشتراک‌گذاری |
| ۸ | Template Builder | ساخت قالب |
| ۹ | Multi-Language | فارسی، انگلیسی |
| ۱۰ | Branding | با هویت Xennic |

### ۴.۶. ماژول Projects

| # | قابلیت | توضیح |
|---|---|---|
| ۱ | مدیریت پروژه | ایجاد، ویرایش |
| ۲ | مدیریت وظایف | Kanban، Gantt |
| ۳ | مدیریت تیم | نقش‌ها، دسترسی |
| ۴ | مدیریت زمان | تقویم، ددلاین |
| ۵ | مدیریت اسناد | فایل‌های پروژه |
| ۶ | مدیریت مالی | بودجه، هزینه |
| ۷ | گزارش‌گیری | پیشرفت، عملکرد |
| ۸ | همگام‌سازی با n8n | اتوماسیون |
| ۹ | همگام‌سازی با Git | نسخه‌بندی |
| ۱۰ | API | یکپارچه‌سازی |

## ۵. تجربه کاربری (UX/UI)

### ۵.۱. اصول طراحی

| # | اصل | توضیح |
|---|---|---|
| ۱ | سادگی | طراحی مینیمال، تمیز |
| ۲ | کارایی | دسترسی سریع به امکانات |
| ۳ | یکپارچگی | تجربه یکسان در همه ماژول‌ها |
| ۴ | پاسخ‌گو | موبایل، تبلت، دسکتاپ |
| ۵ | دسترس‌پذیری | WCAG 2.1 AA |
| ۶ | RTL | پشتیبانی کامل فارسی |
| ۷ | Dark Mode | حالت شب |
| ۸ | برند | هویت Xennic |

### ۵.۲. ساختار صفحات

Home (داشبورد)
├── Chat (گفتگو)
├── Documents (اسناد)
│ ├── Standards (استانداردها)
│ ├── Regulations (مقررات)
│ ├── Papers (مقالات)
│ └── Books (کتاب‌ها)
├── Calculator (محاسبات)
│ ├── Basic (ساده)
│ ├── Advanced (پیشرفته)
│ └── Solar (خورشیدی)
├── Vision (بینایی ماشین)
│ ├── Nameplate
│ ├── Bill (قبض)
│ └── Barcode
├── Reports (گزارش‌ها)
├── Projects (پروژه‌ها)
├── Profile (پروفایل)
└── Settings (تنظیمات)


### ۵.۳. کامپوننت‌های کلیدی

| # | کامپوننت | کاربرد |
|---|---|---|
| ۱ | Header | ناوبری، جستجو، پروفایل |
| ۲ | Sidebar | منوی اصلی |
| ۳ | Search Bar | جستجوی جهانی |
| ۴ | Chat Interface | گفتگو با AI |
| ۵ | Document Viewer | نمایش اسناد |
| ۶ | Calculator Widget | محاسبات |
| ۷ | Image Uploader | آپلود تصویر/PDF |
| ۸ | Report Builder | ساخت گزارش |
| ۹ | Kanban Board | مدیریت وظایف |
| ۱۰ | Dashboard | داشبورد |
| ۱۱ | Notification | اعلان‌ها |
| ۱۲ | Modal | پنجره‌های بازشو |

### ۵.۴. هویت بصری

| مورد | مقدار |
|---|---|
| رنگ اصلی | سرمه‌ای #0D1B2A |
| رنگ تأکیدی | زرد #F5B400 |
| رنگ فناوری | سبز #0A6F6F |
| پس‌زمینه | سفید یا سرمه‌ای روشن |
| فونت فارسی | IRANSans |
| فونت انگلیسی | Inter |
| آیکون‌ها | Lucide |
| طراحی | مدرن، تمیز، حرفه‌ای |

### ۵.۵. SEO

| # | اقدام | ابزار |
|---|---|---|
| ۱ | SSR/SSG | Next.js |
| ۲ | Meta Tags | next-seo |
| ۳ | Sitemap | next-sitemap |
| ۴ | Robots.txt | خودکار |
| ۵ | Schema.org | JSON-LD |
| ۶ | Open Graph | شبکه‌های اجتماعی |
| ۷ | Performance | Lighthouse 90+ |
| ۸ | Mobile-First | طراحی موبایل |
| ۹ | Core Web Vitals | Google |
| ۱۰ | Content Strategy | محتوای تخصصی |

### ۵.۶. چندزبانه

| زبان | وضعیت | اولویت |
|---|---|---|
| فارسی | ✅ اصلی | 🔴 بالا |
| انگلیسی | ✅ | 🔴 بالا |
| عربی | ⏳ | 🟡 متوسط |
| ترکی | ⏳ | 🟡 متوسط |
| چینی | ⏳ | 🟢 پایین |

**تکنولوژی**: `next-intl` + فایل‌های JSON

## ۶. مدل درآمدی

### ۶.۱. پلن‌های اشتراک

| پلن | قیمت | کاربران هدف | امکانات |
|---|---|---|---|
| Free | رایگان | دانشجویان، کاربران جدید | Chat محدود، ۵ سند، محاسبات ساده |
| Pro | ۵۰۰ هزار تومان/ماه | مهندسان، مشاوران | Chat نامحدود، ۱۰۰ سند، همه محاسبات |
| Team | ۲ میلیون تومان/ماه | تیم‌ها (۵ نفر) | همه Pro + اشتراک‌گذاری |
| Enterprise | ۵ میلیون تومان/ماه | سازمان‌ها | همه Team + API + پشتیبانی |
| Student | ۱۰۰ هزار تومان/ماه | دانشجویان | نسخه تخفیف‌دار Pro |

### ۶.۲. درآمد اضافی

| # | منبع | مدل |
|---|---|---|
| ۱ | اشتراک | ماهانه/سالانه |
| ۲ | API | پرداخت به ازای مصرف |
| ۳ | فروش تجهیزات | کمیسیون (shop.xennic.ir) |
| ۴ | آموزش | دوره‌های پولی |
| ۵ | تبلیغات | برای کاربران Free |
| ۶ | گزارش‌های تخصصی | فروش |
| ۷ | خدمات مشاوره | از طریق پلتفرم |
| ۸ | Lifetime Deal | (LTD) |

### ۶.۳. پیش‌بینی درآمد

| سال | کاربران فعال | کاربران پولی | درآمد سالانه |
|---|---|---|---|
| ۱۴۰۵ | ۱,۰۰۰ | ۱۰۰ | ۵۰۰ میلیون |
| ۱۴۰۶ | ۵,۰۰۰ | ۵۰۰ | ۲.۵ میلیارد |
| ۱۴۰۷ | ۱۵,۰۰۰ | ۱,۵۰۰ | ۸ میلیارد |
| ۱۴۰۸ | ۳۰,۰۰۰ | ۳,۰۰۰ | ۱۵ میلیارد |
| ۱۴۰۹ | ۵۰,۰۰۰ | ۵,۰۰۰ | ۲۵ میلیارد |

### ۶.۴. استراتژی قیمت‌گذاری

| پلن | قیمت ماهانه | قیمت سالانه | تخفیف سالانه |
|---|---|---|---|
| Free | ۰ | ۰ | — |
| Student | ۱۰۰ هزار | ۱ میلیون | ۱۷٪ |
| Pro | ۵۰۰ هزار | ۵ میلیون | ۱۷٪ |
| Team | ۲ میلیون | ۲۰ میلیون | ۱۷٪ |
| Enterprise | ۵ میلیون | ۵۰ میلیون | ۱۷٪ |

### ۶.۵. مقایسه با رقبا

| پلتفرم | قیمت | قیمت Xennic |
|---|---|---|
| ETAP | ۵,۰۰۰-۵۰,۰۰۰ دلار | ۵۰۰ هزار تومان/ماه |
| DIgSILENT | ۱۰,۰۰۰-۱۰۰,۰۰۰ یورو | ۵۰۰ هزار تومان/ماه |
| MATLAB | ۲,۰۰۰ دلار/سال | ۵۰۰ هزار تومان/ماه |

**نتیجه**: Xennic **۱۰-۱۰۰ برابر ارزان‌تر**.

## ۷. زیرساخت

### ۷.۱. زیرساخت فنی

| سرویس | کاربرد | وضعیت |
|---|---|---|
| Docker | Container | ✅ |
| Nginx / Caddy | Reverse Proxy + SSL | ⏳ |
| PostgreSQL | Main DB | ✅ |
| Redis | Cache | ✅ |
| Qdrant | Vector DB | ✅ |
| MinIO | Object Storage | ✅ |
| RabbitMQ | Message Queue | ✅ |
| AI Service | AI Engine | ✅ |
| Engineering Service | محاسبات | ✅ |
| Vision Service | بینایی ماشین | ✅ |

**نکته**: ۹۵٪ زیرساخت آماده است.

### ۷.۲. محیط‌ها

| محیط | کاربرد | دامنه |
|---|---|---|
| Development | توسعه محلی | localhost |
| Staging | تست | staging.xennic.ir |
| Production | نهایی | app.xennic.ir |

### ۷.۳. مقیاس‌پذیری

| سطح | کاربران | معماری |
|---|---|---|
| MVP | ۰-۱,۰۰۰ | Single Server |
| Beta | ۱,۰۰۰-۱۰,۰۰۰ | Load Balanced |
| V1 | ۱۰,۰۰۰-۱۰۰,۰۰۰ | Microservices |
| V2 | ۱۰۰,۰۰۰+ | Multi-Region |

### ۷.۴. پشتیبان‌گیری

| نوع | فرکانس | محل | نگهداری |
|---|---|---|---|
| Database | روزانه | MinIO + Git | ۳۰ روز |
| Files | روزانه | MinIO | ۹۰ روز |
| Config | هر تغییر | Git | همیشه |
| Full Backup | هفتگی | Cloud | ۱ سال |

## ۸. امنیت

### ۸.۱. احراز هویت

| # | مکانیزم |
|---|---|
| ۱ | JWT |
| ۲ | Refresh Token |
| ۳ | OAuth 2.0 (Google, GitHub) |
| ۴ | 2FA |
| ۵ | Password Hashing (bcrypt/argon2) |
| ۶ | Session Management (Redis) |

### ۸.۲. امنیت داده

| # | مکانیزم |
|---|---|
| ۱ | HTTPS (SSL/TLS) |
| ۲ | Encryption at Rest (AES-256) |
| ۳ | Encryption in Transit (TLS 1.3) |
| ۴ | Data Anonymization |
| ۵ | Access Control (RBAC) |
| ۶ | Audit Logs |

### ۸.۳. امنیت API

| # | مکانیزم |
|---|---|
| ۱ | Rate Limiting |
| ۲ | API Key |
| ۳ | CORS |
| ۴ | Input Validation (Pydantic) |
| ۵ | SQL Injection Prevention (ORM) |
| ۶ | XSS Prevention (Sanitization) |
| ۷ | CSRF Protection (Token) |

### ۸.۴. امنیت AI

| # | مکانیزم |
|---|---|
| ۱ | Prompt Injection Prevention |
| ۲ | Output Filtering |
| ۳ | Rate Limiting AI |
| ۴ | Data Privacy |
| ۵ | Model Monitoring |
| ۶ | Fallback |

### ۸.۵. امنیت DevOps

| # | مکانیزم |
|---|---|
| ۱ | Secrets Management (HashiCorp Vault / .env) |
| ۲ | Dependency Scanning (Snyk / Dependabot) |
| ۳ | Container Scanning (Trivy) |
| ۴ | Penetration Testing |
| ۵ | Security Headers (CSP, HSTS) |
| ۶ | Monitoring (Grafana + Sentry) |

## ۹. مستندسازی

### ۹.۱. مستندسازی API

| ابزار | کاربرد |
|---|---|
| Swagger / OpenAPI 3.1 | مستندسازی REST API |
| ReDoc | نمایش جایگزین |
| FastAPI Docs | خودکار در FastAPI |
| Postman Collection | تست API |
| OpenAPI Generator | SDK خودکار |

### ۹.۲. مستندسازی کد

| نوع | ابزار |
|---|---|
| Docstrings | Python docstrings |
| Type Hints | TypeScript / Python |
| Comments | کامنت‌های هدفمند |
| README | Markdown |
| CONTRIBUTING | Markdown |
| CHANGELOG | Markdown |
| Architecture Docs | Markdown + Diagram |

### ۹.۳. مستندسازی کاربر

| نوع | محتوا | محل |
|---|---|---|
| راهنمای شروع | Getting Started | وب‌سایت |
| آموزش‌ها | Tutorials | وب‌سایت + YouTube |
| FAQ | سوالات متداول | وب‌سایت |
| Knowledge Base | پایگاه دانش | پلتفرم |
| API Docs | مستندات API | developers.xennic.ir |
| Video Tutorials | ویدیوها | YouTube |
| Community | انجمن | پلتفرم |

### ۹.۴. مستندسازی معماری

| نوع | ابزار |
|---|---|
| Diagram | Mermaid / draw.io |
| C4 Model | Structurizr |
| Sequence Diagram | Mermaid |
| ER Diagram | dbdiagram.io |
| Flowchart | Mermaid |

### ۹.۵. مستندسازی درون پلتفرم

| # | قابلیت |
|---|---|
| ۱ | Tooltip |
| ۲ | Onboarding |
| ۳ | Help Center |
| ۴ | Interactive Guides |
| ۵ | Video Tutorials |
| ۶ | FAQ |
| ۷ | Changelog |
| ۸ | Feedback |

## ۱۰. نقشه راه + ارجاعات

### ۱۰.۱. نقشه راه Xennic v1

| فاز | زمان | خروجی |
|---|---|---|
| فاز ۰ | مهر ۱۴۰۵ | زیرساخت + مستندسازی |
| فاز ۱ | آبان ۱۴۰۵ | MVP (Chat + Documents) |
| فاز ۲ | آذر ۱۴۰۵ | Calculator + Vision |
| فاز ۳ | دی ۱۴۰۵ | Reports + Projects |
| فاز ۴ | بهمن ۱۴۰۵ | Beta (تست عمومی) |
| فاز ۵ | اسفند ۱۴۰۵ | Xennic v1 (انتشار) |

### ۱۰.۲. تیم توسعه

| نقش | تعداد | وظیفه |
|---|---|---|
| Tech Lead | ۱ | هدایت فنی |
| Frontend Dev | ۱-۲ | Next.js، React |
| Backend Dev | ۱-۲ | FastAPI، Python |
| AI/ML Engineer | ۱ | AI، RAG |
| UI/UX Designer | ۱ | طراحی |
| DevOps | ۱ | Docker، Deployment |
| QA | ۱ | تست |
| Technical Writer | ۱ | مستندسازی |

**نکته**: در شروع، خودتان + کاظم کافی است.

### ۱۰.۳. ریسک‌های توسعه

| # | ریسک | احتمال | اثر | راه‌حل |
|---|---|---|---|---|
| ۱ | تاخیر در توسعه | متوسط | بالا | MVP کوچک |
| ۲ | کمبود نیرو | بالا | بالا | استخدام + AI |
| ۳ | پیچیدگی فنی | متوسط | متوسط | ماژولار |
| ۴ | بودجه محدود | بالا | متوسط | فازبندی |
| ۵ | رقابت سریع | متوسط | متوسط | تمایز AI |
| ۶ | امنیت | متوسط | بالا | تست امنیت |
| ۷ | مقیاس‌پذیری | کم | بالا | میکروسرویس |

### ۱۰.۴. ارجاعات

**ارجاعات داخلی**:
- [[L1-STR-001]] بیانیه ماموریت و چشم‌انداز
- [[L1-BRD-001]] هویت برند Xennic
- [[L1-BRD-002]] راهنمای برند Xennic
- [[L1-FIN-001]] مدل مالی پنج‌ساله
- [[L1-MKT-001]] تحلیل بازار برق ایران
- [[L1-MKT-002]] تحلیل رقبا
- [[FND-008]] ماتریس مهارت‌ها

**ارجاعات به اسناد**:
- [[کتابچه ۲۸ فصلی]] فصل ۲۰ (تحول دیجیتال)

**ارجاعات خارجی**:
- https://nextjs.org — Next.js
- https://fastapi.tiangolo.com — FastAPI
- https://qdrant.tech — Qdrant
- https://tailwindcss.com — Tailwind CSS
- https://ui.shadcn.com — shadcn/ui
- https://www.openapis.org — OpenAPI

**ارجاعات آینده**:
- [[L2-PLT-002]] Xennic v2 (فروشگاه)
- [[L2-AI-001]] دستیار مدیریت
- [[L2-TEC-001]] خدمات هدف
- [[L2-MKT-001]] استراتژی محتوا

## ۱۱. Changelog

- v0.1.0 (2026-10-09): ایجاد اولیه بر اساس مصاحبه ساختاریافته ۱۰ بخشی