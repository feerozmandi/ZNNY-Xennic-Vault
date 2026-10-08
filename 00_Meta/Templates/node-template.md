---
id: <% tp.file.title.split(" — ")[0] %>
title: <% tp.file.title.split(" — ")[1] || tp.file.title %>
layer: <% tp.system.suggester(["Founder", "PreLaunch", "Launch", "Future", "Meta"], ["Founder", "PreLaunch", "Launch", "Future", "Meta"]) %>
domain: <% tp.system.suggester(["FND", "LEG", "BRD", "FIN", "STR", "MKT", "TEC", "PLT", "AI", "OPS", "HR", "SEC", "QA", "RND", "INT", "CONV"], ["FND", "LEG", "BRD", "FIN", "STR", "MKT", "TEC", "PLT", "AI", "OPS", "HR", "SEC", "QA", "RND", "INT", "CONV"]) %>
status: draft
owner: احمد فیروزمندی بندپی
created: <% tp.date.now("YYYY-MM-DD") %>
version: 0.1.0
dependencies: []
tags: []
---

# <% tp.file.title %>

## ۱. هدف (Why)
> [توضیح هدف نود]

## ۲. محتوا
> [محتوای اصلی]

## ۳. اقدامات
- [ ] گام ۱
- [ ] گام ۲

## ۴. خروجی (Deliverable)
> [خروجی نهایی]

## ۵. ریسک‌ها
> [ریسک‌ها و راه‌حل]

## ۶. ارجاعات
- [[]]

## ۷. Changelog
- v0.1.0 (<% tp.date.now("YYYY-MM-DD") %>): ایجاد اولیه