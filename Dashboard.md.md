---
id: DASHBOARD
title: داشبورد مرکزی Xennic
type: dashboard
created: 2026-10-08
---

# 🎯 داشبورد مرکزی Xennic

## 📊 آمار کلی

```dataview
TABLE length(rows) AS "تعداد", rows.file.link AS "نودها"
FROM "01_Founder" OR "02_PreLaunch" OR "03_Launch"
GROUP BY layer
```

## 📝 نودهای در حال توسعه

```dataview
TABLE status, owner, version
FROM "01_Founder" OR "02_PreLaunch" OR "03_Launch"
WHERE status = "draft"
SORT file.mtime DESC
LIMIT 10
```

## ✅ نودهای تایید‌شده

```dataview
TABLE status, owner, version
FROM "01_Founder" OR "02_PreLaunch" OR "03_Launch"
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

## 📅 آخرین تغییرات

```dataview
TABLE file.mtime AS "آخرین تغییر", status
FROM "01_Founder" OR "02_PreLaunch" OR "03_Launch"
SORT file.mtime DESC
LIMIT 10
```

## 🏷️ بر اساس Domain

```dataview
TABLE length(rows) AS "تعداد"
FROM "02_PreLaunch" OR "03_Launch"
GROUP BY domain
```