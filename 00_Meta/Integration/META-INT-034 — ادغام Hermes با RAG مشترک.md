---
id: META-INT-034
title: ادغام Hermes با RAG مشترک
type: integration
status: done
created: 2026-10-17
tags: [integration, hermes, rag, webhook, get]
layer: Meta
domain: INT
owner: احمد فیروزمندی بندپی
version: 1.0.1
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

حالا که RAG مشترک کامل است، باید قواعدی برای **جلوگیری از موازی‌کاری** تعریف کنیم.

### چالش

**موازی‌کاری ممکن:** محتوای تکراری در Obsidian و Open Notebook.

**مثال:** نود FND-003 (خط گرم) در Obsidian + Source «خط گرم» در Open Notebook.

**نتیجه:** نتایج تکراری در RAG.

### راه‌حل: قواعد تفکیک

| مورد | Obsidian | Open Notebook |
|---|---|---|
| **نودهای سازمانی** | ✅ | ❌ |
| **تصمیمات** | ✅ | ❌ |
| **جلسات** | ✅ | ❌ |
| **PDF و کتاب** | ❌ | ✅ |
| **استانداردها** | ❌ | ✅ |
| **قوانین** | ❌ | ✅ |

### Metadata مشترک

**در Obsidian (frontmatter):**
```yaml
---
id: FND-003
source: obsidian
type: node
tags: [founder, experience, live-line]
---
```

**در Open Notebook (payload):**

{
  "source": "open_notebook",
  "source_id": "source:...",
  "type": "document",
  "tags": ["standards", "pdf"]
}

### لینک‌دهی بین دو منبع

**در Obsidian:** اگر نودی به یک سند Open Notebook اشاره دارد:

---

## ارجاعات
### لینک‌های مرتبط

- [[META-INT-020 — RAG مشترک Obsidian + Open Notebook → Qdrant|META-INT-020]] — RAG مشترک
    
- [[3.1-semantic-search-api]] — API جستجو
    
- [[META-INT-033 — ادغام Hermes با MCP n8n-official|META-INT-033]] — ادغام MCP



---

### منابع مرتبط
- OpenNotebook: source:1i9j5enf9dv2q2p7vczm — خط گرم

**در Open Notebook:** اگر سندی به نود Obsidian اشاره دارد:

منبع مرتبط: FND-003 (Obsidian)

---

## Changelog

- **v1.0.1 (۱۴۰۵-۰۷-۲۷):** به‌روزرسانی شناسه، لینک‌ها و مالک
- **v1.0.0 (۰۷۸۴-۰۵-۰۳):** ایجاد اولیه
