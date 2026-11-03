#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — جست‌وجوی شرکت از خط فرمان (میان‌بر «/find» در بله)
#
#   bash 03_ops/search_hint.sh ترانسفو
#   bash 03_ops/search_hint.sh 38-12
#   bash 03_ops/search_hint.sh --limit 20 کابل
#
# چرا لازم است؟ پس از ایمپورت فهرست غرفه‌داران، فهرست شرکت‌ها بسیار بزرگ‌تر
# از چهار روز نمایشگاه است. برای پیدا کردن کد یک شرکت (ORG-…) بدون باز کردن
# بله — مثلاً وقتی گوشی در دست نیست — همین اسکریپت همان تابعی را صدا می‌زند
# که ربات صدا می‌زند: `iee1405.search_orgs()`. پس نتیجه دقیقاً همان چیزی است
# که `/find` برمی‌گرداند؛ دو مسیر جداگانه و دو نتیجه متفاوت وجود ندارد.
#
# فقط می‌خواند؛ هیچ چیزی نمی‌نویسد.
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_common.sh
source "$HERE/lib_common.sh"

LIMIT=12
QUERY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --limit) LIMIT="${2:-12}"; shift 2 ;;
        -h|--help)
            sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) QUERY="${QUERY:+$QUERY }$1"; shift ;;
    esac
done

if [[ -z "${QUERY// /}" ]]; then
    c_bad "عبارت جست‌وجو خالی است"
    c_hint "bash 03_ops/search_hint.sh ترانسفو    # یا شماره غرفه: 38-12"
    exit 2
fi

if ! [[ "$LIMIT" =~ ^[0-9]+$ ]] || (( LIMIT < 1 || LIMIT > 200 )); then
    c_bad "مقدار --limit باید بین ۱ و ۲۰۰ باشد"
    exit 2
fi

dk_detect || { c_bad "docker در دسترس نیست"; exit 1; }
ct_detect >/dev/null 2>&1 || { c_bad "کانتینر PostgreSQL پیدا نشد"; exit 1; }

# نقل‌قول تک‌کوتیشن برای SQL: ' → ''
Q="${QUERY//\'/\'\'}"

c_head "جست‌وجو: «$QUERY»"

ROWS="$(pgq "$PG_DB" -c "SELECT code || E'\t' || legal_name || E'\t' || coalesce(booth, '')
                          FROM iee1405.search_orgs('$Q', $LIMIT)" 2>&1)"

if [[ -z "${ROWS// /}" ]]; then
    c_bad "چیزی پیدا نشد"
    c_hint "بخشی از نام را امتحان کنید؛ نیم‌فاصله و ی/ک عربی خودکار یکسان می‌شوند."
    exit 1
fi

if grep -qi "ERROR\|does not exist" <<<"$ROWS"; then
    c_bad "جست‌وجو اجرا نشد"
    printf '%s\n' "$ROWS" | head -3
    c_hint "اول: bash 03_ops/deploy_sql.sh   (تابع iee1405.search_orgs را می‌سازد)"
    exit 1
fi

printf '  %-14s %-46s %s\n' "کد" "نام شرکت" "غرفه"
printf '  %s\n' "──────────────────────────────────────────────────────────────────────────"
COUNT=0
while IFS=$'\t' read -r code name booth; do
    [[ -z "${code// /}" ]] && continue
    COUNT=$((COUNT + 1))
    printf '  %-14s %-46.46s %s\n' "$code" "$name" "${booth:-—}"
done <<<"$ROWS"

printf '  %s\n' "──────────────────────────────────────────────────────────────────────────"
printf '  %d نتیجه (سقف %d)\n\n' "$COUNT" "$LIMIT"

if (( COUNT >= LIMIT )); then
    c_hint "به سقف رسید — با --limit بیشتر یا عبارت دقیق‌تر جست‌وجو کنید."
fi

c_head "گام بعدی"
printf '  در بله:  /org <کد>      پرونده کامل شرکت\n'
printf '           /log <کد> | خلاصه | اقدام بعدی\n'
printf '  از اینجا: bash 03_ops/inspect_state.sh     سلامت ربات\n'
