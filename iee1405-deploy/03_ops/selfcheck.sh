#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — خودآزمون بسته، پیش از هر استقرار
#
#   bash 03_ops/selfcheck.sh            # همه بررسی‌ها
#   bash 03_ops/selfcheck.sh --quick    # فقط نحو و کامپایل (بدون دیتابیس)
#
# چه چیزی را می‌سنجد؟
#   ۱. نحو همه اسکریپت‌های bash (bash -n)
#   ۲. کامپایل همه فایل‌های پایتون (بدون اجرا)
#   ۳. نبود رمز و توکن در فایل‌های بسته
#   ۴. سه آزمون دیتابیسی — فقط اگر کلاستر آزمایشی در دسترس باشد
#   ۵. آزمون پذیرش جعبه‌ابزار میدانی (بدون دیتابیس، همیشه)
#
# چرا؟ پیش از این، «آیا همه‌چیز سالم است؟» چهار دستور جداگانه در README بود و
# کسی نمی‌دانست کدام‌ها روی سرور اجرا می‌شوند و کدام‌ها روی لپ‌تاپ. این اسکریپت
# فقط **می‌خواند** و هیچ چیزی را تغییر نمی‌دهد؛ روی VPS هم بی‌خطر است.
#
# کد خروج: ۰ = سالم · ۱ = خطا · ۲ = خطا فقط در آزمون‌های دیتابیسی
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
T="$(dirname "$ROOT")/iee1405-field-toolkit"      # جعبه‌ابزار میدانی، کنار بسته
PY="${PYTHON:-python3}"
QUICK=0
[[ "${1:-}" == "--quick" ]] && QUICK=1

FAIL=0
DBFAIL=0

c_ok()   { printf '  \033[32m✅\033[0m %s\n' "$*"; }
c_bad()  { printf '  \033[31m❌\033[0m %s\n' "$*"; FAIL=1; }
c_warn() { printf '  \033[33m⚠️ \033[0m %s\n' "$*"; }
c_head() { printf '\n\033[1m%s\033[0m\n' "$*"; }

printf '\n\033[1m خودآزمون بسته استقرار IEE 1405\033[0m\n'
printf ' پوشه: %s\n' "$ROOT"

# ── ۱) نحو bash ───────────────────────────────────────────────────────
c_head "۱) نحو اسکریپت‌های bash"
N=0
while IFS= read -r f; do
    N=$((N + 1))
    if ! bash -n "$f" 2>/tmp/iee_sc_err; then
        c_bad "$(basename "$f"): $(head -2 /tmp/iee_sc_err | tr '\n' ' ')"
    fi
done < <(find "$ROOT" -name '*.sh' -type f | sort)
[[ "$FAIL" == "0" ]] && c_ok "$N اسکریپت، بدون خطای نحو"

# ── ۲) کامپایل پایتون ─────────────────────────────────────────────────
c_head "۲) کامپایل فایل‌های پایتون"
PYFAIL=0
while IFS= read -r f; do
    if ! "$PY" -c 'import sys,py_compile; py_compile.compile(sys.argv[1], doraise=True)' "$f" \
            >/tmp/iee_sc_err 2>&1; then
        c_bad "$(basename "$f")"
        head -3 /tmp/iee_sc_err | sed 's/^/     /'
        PYFAIL=1
    fi
done < <(find "$ROOT" -name '*.py' -type f | sort)
[[ "$PYFAIL" == "0" ]] || FAIL=1
if [[ -d "$T" ]]; then
    while IFS= read -r f; do
        if ! "$PY" -c 'import sys,py_compile; py_compile.compile(sys.argv[1], doraise=True)' "$f" \
                >/dev/null 2>&1; then
            c_bad "جعبه‌ابزار: $(basename "$f")"; FAIL=1; PYFAIL=1
        fi
    done < <(find "$T" -maxdepth 1 -name '*.py' -type f | sort)
fi
[[ "$PYFAIL" == "0" ]] && c_ok "همه فایل‌ها کامپایل شدند"

# ── ۳) جست‌وجوی رمز ──────────────────────────────────────────────────
c_head "۳) نبود رمز و توکن"
# الگوها فقط شناسایی می‌کنند؛ چیزی چاپ نمی‌شود که خودش راز باشد.
HITS="$(grep -rnE '[0-9]{8,10}:[A-Za-z0-9_-]{30,}|postgres(ql)?://[^ "]+:[^ "@]+@' \
        --include='*.py' --include='*.sh' --include='*.json' --include='*.yml' \
        "$ROOT" 2>/dev/null | grep -v 'SECRET_PATTERNS\|re.compile\|testenv\|selfcheck' || true)"
if [[ -n "$HITS" ]]; then
    c_bad "الگوی رمز پیدا شد:"
    printf '%s\n' "$HITS" | sed 's/^/     /' | head -5
else
    c_ok "هیچ توکن یا رشته اتصال رمزدار در فایل‌ها نیست"
fi

if [[ "$QUICK" == "1" ]]; then
    c_head "حالت --quick: آزمون‌های دیتابیسی رد شد"
else
    # ── ۴) آزمون‌های دیتابیسی (اگر کلاستر آزمایشی در دسترس باشد) ──────
    c_head "۴) آزمون‌های دیتابیسی"
    if "$PY" "$HERE/testenv.py" >/tmp/iee_sc_env 2>&1; then
        sed -n '1,2p' /tmp/iee_sc_env | sed 's/^/  /'
        echo ""
        for pair in "02_n8n/validate_workflows.py|اعتبارسنجی گردش‌کارها" \
                    "03_ops/test_workflow_e2e.py|آزمون سرتاسری ربات" \
                    "03_ops/test_import.py|آزمون زنجیره اکسل → ایمپورت"; do
            script="${pair%%|*}"; label="${pair##*|}"
            out="$("$PY" "$ROOT/$script" 2>&1)"
            if [[ $? -eq 0 ]]; then
                c_ok "$label — $(printf '%s\n' "$out" | tail -1)"
            else
                c_bad "$label"
                printf '%s\n' "$out" | tail -5 | sed 's/^/     /'
                DBFAIL=1
            fi
        done
    else
        c_warn "کلاستر آزمایشی در دسترس نیست — سه آزمون دیتابیسی رد شد"
        sed -n '2,4p' /tmp/iee_sc_env | sed 's/^/     /'
        printf '     راهنما: pip install pgserver   یا   export IEE_TEST_PG_BIN / IEE_TEST_PG_URI\n'
    fi
fi

# ── ۵) جعبه‌ابزار میدانی ─────────────────────────────────────────────
c_head "۵) جعبه‌ابزار میدانی (بدون دیتابیس)"
if [[ -f "$T/test_toolkit.py" ]]; then
    out="$("$PY" "$T/test_toolkit.py" 2>&1)"
    if [[ $? -eq 0 ]]; then
        c_ok "$(printf '%s\n' "$out" | grep -E 'نتیجه|موفق' | tail -1)"
    else
        c_bad "آزمون جعبه‌ابزار شکست خورد"
        printf '%s\n' "$out" | tail -6 | sed 's/^/     /'
    fi
else
    c_warn "پوشه جعبه‌ابزار کنار بسته نیست ($T) — رد شد"
fi

# ── نتیجه ────────────────────────────────────────────────────────────
c_head "نتیجه"
if [[ "$FAIL" != "0" ]]; then
    c_bad "خطا در بررسی‌های پایه — پیش از استقرار رفع شود"
    exit 1
fi
if [[ "$DBFAIL" != "0" ]]; then
    c_bad "همه بررسی‌های پایه سالم‌اند، اما آزمون دیتابیسی ناموفق بود"
    exit 2
fi
c_ok "همه بررسی‌ها سالم"
printf '  گام بعدی: bash 03_ops/preflight.sh   (سپس بخش ۰ README)\n\n'
