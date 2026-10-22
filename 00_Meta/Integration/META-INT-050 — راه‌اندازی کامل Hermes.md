---
id: META-INT-050
title: راه‌اندازی کامل Hermes
status: approved
created: 2026-10-16
tags: [integration, hermes, mcp, obsidian, n8n]
layer: Meta
domain: INT
owner: احمد فیروزمندی بندپی
version: 1.2.0
dependencies: []
---

# راه‌اندازی کامل Hermes

> [!abstract] هدف
> راه‌اندازی کامل Hermes Agent با ۲ MCP Server فعال برای اتصال به Obsidian Vault و n8n Workflow Automation.

## فهرست

| # | بخش |
|---|---|
| ۱ | هدف |
| ۲ | معماری |
| ۳ | پیکربندی |
| ۴ | تست |
| ۵ | نتایج |
| ۶ | چالش‌های حل‌شده |
| ۷ | ارجاعات |
| ۸ | Changelog |

---

## هدف

راه‌اندازی کامل Hermes Agent با ۲ MCP Server فعال برای اتصال به Obsidian Vault و n8n Workflow Automation.


---

## معماری

```
Hermes Agent (desktop app)
├── MCP Server: obsidian (42 tools)
│   └── Vault: F:\ahmad\obsidian\ZNNY-Xennic-Vault
├── MCP Server: n8n-official (51 tools)
│   └── n8n: http://localhost:5678 (v2.42.6)
└── RAG Pipeline (shared)
    ├── Open Notebook → Qdrant
    └── Obsidian Founder → Qdrant
```


---

## پیکربندی

### Hermes Config
- مسیر: `C:/Users/Narges/AppData/Local/hermes/config.yaml`
- مدل فعال: gapgpt-qwen-3.5 (provider: gapgpt)

### MCP Servers فعال

| Server | Tools | بایند |
|--------|-------|-------|
| obsidian | 42 | `F:\ahmad\obsidian\ZNNY-Xennic-Vault` |
| n8n-official | 51 | `http://localhost:5678` |

> [!success] تأیید مستقل ۱۴۰۵-۰۷-۳۰ — بدون موازی‌کاری
> خروجی `hermes mcp list` مستقیماً تأیید کرد که دقیقاً همین ۲ Server فعال‌اند و وضعیت `✓ enabled` دارند. یک ردیف سوم با نام `n8n` (ترنسپورت `uvx n8n-mcp-server`، بسته MCP جامعه‌محور/Community) هم در `config.yaml` موجود است اما وضعیت آن `✗ disabled` است — یعنی **هیچ تداخل یا موازی‌کاری واقعی بین دو MCP برای n8n وجود ندارد**؛ فقط یک پیکربندی قدیمی/آزمایشی غیرفعال باقی مانده که پاک‌سازی آن (حذف بلوک مربوطه از `config.yaml`) یک اقدام نظافتی جزئی و کم‌اولویت است، نه یک ریسک حاکمیتی. جزئیات بیشتر در [[META-INT-033 — ادغام Hermes با MCP n8n-official|META-INT-033]].

### Vault
- مسیر: `F:\ahmad\obsidian\ZNNY-Xennic-Vault`
- Git: branch dev
- Backup: obsidian-git (هر ۱۰ دقیقه)

### زیرساخت RAG مشترک
- **Qdrant:** `http://localhost:6333` (v1.18.3)
- **E5-large TEI:** `http://localhost:8001` (1.9.4) — 1024 dimensions, Cosine
- **Collection:** `xennic_shared_knowledge`
- **Open Notebook:** `http://localhost:5055` (v1.15.0)
- **Webhook Search:** `http://localhost:5678/webhook/search?query={q}&limit=5`


---

## تست

```bash
# تست اتصال Obsidian MCP
mcp__obsidian__notes_search({ query: "FND" })

# تست اتصال n8n MCP
mcp__n8n_official__search_workflows({ limit: 5 })

# تست RAG Search
curl "http://localhost:5678/webhook/search?query=خط گرم&limit=5"
```


---

## نتایج

- ✅ Hermes Desktop App با موفقیت نصب و پیکربندی شد
- ✅ Obsidian MCP Server متصل و فعال (۴۲ ابزار)
- ✅ n8n-official MCP Server متصل و فعال (۵۱ ابزار)
- ✅ RAG pipeline مشترک فعال (E5-large → Qdrant)
- ✅ Webhook semantic search قابل استفاده


---

## چالش‌های حل‌شده

1. **Encoding فارسی در MCP tool_call:** کاراکترهای فارسی (عربی-فارسی) در JSON tool_call مشکل serialize ایجاد می‌کردند. راه‌حل: استفاده از Webhook GET endpoint به جای MCP tool_call برای جستجوی معنایی فارسی.
2. **MCP access روی workflow:** workflowهای n8n پیش‌فرض `mcpAccess: false` دارند — باید از طریق UI فعال شوند.
3. **عدم دسترسی به browser محلی:** Chromium نصب نبود؛ استفاده از direct file write و HTTP API به جای browser automation.

---

## ارجاعات
### لینک‌های مرتبط

- [[3.1-semantic-search-api]]
- [[META-INT-033 — ادغام Hermes با MCP n8n-official|META-INT-033]]
- [[META-INT-034 — ادغام Hermes با RAG مشترک|META-INT-034]]
- [[META-INT-020 — RAG مشترک Obsidian + Open Notebook → Qdrant|META-INT-020]]

---

## Changelog

- **v1.2.0 (۱۴۰۵-۰۷-۳۰):** تأیید مستقل تعداد MCP Server فعال از طریق `hermes mcp list`؛ ثبت وجود یک ردیف Community غیرفعال (`n8n`) در `config.yaml` به‌عنوان یادآوری نظافتی کم‌اولویت، نه موازی‌کاری واقعی.
- **v1.1.0 (۱۴۰۵-۰۷-۳۰):** تصحیح `status` به مقدار معتبر `approved` (قبلاً `done`)؛ حذف فیلدهای غیراستاندارد `type` و `updated`.
- **v1.0.1 (۱۴۰۵-۰۷-۲۷):** به‌روزرسانی شناسه، لینک‌ها و مالک
- **v0.5.0 (۱۴۰۵-۰۷-۲۴):** راه‌اندازی کامل Hermes با ۲ MCP Server (obsidian + n8n-official) — در نسخه اصلی این سطر به‌اشتباه «v5.0» ثبت شده بود؛ هنگام یکپارچه‌سازی این نود در طرح شماره‌گذاری SemVer فعلی، به v0.5.0 اصلاح شد تا با توالی نسخه‌های بالا (v1.0.0 → v1.0.1) سازگار باشد.
