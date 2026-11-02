#!/usr/bin/env python3
"""رمزگشایی execution_data در n8n و چاپ خطای واقعی یک اجرا.

n8n داده اجرا را با قالب فشرده «flatted» ذخیره می‌کند: یک آرایه که
عناصر آن رشته‌های عددی اشاره‌گر به اندیس همان آرایه‌اند. به همین دلیل
خواندن خام آن چیزهایی مثل lastNodeExecuted = "7" نشان می‌دهد.

ورودی: متن خام ستون execution_data روی stdin (یا مسیر فایل به‌عنوان آرگومان)
خروجی: نام گره شکست‌خورده، پیام خطا، و وضعیت هر گره در آن اجرا
"""
import json
import sys

MAX_DEPTH = 60


def unflatten(raw):
    """تبدیل آرایه فشرده n8n/flatted به ساختار عادی و قابل خواندن."""
    raw = raw.strip()
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {"__parse_error__": raw[:400]}

    if isinstance(data, dict):
        return data                      # بعضی نسخه‌ها فشرده نیستند
    if not isinstance(data, list) or not data:
        return data

    root = data[0]
    if not isinstance(root, (dict, list)):
        return root

    resolving = {0}

    def resolve(value, depth=0):
        if depth > MAX_DEPTH:
            return value
        if isinstance(value, dict):
            return {k: resolve(v, depth + 1) for k, v in value.items()}
        if isinstance(value, list):
            return [resolve(v, depth + 1) for v in value]
        if isinstance(value, str) and value.isdigit():
            idx = int(value)
            if 0 <= idx < len(data) and idx not in resolving:
                resolving.add(idx)
                try:
                    return resolve(data[idx], depth + 1)
                finally:
                    resolving.discard(idx)
        return value

    return resolve(root)


def short(value, limit=400):
    if value is None:
        return "—"
    if isinstance(value, (dict, list)):
        value = json.dumps(value, ensure_ascii=False)
    value = str(value).replace("\n", " ")
    return value if len(value) <= limit else value[:limit] + "…"


def status_of(run):
    if not isinstance(run, dict):
        return "?"
    if run.get("error"):
        return "error"
    if run.get("executionStatus"):
        return str(run["executionStatus"])
    return "success"


def main():
    if len(sys.argv) > 1:
        raw = open(sys.argv[1], encoding="utf-8", errors="replace").read()
    else:
        raw = sys.stdin.read()

    data = unflatten(raw)
    if not isinstance(data, dict):
        print("⚠️ execution_data قابل رمزگشایی نبود")
        print(short(data, 600))
        return 1

    if "__parse_error__" in data:
        print("⚠️ execution_data معتبر نیست (بریده یا دودویی)")
        print(short(data["__parse_error__"], 600))
        return 1

    rd = data.get("resultData") or {}
    err = rd.get("error") or data.get("error") or {}
    last = data.get("lastNodeExecuted") or rd.get("lastNodeExecuted")

    print("گره شکست‌خورده : %s" % short(last, 120))
    node = err.get("node")
    if isinstance(node, dict):
        print("گره خطادار     : %s" % short(node.get("name"), 120))
        if node.get("type"):
            print("نوع گره        : %s" % short(node.get("type"), 120))
    print("پیام خطا       : %s" % short(err.get("message"), 500))
    if err.get("description"):
        print("توضیح          : %s" % short(err.get("description"), 500))
    for key in ("httpCode", "level", "name", "status"):
        if err.get(key) not in (None, ""):
            print("%-15s: %s" % (key, short(err.get(key), 200)))
    if err.get("context"):
        print("context        : %s" % short(err.get("context"), 300))
    if err.get("stack"):
        print("stack (اول)    : %s" % short(str(err["stack"]).splitlines()[0], 300))

    run_data = rd.get("runData") or data.get("runData") or {}
    if isinstance(run_data, dict) and run_data:
        print("\nگره‌های این اجرا (به ترتیب):")
        for name, runs in run_data.items():
            runs = runs if isinstance(runs, list) else [runs]
            parts = []
            for run in runs:
                st = status_of(run)
                ms = run.get("executionTime") or run.get("executionStatus") or ""
                if st == "error" and isinstance(run.get("error"), dict):
                    st = "error: %s" % short(run["error"].get("message"), 120)
                parts.append(("%s %s" % (st, ms)).strip())
            print("  • %-34s %s" % (short(name, 34), " | ".join(parts)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
