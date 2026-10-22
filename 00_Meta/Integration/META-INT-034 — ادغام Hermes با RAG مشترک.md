---
id: META-INT-034
title: ادغام Hermes با RAG مشترک
status: approved
created: 2026-10-17
tags: [integration, hermes, rag, webhook, get]
layer: Meta
domain: INT
owner: احمد فیروزمندی بندپی
version: 1.1.0
dependencies: []
---

# ادغام Hermes با RAG مشترک

> [!abstract] هدف
> اتصال Hermes به RAG مشترک (Obsidian + Open Notebook) از طریق Webhook GET.

## فهرست

| # | بخش | # | بخش |
|---|---|---|---|
| ۱ | هدف | ۶ | چالش‌های حل‌شده |
| ۲ | معماری نهایی | ۷ | استفاده در Hermes |
| ۳ | Endpoint | ۸ | 🎯 گام ۴: جلوگیری از موازی‌کاری |
| ۴ | نتایج تست | ۹ | ارجاعات |
| ۵ | مزایای Webhook GET | ۱۰ | Changelog |

---

## هدف
اتصال Hermes به RAG مشترک (Obsidian + Open Notebook) از طریق Webhook GET.


---

## معماری نهایی

┌──────────────────────────────────────────┐
│ Hermes Agent │
│ ┌────────────────────────────────────┐ │
│ │ Terminal Tool → curl │ │
│ │ Web Search → URL │ │
│ └────────────────────────────────────┘ │
└──────────────────────────────────────────┘
↓ (Webhook GET)
┌──────────────────────────────────────────┐
│ n8n Workflow │
│ ┌────────────────────────────────────┐ │
│ │ [API-01] Semantic Search │ │
│ │ - Webhook GET │ │
│ │ - Code: Parse Query │ │
│ │ - HTTP: E5 Embedding │ │
│ │ - HTTP: Qdrant Search │ │
│ │ - Code: Format Results │ │
│ └────────────────────────────────────┘ │
└──────────────────────────────────────────┘
↓
┌──────────────────────────────────────────┐
│ Qdrant (xennic_shared_knowledge) │
│ - Obsidian (۱۹ chunk) │
│ - Open Notebook (۱ chunk) │
└──────────────────────────────────────────┘


---

## Endpoint

| مورد | مقدار |
|---|---|
| **URL** | `http://localhost:5678/webhook/search` |
| **Method** | `GET` |
| **Parameters** | `query` (اجباری), `limit` (اختیاری) |


---

## نتایج تست

| Query | Score برتر | منبع |
|---|---|---|
| خط گرم | **۰.۸۷** | Open Notebook + FND-003 |
| دیسپاچینگ | ۰.۸۵ | FND-002, FND-004 |


---

## مزایای Webhook GET

| ویژگی | مزیت |
|---|---|
| **URL-encoded query** | مشکل encoding فارسی حل شد |
| **بدون OAuth** | ساده‌تر از MCP |
| **بدون MCP access** | نیازی به Available in MCP نیست |
| **قابل bookmark** | در مرورگر تست می‌شود |
| **پایدار** | همیشه کار می‌کند |


---

## چالش‌های حل‌شده

1. **MCP tool_call با فارسی** → خطای encoding → راه‌حل: Webhook GET
2. **POST body با فارسی** → مشکل serialize → راه‌حل: URL-encoded
3. **Available in MCP** → نیاز به UI → راه‌حل: Webhook GET


---

## استفاده در Hermes

**در چت Hermes:**

از این URL برای جستجو استفاده کن:  
[http://localhost:5678/webhook/search?query=%D8%AE%D8%B7%20%DA%AF%D8%B1%D9%85&limit=5](http://localhost:5678/webhook/search?query=%D8%AE%D8%B7%20%DA%AF%D8%B1%D9%85&limit=5)


**یا با curl در Terminal:**
```powershell
curl.exe -s "http://localhost:5678/webhook/search?query=%D8%AE%D8%B7%20%DA%AF%D8%B1%D9%85&limit=5"
```


---

## 🎯 گام ۴: جلوگیری از موازی‌کاری

حالا که RAG مشترک کامل است، باید قواعدی برای **جلوگیری از موازی‌کاری** رعایت شود تا محتوای تکراری (مثلاً نود FND-003 «خط گرم» در Obsidian + Source «خط گرم» در Open Notebook) باعث نتایج تکراری در RAG نشود.

> [!note] مرجع یکتا
> جدول تفکیک محتوا، قرارداد Metadata مشترک و روش لینک‌دهی متقابل بین Obsidian و Open Notebook به‌طور کامل در [[META-INT-040 — قواعد تفکیک محتوا (جلوگیری از موازی‌کاری)|META-INT-040]] مستند شده‌اند. برای جلوگیری از دوباره‌کاری محتوا (طبق قاعده ۹ در META-CONV-001)، آن قواعد اینجا تکرار نمی‌شوند.

---

## ارجاعات
### لینک‌های مرتبط

- [[META-INT-020 — RAG مشترک Obsidian + Open Notebook → Qdrant|META-INT-020]] — RAG مشترک
- [[META-INT-033 — ادغام Hermes با MCP n8n-official|META-INT-033]] — ادغام MCP
- [[META-INT-040 — قواعد تفکیک محتوا (جلوگیری از موازی‌کاری)|META-INT-040]] — قواعد تفکیک و لینک‌دهی متقابل
- [[3.1-semantic-search-api]] — API جستجو

---

## Changelog

- **v1.1.0 (۱۴۰۵-۰۷-۳۰):** تصحیح `status` به مقدار معتبر `approved` (قبلاً `done`)؛ حذف فیلد غیراستاندارد `type`؛ حذف تکرار کامل محتوای META-INT-040 («جدول تفکیک» و «Metadata مشترک») و جایگزینی با ارجاع مستقیم طبق قاعده ۹ (جلوگیری از موازی‌کاری)؛ تعمیر بخش ناقص «لینک‌دهی بین دو منبع» که در نسخه قبلی نیمه‌کاره رها شده و با بخش ارجاعات قاطی شده بود.
- **v1.0.1 (۱۴۰۵-۰۷-۲۷):** به‌روزرسانی شناسه، لینک‌ها و مالک
- **v1.0.0 (۰۷۸۴-۰۵-۰۳):** ایجاد اولیه
