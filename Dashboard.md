---
id: DASHBOARD
title: داشبورد مرکزی Xennic
type: dashboard
created: 2026-10-08
layer: Meta
domain: CONV
status: draft
owner: احمد فیروزمندی بندپی
version: 0.2.0
dependencies: []
tags: [dashboard]
---

# 🎯 داشبورد مرکزی Xennic

## 📊 آمار کلی

```dataview
TABLE length(rows) AS "تعداد", rows.file.link AS "نودها"
FROM "01_Founder" OR "02_PreLaunch" OR "03_Launch" OR "05_Knowledge"
GROUP BY layer
```

## 📝 نودهای در حال توسعه

```dataview
TABLE status, owner, version
FROM "01_Founder" OR "02_PreLaunch" OR "03_Launch" OR "05_Knowledge"
WHERE status = "draft"
SORT file.mtime DESC
LIMIT 10
```

## 🔎 نودهای در حال بازبینی

```dataview
TABLE status, owner, version
FROM "01_Founder" OR "02_PreLaunch" OR "03_Launch" OR "05_Knowledge"
WHERE status = "review"
SORT file.mtime DESC
LIMIT 10
```

## ✅ نودهای تایید‌شده

```dataview
TABLE status, owner, version
FROM "01_Founder" OR "02_PreLaunch" OR "03_Launch" OR "05_Knowledge"
WHERE status = "approved"
SORT file.mtime DESC
LIMIT 10
```

## 🏢 نودهای Founder

```dataview
TABLE title, version, status
FROM "01_Founder"
SORT id ASC
```

## 🚀 نودهای PreLaunch

```dataview
TABLE title, version, status
FROM "02_PreLaunch"
SORT id ASC
```

## 🚀 نودهای Launch

```dataview
TABLE title, version, status
FROM "03_Launch"
SORT id ASC
```

## 📚 نودهای Knowledge

```dataview
TABLE title, version, status
FROM "05_Knowledge"
SORT id ASC
```

## 📅 آخرین تغییرات

```dataview
TABLE file.mtime AS "آخرین تغییر", status
FROM "01_Founder" OR "02_PreLaunch" OR "03_Launch" OR "05_Knowledge"
SORT file.mtime DESC
LIMIT 10
```

## 🏷️ بر اساس Domain

```dataview
TABLE length(rows) AS "تعداد"
FROM "02_PreLaunch" OR "03_Launch" OR "05_Knowledge"
GROUP BY domain
```

---

## Changelog
- **v0.2.0 (2026-10-29):** پوشش لایهٔ `05_Knowledge` که تا این نسخه در هیچ بخشی از داشبورد دیده نمی‌شد (آمار کلی، آخرین تغییرات، تفکیک Domain) اضافه شد؛ یک بخش اختصاصی «📚 نودهای Knowledge» ایجاد شد. جدول جدید «🔎 نودهای در حال بازبینی» (`status = review`) اضافه شد تا چرخهٔ ۴ حالتهٔ رسمی وضعیت نود (`draft|review|approved|archived`، طبق META-CONV-001) به‌جای فقط دو حالت قبلی پوشش داده شود.
- **v0.1.0 (2026-10-08):** ایجاد اولیه — داشبورد مرکزی با نماهای Dataview برای آمار کلی، نودهای در حال توسعه/تأیید‌شده، فهرست نودهای هر لایه (Founder/PreLaunch/Launch)، آخرین تغییرات و تفکیک بر اساس Domain.
