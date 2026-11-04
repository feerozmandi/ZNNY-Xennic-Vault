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
import os
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
    "n8n-nodes-base.manualTrigger": {1},
}

# پارامترهای نمونه برای اجرای هر گره SQL (به ترتیب $1..$n)
SAMPLE_PARAMS = {
    # آپدیت کامل بله؛ همان چیزی که ${JSON.stringify($json)} تولید می‌کند
    "🧠 پردازش در PostgreSQL": [
        '{"update_id":7001,"message":{"chat_id":900001,"from":{"id":1},"text":"/help"}}'
    ],
    # پاسخ موفق بله، همان شکل واقعی getUpdates
    "🩺 بازرسی پاسخ بله": ['{"ok":true,"result":[]}'],
    # پاسخ واقعی sendMessage بله + شناسه آپدیتی که باید «ارسال‌شده» شود
    "✅ ثبت ارسال": ["7001", '{"ok":true,"result":{"message_id":5}}'],
    # مسیر جایگزین: همان شناسه + پاسخ بله به ارسال بی‌دکمه
    "✅ ثبت ارسال بدون دکمه": ["7001", '{"ok":true,"result":{"message_id":6}}'],
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
        if wf_name.startswith("IEE1405-01") and "poll_watch" not in json.dumps(n, ensure_ascii=False):
            pass
        if t == "n8n-nodes-base.httpRequest" and n.get("onError") == "continueErrorOutput":
            branches = wf.get("connections", {}).get(n["name"], {}).get("main", [])
            if len(branches) < 2 or not branches[1]:
                err(wf_name, f"{n['name']}: onError خطا فعال است اما شاخه خطا وصل نشده")
        if t == "n8n-nodes-base.httpRequest":
            if n.get("onError") not in ("continueRegularOutput", "continueErrorOutput"):
                err(wf_name, f"{n['name']}: onError تنظیم نشده — یک قطعی بله کل اجرا را متوقف می‌کند")
            params = n.get("parameters", {})
            # تنها متغیر تأییدشده BALE_API_URL است (setup_env.sh می‌سازد و
            # preflight.sh بررسی می‌کند). نام دیگری یعنی آدرس «botundefined».
            url = params.get("url", "")
            if "$env.BALE_API_URL" not in url:
                err(wf_name, f"{n['name']}: آدرس باید از $env.BALE_API_URL ساخته شود: {url[:60]}")
            elif url.rstrip().endswith("BALE_API_URL"):
                err(wf_name, f"{n['name']}: متد به آدرس اضافه نشده است")
            # بدون timeout، درخواست معلق اجرا را دقیقه‌ها در حالت running نگه می‌دارد
            timeout = (params.get("options") or {}).get("timeout")
            if not isinstance(timeout, int) or timeout <= 0 or timeout > 120000:
                err(wf_name, f"{n['name']}: options.timeout معتبر نیست ({timeout}) — "
                             "درخواست معلق اجرا را قفل می‌کند")
            if n.get("retryOnFail"):
                warn(wf_name, f"{n['name']}: retryOnFail روشن است — صف اجرا شلوغ می‌شود; "
                                "تحویل تضمین‌شده از دیتابیس می‌آید")


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


# ═══════════════════════════════════════════════════════════════════════
# قاعده «ورودی گره HTTP»: هر $json.<field> در گره HTTP باید در خروجی گره
# بالادستی وجود داشته باشد. باگ واقعی نسخه ۰.۱.۹ همین بود: گره ضربان فقط
# {at} برمی‌گرداند و گره HTTP که بعد از آن است، $json.offset را undefined
# می‌دید → «offset=NaN» → بله: 400 malformed request.
# ═══════════════════════════════════════════════════════════════════════
EXPR_FIELD = re.compile(r"\$json(?:\.([A-Za-z_][A-Za-z0-9_]*)|\[['\"]([^'\"]+)['\"]\])")
SQL_ALIAS = re.compile(r'\bAS\s+(?:"([^"]+)"|([A-Za-z_][A-Za-z0-9_]*))', re.IGNORECASE)


def _fields_in(obj):
    found = set()
    if isinstance(obj, dict):
        for v in obj.values():
            found |= _fields_in(v)
    elif isinstance(obj, list):
        for v in obj:
            found |= _fields_in(v)
    elif isinstance(obj, str):
        for m in EXPR_FIELD.finditer(obj):
            found.add(m.group(1) or m.group(2))
    return found


def _upstream(wf, node_name):
    """گره‌هایی که خروجی‌شان به این گره می‌رسد (یک گام عقب)."""
    ups = []
    for src, conns in wf.get("connections", {}).items():
        for branch in conns.get("main", []):
            for link in branch or []:
                if link.get("node") == node_name:
                    ups.append(src)
    return ups


# گره‌هایی که ورودی‌شان را از جای دیگری می‌گیرند (نه آیتم گره بالادستی)
REFERENCE_ONLY = {"n8n-nodes-base.scheduleTrigger", "n8n-nodes-base.manualTrigger",
                  "n8n-nodes-base.splitOut", "n8n-nodes-base.if", "n8n-nodes-base.noOp"}


# خروجی شناخته‌شده گره‌های HTTP بله: از روی انتهای URL تشخیص داده می‌شود.
# sendMessage پاسخ {ok, result:{message_id}} می‌دهد و **update_id ندارد**؛
# استفاده از $json.update_id بعد از آن همیشه NULL است.
HTTP_OUTPUTS = {
    "/getUpdates": {"ok", "result", "error_code", "description"},
    "/sendMessage": {"ok", "result", "error_code", "description"},
    "/setWebhook": {"ok", "description"},
    "/deleteWebhook": {"ok", "description"},
}


def _http_fields(url):
    for suffix, fields in HTTP_OUTPUTS.items():
        if suffix in url:
            return fields
    return None

def check_http_inputs(wf_name, wf):
    """هر $json.<field> باید در خروجی گره بالادستی وجود داشته باشد.

    باگ واقعی ۰.۱.۱۱: گره «ثبت ارسال» بعد از گره ارسال بود و $json.update_id
    می‌خواند؛ خروجی گره ارسال پاسخ بله است و update_id ندارد → NULL → پیام
    هر ۲۰ ثانیه تکرار می‌شد. ارجاع صریح به گره دیگر ($('...').item) از این
    قاعده مستثنی است.
    """
    by_name = {n["name"]: n for n in wf["nodes"]}
    for n in wf["nodes"]:
        if n.get("type") in REFERENCE_ONLY:
            continue
        params = n.get("parameters", {})
        # $('نام گره').item.json.x → وابستگی به گره دیگر است، نه به گره بالادست
        if "$(" in json.dumps(params, ensure_ascii=False) or "$node[" in json.dumps(params, ensure_ascii=False):
            continue
        used = _fields_in(params)
        if not used:
            continue
        for up_name in _upstream(wf, n["name"]):
            up = by_name.get(up_name)
            if not up:
                continue

            if up.get("type") == "n8n-nodes-base.httpRequest":
                # خروجی شناخته‌شده HTTP: فیلدهای غیرموجود را می‌گیریم
                allowed = _http_fields(up.get("parameters", {}).get("url", ""))
                if allowed is None:
                    continue
                missing = {f for f in used if f not in allowed and f not in {"data", "json"}}
                if missing:
                    err(
                        wf_name,
                        f"گره «{n['name']}» از {sorted(missing)} استفاده می‌کند ولی خروجی گره "
                        f"«{up_name}» (پاسخ بله) این فیلدها را ندارد → مقدار NULL",
                    )
                continue

            if up.get("type") != "n8n-nodes-base.postgres":
                continue
            sql = up.get("parameters", {}).get("query", "")
            aliases = {a or b for a, b in SQL_ALIAS.findall(sql)}
            # ستون‌های بدون AS (مثل SELECT a, b) هم پذیرفته می‌شوند
            # ستون‌های بدون AS، با یا بدون پیشوند جدول: o.chat_id → chat_id
            aliases |= set(
                re.findall(
                    r"(?:SELECT|,)\s*(?:[A-Za-z_][A-Za-z0-9_]*\.)?([A-Za-z_][A-Za-z0-9_]*)",
                    sql,
                    re.I,
                )
            )
            missing = used - aliases
            if missing:
                err(
                    wf_name,
                    f"گره «{n['name']}» از {sorted(missing)} استفاده می‌کند ولی خروجی گره "
                    f"«{up_name}» این فیلدها را ندارد (متغیر undefined → مقدار NaN/خالی در URL)",
                )

# ═══════════════════════════════════════════════════════════════════════
# قاعده «ترتیب وابستگی»: جلو بردن offset باید **بعد** از پردازش باشد، چون
# poll_advance() مقدارش را از bot_updates می‌خواند. باگ واقعی ۰.۱.۱۱ همین
# بود: advance قبل از dispatch اجرا می‌شد، جدول خالی بود و offset صفر
# می‌ماند → همان دسته هر ۲۰ ثانیه دوباره گرفته می‌شد.
# ═══════════════════════════════════════════════════════════════════════
ADVANCE_NODES = {"⏭ ثبت زمان دریافت": "🧠 پردازش در PostgreSQL"}


def _reachable(wf, start):
    seen, stack = set(), [start]
    while stack:
        cur = stack.pop()
        for branch in wf.get("connections", {}).get(cur, {}).get("main", []):
            for link in branch or []:
                nxt = link.get("node")
                if nxt and nxt not in seen:
                    seen.add(nxt)
                    stack.append(nxt)
    return seen


def check_order(wf_name, wf):
    names = {n["name"] for n in wf["nodes"]}
    for advance, before in ADVANCE_NODES.items():
        if advance not in names or before not in names:
            continue
        # advance باید از before قابل دسترسی باشد (یعنی پایین‌دست آن)
        if advance not in _reachable(wf, before):
            err(
                wf_name,
                f"ترتیب غلط: «{advance}» باید بعد از «{before}» باشد، وگرنه "
                f"جدول bot_updates هنگام خواندن خالی است و offset جلو نمی‌رود",
            )

# ═══════════════════════════════════════════════════════════════════════
# قاعده «ادامه زنجیره»: گره‌ای که ممکن است صفر ردیف برگرداند و گره‌های
# بعدی به آن وابسته‌اند، باید alwaysOutputData داشته باشد. باگ واقعی
# ۰.۱.۱۵: در پیمایش خالی (result: []) گره پردازش صفر ردیف می‌داد و n8n
# همه گره‌های بعدی را رد می‌کرد — یعنی پاسخ‌های ارسال‌نشده هرگز دوباره
# تلاش نمی‌شدند و تضمین تحویل شکسته بود.
# ═══════════════════════════════════════════════════════════════════════
MUST_CONTINUE = {
    "🧠 پردازش در PostgreSQL": "در پیمایش خالی صفر ردیف می‌دهد و ارسال پاسخ‌های معوق بعد از آن است",
    "✂️ تفکیک آپدیت‌ها": "در پیمایش خالی هیچ آیتمی تولید نمی‌کند",
}


def check_continuation(wf_name, wf):
    by_name = {n["name"]: n for n in wf["nodes"]}
    for name, why in MUST_CONTINUE.items():
        n = by_name.get(name)
        if n and not n.get("alwaysOutputData"):
            err(wf_name, f"گره «{name}» باید alwaysOutputData داشته باشد: {why}")


# ═══════════════════════════════════════════════════════════════════════
# قاعده «کات هرس‌شده»: در PostgreSQL، CTE بدون ارجاع اجرا نمی‌شود (PG 12+).
# باگ واقعی ۰.۱.۱۶: WF-04 با «WITH rec AS (SELECT recover_if_dead()) ...»
# نوشته شده بود و خودترمیمی هرگز اجرا نمی‌شد — بی‌صدا و بدون هیچ خطایی.
# ═══════════════════════════════════════════════════════════════════════
NAMED_CTE = re.compile(r"\bWITH\s+(?:RECURSIVE\s+)?([A-Za-z_][A-Za-z0-9_]*)\s+AS\s*\(", re.I)


def check_unused_cte(wf_name, wf):
    for n in wf["nodes"]:
        if n.get("type") != "n8n-nodes-base.postgres":
            continue
        sql = n.get("parameters", {}).get("query", "")
        for name in NAMED_CTE.findall(sql):
            # تعداد ارجاع: یک بار در تعریف + هر بار استفاده
            if len(re.findall(rf"\b{re.escape(name)}\b", sql)) < 2:
                err(
                    wf_name,
                    f"گره «{n['name']}»: کات «{name}» هیچ‌جا استفاده نشده — "
                    f"PostgreSQL آن را اجرا نمی‌کند (کار بی‌اثر و بی‌صدا)",
                )

def check_cron(wf_name, wf):
    for n in wf["nodes"]:
        rule = n.get("parameters", {}).get("rule", {})
        for it in rule.get("interval", []):
            if it.get("field") == "cronExpression":
                e = it.get("expression", "").strip()
                parts = e.split()
                if len(parts) not in (5, 6):
                    err(wf_name, f"{n['name']}: عبارت cron باید ۵ یا ۶ بخش باشد: «{e}»")


def _test_uri(srv):
    """همان دیتابیس تولید (xennic) اگر ساختارش هست؛ وگرنه پیش‌فرض."""
    base = srv.get_uri()
    for name in (os.environ.get("IEE_TEST_DB"), "xennic", "postgres"):
        if not name:
            continue
        cand = base.replace("/postgres?", f"/{name}?")
        try:
            r = subprocess.run(
                [str(BIN / "psql"), cand, "-X", "-t", "-A", "-c",
                 "SELECT to_regclass('iee1405.bot_state') IS NOT NULL"],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10)
            if r.stdout.decode().strip() == "t":
                return cand
        except Exception:
            continue
    return base


def run_sql(wf_name, node, sql):
    """اجرا با پارامترهای واقعی داخل تراکنش و ROLLBACK."""
    srv = pgserver.get_server("/tmp/pgdata", cleanup_mode=None)
    uri = _test_uri(srv)
    n_params = len(set(re.findall(r"\$(\d+)", sql)))
    binds = SAMPLE_PARAMS.get(node["name"], [])
    if n_params and len(binds) < n_params:
        err(wf_name, f"{node['name']}: {n_params} پارامتر دارد اما نمونه تعریف نشده")
        return
    if n_params and len(binds) > n_params:
        err(wf_name, f"{node['name']}: {len(binds)} نمونه برای {n_params} پارامتر — زیاد است")
        return

    def q(s):
        return subprocess.run([str(BIN / "psql"), uri, "-v", "ON_ERROR_STOP=1",
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
        check_http_inputs(wf_name, wf)
        check_order(wf_name, wf)
        check_continuation(wf_name, wf)
        check_unused_cte(wf_name, wf)
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
