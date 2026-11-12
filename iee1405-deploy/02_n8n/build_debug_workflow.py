#!/usr/bin/env python3
"""ساخت گردش‌کار تشخیصی IEE1405-99 — سه درخواست موازی به بله.

هدف: در **یک اجرا** معلوم شود کدام شکل درخواست کار می‌کند و کدام معلق می‌ماند:

  A) دقیقاً همان تنظیمات wf-01  (sendQuery=keypair + queryParameters + timeout 20s)
  B) ساده: همه چیز در خود آدرس     (بدون sendQuery، timeout 10s)
  C) بدون پارامتر: همان چیزی که تست ۳.۷ موفق بود (timeout 10s)

اگر فقط A گیر کند → ایراد از مسیر sendQuery/specifyQuery است.
اگر هر سه گیر کنند → خود گره HTTP در این نسخه با این دامنه مشکل دارد.
اگر هر سه برگردند → مشکل جای دیگری است (و بخش ۳.۲ می‌گوید کجا).
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "wf-debug-bale.json"

WORKFLOW_ID = "IEE1405-99"


def nid(name: str) -> str:
    import hashlib

    h = hashlib.md5(name.encode("utf-8")).hexdigest()
    return f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


def http_node(name, position, *, url_suffix, query=None, timeout, notes=None):
    params = {
        "method": "GET",
        "url": "={{ $env.BALE_API_URL }}/getUpdates" + url_suffix,
        "options": {"timeout": timeout},
    }
    if query:
        params["sendQuery"] = True
        params["specifyQuery"] = "keypair"
        params["queryParameters"] = {
            "parameters": [{"name": k, "value": v} for k, v in query.items()]
        }
    node = {
        "parameters": params,
        "id": nid(name),
        "name": name,
        "type": "n8n-nodes-base.httpRequest",
        "typeVersion": 4.2,
        "position": position,
        "retryOnFail": False,
        # نتیجه هر شاخه مستقل ثبت می‌شود؛ شکست یکی بقیه را متوقف نمی‌کند
        "onError": "continueRegularOutput",
    }
    if notes:
        node["notes"] = notes
        node["notesInFlow"] = True
    return node


def main():
    trigger = {
        "parameters": {},
        "id": nid("▶ اجرای دستی"),
        "name": "▶ اجرای دستی",
        "type": "n8n-nodes-base.manualTrigger",
        "typeVersion": 1,
        "position": [0, 0],
        "notes": "در UI دکمه «Execute workflow» را بزنید؛ هیچ زمان‌بندی ندارد",
        "notesInFlow": True,
    }

    a = http_node(
        "A) مثل wf-01", [260, -160],
        url_suffix="",
        query={"offset": "={{ (Number($json && $json.offset) || 0) + 1 }}", "limit": "50", "timeout": "0"},
        timeout=20000,
        notes="دقیقاً تنظیمات تولید: sendQuery=keypair",
    )
    b = http_node(
        "B) ساده", [260, 0],
        url_suffix="?offset=0&limit=50&timeout=0",
        query=None,
        timeout=10000,
        notes="بدون sendQuery؛ پارامترها داخل خود آدرس",
    )
    c = http_node(
        "C) بدون پارامتر", [260, 160],
        url_suffix="",
        query=None,
        timeout=10000,
        notes="همان چیزی که تست ۳.۷ با موفقیت اجرا کرد",
    )

    wf = {
        "id": WORKFLOW_ID,
        "name": "IEE1405-99 — آزمون اتصال بله (تشخیصی)",
        "nodes": [trigger, a, b, c],
        "connections": {
            trigger["name"]: {
                "main": [[
                    {"node": a["name"], "type": "main", "index": 0},
                    {"node": b["name"], "type": "main", "index": 0},
                    {"node": c["name"], "type": "main", "index": 0},
                ]]
            },
            # هر شاخه به پایان خودش می‌رسد؛ چیزی در دیتابیس تولید نمی‌نویسد
            a["name"]: {"main": [[]]},
            b["name"]: {"main": [[]]},
            c["name"]: {"main": [[]]},
        },
        "settings": {
            "executionOrder": "v1",
            "timezone": "Asia/Tehran",
            "saveManualExecutions": True,
            "saveExecutionProgress": True,
            "saveDataSuccessExecution": "all",
            "saveDataErrorExecution": "all",
            "executionTimeout": 60,
        },
        "staticData": None,
        "meta": {"templateCredsSetupCompleted": False},
        "pinData": {},
        "tags": [{"name": "IEE1405"}],
        "active": False,
    }

    OUT.write_text(json.dumps(wf, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"✅ {OUT.name} ساخته شد ({len(wf['nodes'])} گره)")


if __name__ == "__main__":
    main()
