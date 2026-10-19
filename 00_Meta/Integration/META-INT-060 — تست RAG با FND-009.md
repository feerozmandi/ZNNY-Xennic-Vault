---
id: META-INT-060
title: تست RAG با FND-009
type: integration
status: done
created: 2026-10-17
updated: 2026-10-17
tags: [integration, rag, test, qdrant, obsidian]
layer: Meta
domain: INT
owner: احمد فیروزمندی بندپی
version: 1.0.1
dependencies: []
---

# تست RAG با FND-009

## هدف

تست بروزرسانی RAG با نود جدید FND-009 و اطمینان از ایندکس‌شدن صحیح در Qdrant.


## معماری

```
nود FND-009 (Obsidian)
    → [RAG-01] Obsidian Founder → Qdrant (n8n)
        → Qdrant collection: xennic_shared_knowledge
            → Webhook Search: http://localhost:5678/webhook/search
```


## پیکربندی

### نود تستی
- **ID:** FND-009
- **Title:** تجربه تست اتوماسیون نود
- **مسیر:** `01_Founder/FND-009 — تجربه تست اتوماسیون نود.md`
- **ساخت‌کننده:** Hermes Agent + skill xennic-node-developer

### Workflow RAG
- **ID:** DlHi16COhc9f0IkQ
- **نام:** [RAG-01] Obsidian Founder → Qdrant
- **وضعیت:** غیرفعال (اجرای دستی)
- **MCP Access:** فعال ✅


## تست

```bash
# جستجوی معنایی با query "تست اتوماسیون"
curl "http://localhost:5678/webhook/search?query=تست%20اتوماسیون&limit=5"
```


## نتایج

| معیار | مقدار |
|-------|-------|
| امتیاز (Score) | **۰.۸۲** |
| جایگاه | **اول** |
| points_count | **۷۷ → ۷۸** (+۱) |
| منبع | obsidian |
| node_id | FND-009 |

نود FND-009 با بالاترین امتیاز در نتایج جستجوی معنایی ظاهر شد که نشان‌دهنده ایندکس‌شدن موفق و embedding صحیح است.

## ارجاعات
### لینک‌های مرتبط

- [[META-INT-034 — ادغام Hermes با RAG مشترک|META-INT-034]]
- [[FND-009 — تجربه تست اتوماسیون نود|FND-009]]
- [[META-INT-050 — راه‌اندازی کامل Hermes|META-INT-050]]

## Changelog

- v1.0.1 (۱۴۰۵-۰۷-۲۷): به‌روزرسانی شناسه، لینک‌ها و مالک
- v6.0 (۱۴۰۵-۰۷-۲۵): تست موفق RAG با نود جدید FND-009 — Score ۰.۸۲ (جایگاه اول)، points_count: ۷۸
