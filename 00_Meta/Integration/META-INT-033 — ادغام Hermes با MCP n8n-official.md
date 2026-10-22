---
id: META-INT-033
title: ادغام Hermes با MCP n8n-official
status: approved
created: 2026-10-15
tags: [integration, hermes, mcp, n8n, oauth]
layer: Meta
domain: INT
owner: احمد فیروزمندی بندپی
version: 1.2.0
dependencies: []
---

# ادغام Hermes با MCP n8n-official

> [!abstract] هدف
> اتصال Hermes به n8n از طریق MCP Server رسمی n8n-official.

## فهرست

| # | بخش |
|---|---|
| ۱ | هدف |
| ۲ | پیکربندی |
| ۳ | OAuth Flow |
| ۴ | Toolهای در دسترس (۱۴ عدد) |
| ۵ | استفاده |
| ۶ | نکات مهم |
| ۷ | ارجاعات |
| ۸ | Changelog |

---

## هدف
اتصال Hermes به n8n از طریق MCP Server رسمی n8n-official.


---

## پیکربندی

| مورد | مقدار |
|---|---|
| **MCP Server Name** | `n8n-official` |
| **Transport** | HTTP |
| **URL** | `http://localhost:5678/mcp-server/http` |
| **Authentication** | OAuth 2.1 |
| **OAuth Callback** | `http://127.0.0.1:27890/callback` |


---

## OAuth Flow

1. `hermes mcp login n8n-official`
2. مرورگر باز می‌شود
3. در n8n → **Authorize**
4. توکن دریافت می‌شود


---

## Toolهای در دسترس (۱۴ عدد)

- List/Create/Update/Get/Delete workflows
- Execute workflow
- List/Get executions
- List credentials
- List projects
- List tags
- List/Read/Write data tables


---

## استفاده

### در چت Hermes:

از طریق MCP n8n، Workflow "[API-01] Semantic Search" را با query "خط گرم" اجرا کن


### در Terminal:
```powershell
hermes mcp list
hermes mcp test n8n-official
```


---

## نکات مهم

- **Workflow باید Available in MCP باشد** تا Hermes آن را ببیند
    
- **OAuth توکن** به‌طور خودکار تمدید می‌شود
    
- **MCP Server n8n** روی همان پورت ۵۶۷۸ (نه ۵۶۷۹)

- **بدون موازی‌کاری با بسته Community:** در `config.yaml` هرمس، یک ردیف سوم با نام `n8n` (بسته جامعه‌محور `uvx n8n-mcp-server`) هم موجود است، اما طبق تأیید `hermes mcp list` (۱۴۰۵-۰۷-۳۰) وضعیت آن `✗ disabled` است. تنها `n8n-official` فعال است — بنابراین این نود همچنان تنها مرجع صحیح ادغام n8n است. حذف بلوک غیرفعال از `config.yaml` یک اقدام نظافتی جزئی پیشنهادی است، نه الزام حاکمیتی.

---

## ارجاعات
### لینک‌های مرتبط

- [[3.1-semantic-search-api]] — API جستجو
    
- [[3.3-hermes-mcp-integration]] — ادغام MCP

---

## Changelog

- **v1.2.0 (۱۴۰۵-۰۷-۳۰):** ثبت تأیید `hermes mcp list` مبنی بر عدم موازی‌کاری واقعی بین `n8n-official` و بسته Community غیرفعال `n8n`.
- **v1.1.0 (۱۴۰۵-۰۷-۳۰):** تصحیح `status` به مقدار معتبر `approved` طبق قاعده ۱۱ (قبلاً `done`)؛ حذف فیلد غیراستاندارد `type`.
- **v1.0.1 (۱۴۰۵-۰۷-۲۷):** به‌روزرسانی شناسه، لینک‌ها و مالک
- **v1.0.0 (۰۷۸۴-۰۵-۰۱):** ایجاد اولیه
