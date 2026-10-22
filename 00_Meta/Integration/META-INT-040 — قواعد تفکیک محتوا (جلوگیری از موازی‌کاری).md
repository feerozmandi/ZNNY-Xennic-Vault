---
id: META-INT-040
title: قواعد تفکیک محتوا (جلوگیری از موازی‌کاری)
status: approved
created: 2026-10-17
tags: [integration, rules, content, separation]
layer: Meta
domain: INT
owner: احمد فیروزمندی بندپی
version: 1.1.0
dependencies: []
---

# قواعد تفکیک محتوا

> [!abstract] هدف
> هر محتوا فقط در یک منبع ذخیره می‌شود — نودهای سازمانی و تصمیمات در Obsidian، اسناد و منابع بیرونی در Open Notebook — بدون تکرار یا دوباره‌کاری.

## فهرست

| # | بخش |
|---|---|
| ۱ | اصل کلی |
| ۲ | Metadata مشترک |
| ۳ | لینک‌دهی بین منابع |
| ۴ | قواعد تکرار |
| ۵ | Qdrant Collection |
| ۶ | ارجاعات |
| ۷ | Changelog |

---

## اصل کلی

**هر محتوا فقط در یک منبع** ذخیره می‌شود:

| نوع محتوا | منبع |
|---|---|
| نودهای سازمانی (FND-*, L2-*) | Obsidian |
| تصمیمات (06_Decisions) | Obsidian |
| جلسات (07_Meetings) | Obsidian |
| متادیتا (00_Meta) | Obsidian |
| PDF، کتاب، استاندارد | Open Notebook |
| قوانین، مقررات | Open Notebook |
| مقالات و اسناد | Open Notebook |


---

## Metadata مشترک

### Obsidian frontmatter
```yaml
---
id: FND-003
source: obsidian
type: node
layer: Founder
domain: FND
tags: [founder, experience, live-line]
version: 0.1.0
created: 2026-10-02
---

```

### Open Notebook payload

{
  "source": "open_notebook",
  "source_id": "source:...",
  "notebook_id": "notebook:...",
  "type": "document",
  "tags": ["standards", "pdf"],
  "language": "fa",
  "created_at": "..."
}


---

## لینک‌دهی بین منابع

برای این‌که بتوان محتوای مرتبط در دو منبع را دنبال کرد، باید یک **ارجاع متقابل صریح** ثبت شود — نه کپی محتوا.

### Obsidian → Open Notebook

اگر نودی در Obsidian به یک سند Open Notebook اشاره دارد، در بخش «ارجاعات» همان نود یک سطر اضافه می‌شود:

> منبع مرتبط: OpenNotebook:source:1i9j5enf9dv2q2p7vczm — خط گرم (PDF)

**نمونه واقعی:** نود FND-003 (رزومه خط گرم) به سند «خط گرم» در Open Notebook ارجاع می‌دهد.

### Open Notebook → Obsidian

اگر سندی در Open Notebook به یک نود Obsidian اشاره دارد، در بخش Notes همان سند یک سطر اضافه می‌شود:

> منبع مرتبط: FND-003 (Obsidian)

---

## قواعد تکرار

❌ **ممنوع:**

- کپی محتوای PDF در نود Obsidian
    
- کپی نود Obsidian در Open Notebook
    
- تکرار تصمیمات در Open Notebook
    

✅ **مجاز:**

- ارجاع متقابل با لینک
    
- خلاصه در یک منبع + لینک به منبع اصلی
    
- Metadata یکسان برای ردیابی


---

## Qdrant Collection

**نام:** `xennic_shared_knowledge`

**Payload:**

{
  "source": "obsidian" | "open_notebook",
  "node_id": "FND-003" | null,
  "source_id": "source:..." | null,
  "title": "...",
  "content": "...",
  "chunk_index": 0,
  "total_chunks": 1,
  "language": "fa",
  "qdrant_id_original": "...",
  "created_at": "..."
}

---

## ارجاعات
### لینک‌های مرتبط

- [[META-INT-020 — RAG مشترک Obsidian + Open Notebook → Qdrant|META-INT-020]] — RAG مشترک
    
- [[3.1-semantic-search-api]] — API جستجو

---

## Changelog

- **v1.1.0 (۱۴۰۵-۰۷-۳۰):** تصحیح `status` به مقدار معتبر `approved` (قبلاً `done`)؛ حذف فیلد غیراستاندارد `type`؛ بازسازی بخش ناقص «لینک‌دهی بین منابع» (مثال‌های FND-003 و منبع Open Notebook که به‌اشتباه در بخش ارجاعات افتاده بودند، به جای درست خود منتقل شدند).
- **v1.0.1 (۱۴۰۵-۰۷-۲۷):** به‌روزرسانی شناسه، لینک‌ها و مالک
- **v1.0.0 (۰۷۸۴-۰۵-۰۳):** ایجاد اولیه
