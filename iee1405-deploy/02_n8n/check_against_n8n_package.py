#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — اعتبارسنجی گردش‌کارها در برابر نسخه واقعی n8n
#
# چرا این اسکریپت جدا از validate_workflows.py است؟
#   آن یکی فایل‌ها را با «دانش من از نسخه‌ها» می‌سنجد؛ این یکی
#   بسته نصب‌شده n8n-nodes-base (همان نسخه‌ای که n8n استفاده می‌کند) را
#   پارس می‌کند و می‌گوید هر گره و هر typeVersion واقعاً وجود دارد یا نه.
#
# اجرا:
#   python3 02_n8n/check_against_n8n_package.py [--package-dir DIR]
#   npm pack n8n-nodes-base@<version> && tar xzf *.tgz   # اگر بسته نیست
# ═══════════════════════════════════════════════════════════════════════
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).parent
DEFAULT_PKG = pathlib.Path("/tmp/n8n2/package")

# نام نود در n8n → مسیر فایل توصیف‌گر در بسته
NODE_FILES = {
    "n8n-nodes-base.postgres": "nodes/Postgres/Postgres.node.js",
    "n8n-nodes-base.scheduleTrigger": "nodes/Schedule/ScheduleTrigger.node.js",
    "n8n-nodes-base.httpRequest": "nodes/HttpRequest/HttpRequest.node.js",
    "n8n-nodes-base.splitOut": "nodes/Transform/SplitOut/SplitOut.node.js",
    "n8n-nodes-base.if": "nodes/If/If.node.js",
    "n8n-nodes-base.noOp": "nodes/NoOp/NoOp.node.js",
}


def supported_versions(path: pathlib.Path):
    """نسخه‌های پشتیبانی‌شده را از فایل نود استخراج می‌کند.

    دو حالت وجود دارد:
      • نسخه‌ی تنها:   version: [1, 1.1, 1.2]   یا  version: 1
      • نسخه‌ی پیش‌فرض + نگاشت:  defaultVersion: 2.7  و  nodeVersions = { ... }
    """
    src = path.read_text(encoding="utf-8", errors="replace")

    # حالت VersionedNodeType: کلیدهای عددی داخل nodeVersions
    m = re.search(r"nodeVersions\s*=\s*\{(.*?)\};", src, re.S)
    if m:
        keys = re.findall(r"^\s*([0-9]+(?:\.[0-9]+)?)\s*:", m.group(1), re.M)
        if keys:
            return sorted({float(k) for k in keys})

    m = re.search(r"version\s*:\s*\[([^\]]*)\]", src)
    if m:
        return sorted({float(x) for x in re.findall(r"[0-9]+(?:\.[0-9]+)?", m.group(1))})

    m = re.search(r"version\s*:\s*([0-9]+(?:\.[0-9]+)?)", src)
    if m:
        return [float(m.group(1))]
    return []


def main():
    pkg = DEFAULT_PKG
    if "--package-dir" in sys.argv:
        pkg = pathlib.Path(sys.argv[sys.argv.index("--package-dir") + 1])
    if not (pkg / "dist").is_dir():
        print(f"⚠️ بسته n8n-nodes-base در {pkg} نیست — بررسی نسخه‌ها انجام نشد")
        print("   برای اجرا:  npm pack n8n-nodes-base@<version>  سپس tar xzf")
        return 0

    pkg_json = json.loads((pkg / "package.json").read_text(encoding="utf-8"))
    print(f"بسته: n8n-nodes-base@{pkg_json.get('version')}")

    errors = []
    seen = {}
    for f in sorted(HERE.glob("wf-*.json")):
        wf = json.loads(f.read_text(encoding="utf-8"))
        for n in wf["nodes"]:
            t = n["type"]
            tv = n["typeVersion"]
            rel = NODE_FILES.get(t)
            if not rel:
                errors.append(f"{f.name}: نوع ناشناخته {t}")
                continue
            path = pkg / "dist" / rel
            if not path.is_file():
                errors.append(f"{f.name}: فایل نود {rel} در بسته نیست")
                continue
            sup = supported_versions(path)
            seen[(t, tv)] = sup
            if tv not in sup:
                errors.append(
                    f"{f.name} → «{n['name']}»: typeVersion {tv} پشتیبانی نمی‌شود "
                    f"(پشتیبانی‌شده: {', '.join(str(int(x)) if x == int(x) else str(x) for x in sup)})")

    print("\nگره‌های استفاده‌شده و نسخه‌های مجاز در این بسته:")
    for (t, tv), sup in sorted(seen.items()):
        sup_s = ", ".join(str(int(x)) if x == int(x) else str(x) for x in sup)
        mark = "✅" if tv in sup else "❌"
        print(f"  {mark} {t}@{tv}   (مجاز: {sup_s})")

    if errors:
        print("\n❌ خطاها:")
        for e in errors:
            print("  -", e)
        return 1
    print("\n✅ همه گره‌ها و نسخه‌ها در این بسته n8n معتبرند")
    return 0


if __name__ == "__main__":
    sys.exit(main())
