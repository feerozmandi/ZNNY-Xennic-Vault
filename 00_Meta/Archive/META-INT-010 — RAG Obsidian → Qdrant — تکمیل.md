---
id: META-INT-010
title: RAG Obsidian → Qdrant — تکمیل
status: archived
created: 2026-10-12
tags: [integration, rag, qdrant, obsidian, superseded]
layer: Meta
domain: INT
owner: احمد فیروزمندی بندپی
version: 1.1.0
dependencies: []
---

# RAG Obsidian → Qdrant — تکمیل

> [!danger] منسوخ‌شده — جایگزین شده با META-INT-020
> این نود پایپ‌لاین **اولیهٔ** RAG را مستند می‌کند که از مدل Embedding `text-embedding-3-small` (gapgpt.app، ۱۵۳۶ بُعد) استفاده می‌کرد. این پایپ‌لاین به‌طور کامل با معماری جدید در [[META-INT-020 — RAG مشترک Obsidian + Open Notebook → Qdrant|META-INT-020]] (مدل `E5-large`، ۱۰۲۴ بُعد) جایگزین شده است. Collection فعلی `xennic_shared_knowledge` اکنون با ابعاد ۱۰۲۴ ساخته می‌شود — اطلاعات این نود (ابعاد ۱۵۳۶ و مدل gapgpt) دیگر معتبر نیست و **نباید به‌عنوان مرجع فنی فعال استفاده شود**. این فایل صرفاً برای حفظ سابقهٔ تاریخی در بایگانی نگهداری می‌شود.

> [!abstract] هدف (در زمان ایجاد)
> ذخیره‌سازی نودهای Obsidian در Qdrant برای جستجوی معنایی مشترک.

## فهرست

| # | بخش |
|---|---|
| ۱ | هدف |
| ۲ | معماری نهایی (منسوخ) |
| ۳ | Collection (منسوخ) |
| ۴ | داده‌های ذخیره‌شده |
| ۵ | مدل Embedding (منسوخ) |
| ۶ | نتیجه تست |
| ۷ | ارجاعات |
| ۸ | Changelog |

---

## هدف
ذخیره‌سازی نودهای Obsidian در Qdrant برای جستجوی معنایی مشترک.


---

## معماری نهایی (منسوخ)

[Manual Trigger]
       ↓
[Execute Command]  ← خواندن فایل‌های Vault از /vault
       ↓
[Code: Parse & Chunk]  ← استخراج frontmatter + chunking + __payload
       ↓
[Loop Over Items: Batch Size 5]
       ↓
[HTTP Request: Embedding]  ← gapgpt.app / text-embedding-3-small
       ↓
[Code: Merge Vector + Payload]  ← UUID v4 + payload از __payload
       ↓
[HTTP Request: Qdrant Upsert]

> [!note] جایگزینی
> معماری فعلی و معتبر در [[META-INT-020 — RAG مشترک Obsidian + Open Notebook → Qdrant|META-INT-020]] مستند شده است (مدل E5-large به‌جای gapgpt).

---

## Collection (منسوخ)
- نام: `xennic_shared_knowledge`
- ابعاد: ۱۵۳۶ (در زمان ایجاد این نود — **اکنون ۱۰۲۴ است**, رجوع کنید به META-INT-020)
- Distance: Cosine
- Indexها: source, node_id, notebook_id, tags, language


---

## داده‌های ذخیره‌شده
- ۸ فایل Founder (FND-001 تا FND-008)
- ۱۹ chunk
- ۱۹ point در Qdrant


---

## مدل Embedding (منسوخ)
- Provider: gapgpt.app (OpenAI-compatible)
- Model: text-embedding-3-small
- ابعاد: 1536


---

## نتیجه تست

> [!warning] داده ثبت‌نشده
> امتیاز (Score) دقیق این دو جستجو هیچ‌وقت در این نود ثبت نشد. پیش از این‌که فرصت تکمیل آن باشد، پایپ‌لاین با مدل E5-large جایگزین شد (نتایج تست معتبر و ثبت‌شده را در [[META-INT-020 — RAG مشترک Obsidian + Open Notebook → Qdrant|META-INT-020]] ببینید: Score ۰.۷۷ برای هر دو query).

- جستجوی "خط گرم" → Score: ثبت‌نشده
- جستجوی "دیسپاچینگ" → Score: ثبت‌نشده

---

## ارجاعات
### لینک‌های مرتبط
- [[META-INT-009]] — Qdrant Collection Creation
- [[1.1-rag-open-notebook-qdrant]]
- [[META-INT-020 — RAG مشترک Obsidian + Open Notebook → Qdrant|META-INT-020]] — نسخه جایگزین و فعال

---

## Changelog

- **v1.1.0 (۱۴۰۵-۰۷-۳۰):** بایگانی‌شدن نود؛ تغییر وضعیت به `archived`، انتقال فایل به `00_Meta/Archive/`، افزودن یادداشت صریح جایگزینی با META-INT-020، و شفاف‌سازی داده‌های تست ثبت‌نشده. حذف فیلد غیراستاندارد `type`.
- **v1.0.1 (۱۴۰۵-۰۷-۲۷):** به‌روزرسانی شناسه، لینک‌ها و مالک
- **v1.0.0 (۰۷۸۴-۰۴-۲۹):** ایجاد اولیه
