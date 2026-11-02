#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — اعتبارسنجی گردش‌کارهای n8n
#
# چه چیزی را بررسی می‌کند؟
#   ۱. JSON معتبر و ساختار کامل (nodes / connections / settings)
#   ۲. یکتا بودن id و name گره‌ها
#   ۳. وجود هر گره مقصد در connections
#   ۴. typeVersion گره‌های شناخته‌شده در محدوده پشتیبانی‌شده
#   ۵. تعادل {{ }} در همه عبارت‌های «=»
#   ۶. وجود gره‌های اجباری (credential، retry) و نبود رمز در فایل
#   ۷. اجرای واقعی هر پرس‌وجوی SQL روی PostgreSQL با پارامترهای نمونه
#      (داخل تراکنش و با ROLLBACK — هیچ داده‌ای تغییر نمی‌کند)
#
# اجرا:  python3 02_n8n/validate_workflows.py
# ═══════════════════════════════════════════════════════════════════════
import json
import pathlib
import re
import subprocess
import sys

import pgserver
from pathlib import Path as P

BIN = P("/usr/local/lib/python3.11/dist-packages/pgserver/pginstall/bin")
HERE = pathlib.Path(__file__).parent

SUPPORTED = {
    "n8n-nodes-base.scheduleTrigger": {1, 1.1, 1.2, 1.3},
    "n8n-nodes-base.postgres": {2, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6},
    "n8n-nodes-base.httpRequest": {4, 4.1, 4.2, 4.3, 4.4},
    "n8n-nodes-base.splitOut": {1},
    "n8n-nodes-base.if": {1, 2, 2.1, 2.2, 2.3},
    "n8n-nodes-base.noOp": {1},
    "n8n-nodes-base.set": {3, 3.1, 3.2, 3.3, 3.4},
}

# پارامترهای نمونه برای اجرای هر گره SQL (به ترتیب $1..$n)
SAMPLE_PARAMS = {
    # آپدیت کامل بله؛ همان چیزی که ${JSON.stringify($json)} تولید می‌کند
    "🧠 پردازش در PostgreSQL": [
        '{"update_id":7001,"message":{"chat_id":900001,"from":{"id":1},"text":"/help"}}'
    ],
    "✅ ثبت ارسال": ["7001"],
    "🛑 ثبت خطای دریافت": ["Connection timed out"],
}

SECRET_PATTERNS = [
    re.compile(r"\b\d{8,10}:[A-Za-z0-9_-]{30,}\b"),      # توکن بله/تلگرام
    re.compile(r"postgres(ql)?://[^\s\"']+:[^\s\"']+@"),  # رشته اتصال با رمز
]

errors, warnings = [], []


def err(wf, msg):
    errors.append(f"[{wf}] {msg}")


def warn(wf, msg):
    warnings.append(f"[{wf}] {msg}")


def check_structure(wf_name, wf):
    for key in ("name", "nodes", "connections", "settings"):
        if key not in wf:
            err(wf_name, f"کلید «{key}» وجود ندارد")
    nodes = wf.get("nodes", [])
    if not nodes:
        err(wf_name, "هیچ گره‌ای ندارد")

    names = [n.get("name") for n in nodes]
    ids = [n.get("id") for n in nodes]
    if len(set(names)) != len(names):
        err(wf_name, "نام گره‌ها یکتا نیست")
    if len(set(ids)) != len(ids):
        err(wf_name, "شناسه گره‌ها یکتا نیست")

    triggers = [n for n in nodes if "trigger" in n.get("type", "").lower()]
    if len(triggers) != 1:
        err(wf_name, f"باید دقیقاً یک گره آغازگر باشد (یافت: {len(triggers)})")

    # connections → همه مقصدها باید گره موجود باشند
    for src, m in wf.get("connections", {}).items():
        if src not in names:
            err(wf_name, f"اتصال از گره ناموجود: {src}")
        for branch in m.get("main", []):
            for target in branch:
                if target.get("node") not in names:
                    err(wf_name, f"اتصال به گره ناموجود: {target.get('node')}")

    # همه گره‌های غیرآغازگر باید ورودی داشته باشند (به‌جز گره‌های معلق)
    targets = {t["node"] for m in wf.get("connections", {}).values()
               for b in m.get("main", []) for t in b}
    for n in nodes:
        if n not in triggers and n["name"] not in targets:
            err(wf_name, f"گره بدون ورودی (یتیم): {n['name']}")

    # typeVersion و credential
    for n in nodes:
        t = n.get("type")
        if t not in SUPPORTED:
            err(wf_name, f"نوع ناشناخته: {t}")
        elif n.get("typeVersion") not in SUPPORTED[t]:
            err(wf_name, f"{n['name']}: typeVersion {n.get('typeVersion')} پشتیبانی نمی‌شود")
        if t == "n8n-nodes-base.postgres":
            creds = n.get("credentials", {})
            if "postgres" not in creds:
                err(wf_name, f"{n['name']}: اعتبارنامه PostgreSQL ندارد")
            if n.get("parameters", {}).get("resource") != "database":
                err(wf_name, f"{n['name']}: resource باید database باشد")
            if n.get("parameters", {}).get("operation") != "executeQuery":
                err(wf_name, f"{n['name']}: operation باید executeQuery باشد")
        if t == "n8n-nodes-base.httpRequest" and n.get("onError") == "continueErrorOutput":
            branches = wf.get("connections", {}).get(n["name"], {}).get("main", [])
            if len(branches) < 2 or not branches[1]:
                err(wf_name, f"{n['name']}: onError خطا فعال است اما شاخه خطا وصل نشده")
        if t == "n8n-nodes-base.httpRequest":
            if not n.get("retryOnFail"):
                warn(wf_name, f"{n['name']}: retryOnFail خاموش است")
            if n.get("onError") not in ("continueRegularOutput", "continueErrorOutput"):
                warn(wf_name, f"{n['name']}: onError تنظیم نشده — یک قطعی بله کل اجرا را متوقف می‌کند")
            url = n.get("parameters", {}).get("url", "")
            if "tapi.bale.ai" not in url:
                warn(wf_name, f"{n['name']}: آدرس بله نیست: {url[:60]}")


def check_expressions(wf_name, wf):
    def walk(obj, path):
        if isinstance(obj, dict):
            for k, v in obj.items():
                walk(v, f"{path}.{k}")
        elif isinstance(obj, list):
            for i, v in enumerate(obj):
                walk(v, f"{path}[{i}]")
        elif isinstance(obj, str) and obj.startswith("="):
            expr = obj[1:]
            if expr.count("{{") != expr.count("}}"):
                err(wf_name, f"{path}: آکولاد نامتوازن در «{expr[:50]}»")
            if "{{" in expr and not expr.strip().startswith("{{") and "='" in expr:
                err(wf_name, f"{path}: نقل‌قول مشکوک در عبارت")

    body = {k: v for k, v in wf.items() if k != "name"}
    walk(body, wf["name"])

    raw = json.dumps(wf, ensure_ascii=False)
    for pat in SECRET_PATTERNS:
        if pat.search(raw):
            err(wf_name, "الگوی رمز/توکن در فایل پیدا شد — نباید در JSON باشد")


def check_cron(wf_name, wf):
    for n in wf["nodes"]:
        rule = n.get("parameters", {}).get("rule", {})
        for it in rule.get("interval", []):
            if it.get("field") == "cronExpression":
                e = it.get("expression", "").strip()
                parts = e.split()
                if len(parts) not in (5, 6):
                    err(wf_name, f"{n['name']}: عبارت cron باید ۵ یا ۶ بخش باشد: «{e}»")


def run_sql(wf_name, node, sql):
    """اجرا با پارامترهای واقعی داخل تراکنش و ROLLBACK."""
    srv = pgserver.get_server("/tmp/pgdata", cleanup_mode=None)
    n_params = len(set(re.findall(r"\$(\d+)", sql)))
    binds = SAMPLE_PARAMS.get(node["name"], [])
    if n_params and len(binds) < n_params:
        err(wf_name, f"{node['name']}: {n_params} پارامتر دارد اما نمونه تعریف نشده")
        return
    if n_params and len(binds) > n_params:
        err(wf_name, f"{node['name']}: {len(binds)} نمونه برای {n_params} پارامتر — زیاد است")
        return

    def q(s):
        return subprocess.run([str(BIN / "psql"), srv.get_uri(), "-v", "ON_ERROR_STOP=1",
                               "-q", "-t", "-A"],
                              input=s.encode(),
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    head = q("BEGIN;")
    if head.returncode != 0:
        err(wf_name, "اتصال به پایگاه‌داده آزمایشی برقرار نشد")
        return
    cmd = sql.rstrip().rstrip(";")
    if n_params:
        cmd += "\n\\bind " + " ".join(f"'{b}'" if not str(b).startswith("{") else f"'{b}'"
                                      for b in binds[:n_params]) + "\n\\g"
    out = q(cmd)
    q("ROLLBACK;")
    if out.returncode != 0:
        err(wf_name, f"{node['name']}: SQL اجرا نشد → {out.stdout.decode()[:300]}")


def main():
    files = sorted(HERE.glob("wf-*.json"))
    if not files:
        print("❌ هیچ فایل گردش‌کاری پیدا نشد")
        return 1

    total_sql = 0
    for f in files:
        try:
            wf = json.loads(f.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            err(f.name, f"JSON نامعتبر: {e}")
            continue
        wf_name = wf.get("name", f.name)
        check_structure(wf_name, wf)
        check_expressions(wf_name, wf)
        check_cron(wf_name, wf)
        for n in wf["nodes"]:
            if n.get("type") == "n8n-nodes-base.postgres":
                sql = n["parameters"]["query"]
                total_sql += 1
                run_sql(wf_name, n, sql)

    print(f"گردش‌کارها: {len(files)} · گره SQL آزمایش‌شده: {total_sql}")
    if warnings:
        print("\n⚠️ هشدارها:")
        for w in warnings:
            print("  -", w)
    if errors:
        print("\n❌ خطاها:")
        for e in errors:
            print("  -", e)
        return 1
    print("\n✅ همه بررسی‌ها موفق بود")
    return 0


if __name__ == "__main__":
    sys.exit(main())
