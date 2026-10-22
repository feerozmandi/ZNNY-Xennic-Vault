---
id: META-INT-010
title: RAG Obsidian → Qdrant — تکمیل
type: integration
status: done
created: 2026-10-12
tags: [integration, rag, qdrant, obsidian]
layer: Meta
domain: INT
owner: احمد فیروزمندی بندپی
version: 1.0.1
dependencies: []
---

# RAG Obsidian → Qdrant — تکمیل

> [!abstract] هدف
> ذخیره‌سازی نودهای Obsidian در Qdrant برای جستجوی معنایی مشترک.

## فهرست

| # | بخش |
|---|---|
| ۱ | هدف |
| ۲ | معماری نهایی |
| ۳ | Collection |
| ۴ | داده‌های ذخیره‌شده |
| ۵ | مدل Embedding |
| ۶ | نتیجه تست |
| ۷ | ارجاعات |
| ۸ | Changelog |

---

## هدف
ذخیره‌سازی نودهای Obsidian در Qdrant برای جستجوی معنایی مشترک.


---

## معماری نهایی

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


---

## Collection
- نام: `xennic_shared_knowledge`
- ابعاد: 1536
- Distance: Cosine
- Indexها: source, node_id, notebook_id, tags, language


---

## داده‌های ذخیره‌شده
- ۸ فایل Founder (FND-001 تا FND-008)
- ۱۹ chunk
- ۱۹ point در Qdrant


---

## مدل Embedding
- Provider: gapgpt.app (OpenAI-compatible)
- Model: text-embedding-3-small
- ابعاد: 1536


---

## نتیجه تست
- جستجوی "خط گرم" → Score: [مقدار]
- جستجوی "دیسپاچینگ" → Score: [مقدار]

---

## ارجاعات
### لینک‌های مرتبط
- [[META-INT-009]] — Qdrant Collection Creation
- [[1.1-rag-open-notebook-qdrant]]

---

## Changelog

- **v1.0.1 (۱۴۰۵-۰۷-۲۷):** به‌روزرسانی شناسه، لینک‌ها و مالک
- **v1.0.0 (۰۷۸۴-۰۴-۲۹):** ایجاد اولیه
