#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — «بافت یک شرکت» برای ساختن سؤال اختصاصی با هوش مصنوعی
#
# چرا این اسکریپت؟ کوئری بلندِ چندخطی، دو بار در چت و ترمینال شکست:
#   • در چت، نقطه‌دارهایی مثل c.id و c.name_fa به پیوند تبدیل شدند
#   • روی سرور، پیام «column c.activity does not exist» داد چون SQL نسخهٔ
#     ۰.۱.۴۰ هنوز اعمال نشده بود
# هر دو با یک دستور کوتاه و پیام خطای صریح حل می‌شود.
#
#   bash 03_ops/prompt_company.sh "ایران ترانسفو"     # جست‌وجو با بخشی از نام
#   bash 03_ops/prompt_company.sh --id 12              # شناسهٔ دقیق
#   bash 03_ops/prompt_company.sh --id 12 --prompt     # + متن آمادهٔ درخواست به هوش مصنوعی
#   bash 03_ops/prompt_company.sh --id 12 --json       # فقط JSON (برای لوله‌کردن)
#   bash 03_ops/prompt_company.sh --list 5             # ۵ شرکت اول با شناسه
#   bash 03_ops/prompt_company.sh --questions --id 12  # سؤال‌های همان شرکت، همان‌طور که ربات می‌پرسد
#
# فقط می‌خواند؛ هیچ چیزی نمی‌نویسد.
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/03_ops/lib_common.sh"

PG_DB="${PG_DB:-xennic}"

if [[ -n "${PG_DIRECT_PSQL:-}" ]]; then
    dk_detect() { return 0; }
    ct_detect() { return 0; }
    pg_user_detect() { PG_USER="${PG_USER:-postgres}"; }
    pgq()        { local db="$1"; shift; $PG_DIRECT_PSQL -X -t -A -d "$db" "$@"; }
    pgq_pretty() { local db="$1"; shift; $PG_DIRECT_PSQL -X -P pager=off -d "$db" "$@"; }
fi

bad()  { c_bad "$1"; [[ $# -gt 1 ]] && c_hint "$2"; exit 1; }

# ── ۰) پیش‌نیاز ───────────────────────────────────────────────────────
dk_detect || bad "docker پیدا نشد" "این اسکریپت باید روی خودِ سرور اجرا شود"
ct_detect || bad "کانتینر PostgreSQL بالا نیست" "docker ps را ببینید"
pg_user_detect >/dev/null 2>&1 || true

HAS_SCHEMA="$(pgq "$PG_DB" -c "SELECT count(*) FROM pg_namespace WHERE nspname = 'barghpa'" 2>/dev/null | tail -1)"
if [[ "${HAS_SCHEMA:-0}" != "1" ]]; then
    bad "آینهٔ فهرست نمایشگاه ساخته نشده (schema barghpa نیست)" \
        "bash 03_ops/deploy_sql.sh   و سپس   bash 03_ops/load_exhibitors.sh"
fi

# ستون activity از v0.1.40 آمده؛ اگر نباشد، پیام خطای خودِ پایگاه («column
# c.activity does not exist») گمراه‌کننده است: به‌نظر می‌رسد کوئری غلط است،
# در حالی که SQL نسخهٔ تازه اعمال نشده.
HAS_COL="$(pgq "$PG_DB" -c "SELECT count(*) FROM information_schema.columns
                             WHERE table_schema = 'barghpa' AND table_name = 'company'
                               AND column_name = 'activity'" 2>/dev/null | tail -1)"
if [[ "${HAS_COL:-0}" != "1" ]]; then
    bad "ستون «حوزه فعالیت» در آینه نیست — SQL نسخهٔ ۰.۱.۴۰ اعمال نشده" \
        "cd ~/ZNNY-Xennic-Vault/iee1405-deploy && bash 03_ops/deploy_sql.sh"
fi

# ── ۱) ورودی ──────────────────────────────────────────────────────────
MODE="name"; TERM=""; CID="0"; LIMIT="3"; PROMPT=0; JSON_ONLY=0
args=("$@")
if [[ ${#args[@]} -eq 0 ]]; then
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
fi
while [[ ${#args[@]} -gt 0 ]]; do
    case "${args[0]}" in
        --id)     CID="${args[1]:-0}"
                  [[ "$MODE" == "questions" ]] || MODE="id"
                  args=("${args[@]:2}") ;;
        --list)   MODE="list"; LIMIT="${args[1]:-5}"; args=("${args[@]:2}") ;;
        --questions) MODE="questions"; args=("${args[@]:1}") ;;
        --limit)  LIMIT="${args[1]:-3}";             args=("${args[@]:2}") ;;
        --prompt) PROMPT=1;   args=("${args[@]:1}") ;;
        --json)   JSON_ONLY=1; args=("${args[@]:1}") ;;
        -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)        TERM="${args[0]}"; args=("${args[@]:1}") ;;
    esac
done

if [[ "$MODE" == "id" && ! "$CID" =~ ^[0-9]+$ ]]; then
    bad "شناسهٔ شرکت عددی نیست: $CID" "مثال: bash 03_ops/prompt_company.sh --id 12"
fi

# ── ۲) خروجی: برای هر شرکت یک شیء JSON ────────────────────────────────
run_ctx() {
    pgq "$PG_DB" -q -v ON_ERROR_STOP=1 \
        -v name="$TERM" -v cid="$CID" -v n="$LIMIT" <<'SQL'
WITH co AS (
    SELECT c.id,
           c.name_fa,
           c.activity,
           (SELECT string_agg(DISTINCT p.hall, '، ')
              FROM barghpa.participation p WHERE p.company_id = c.id) AS halls,
           (SELECT string_agg(DISTINCT f.flag, ',')
              FROM barghpa.company_flag f WHERE f.company_id = c.id) AS flags,
           (SELECT pi.first_check FROM barghpa.pilot pi
             WHERE pi.company_id = c.id) AS pilot_check
      FROM barghpa.company c
     WHERE (:'cid'::bigint > 0 AND c.id = :'cid'::bigint)
        OR (:'cid'::bigint = 0 AND c.name_fa ILIKE '%' || :'name' || '%')
     ORDER BY c.id
     LIMIT :'n'::int
)
SELECT jsonb_pretty(jsonb_build_object(
           'id',          co.id,
           'name',        co.name_fa,
           'activity',    co.activity,
           'halls',       co.halls,
           'flags',       co.flags,
           'pilot_check', co.pilot_check))
  FROM co;
SQL
}

if [[ "$MODE" == "questions" ]]; then
    [[ "$CID" =~ ^[0-9]+$ ]] || bad "برای --questions شناسه لازم است" \
        "bash 03_ops/prompt_company.sh --questions --id 12"
    HAS_IV="$(pgq "$PG_DB" -c "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                                WHERE n.nspname = 'iee1405' AND p.proname = 'iv_questions'" | tail -1)"
    [[ "${HAS_IV:-0}" == "1" ]] || bad "تابع سؤال‌های مصاحبه نصب نشده" \
        "bash 03_ops/deploy_sql.sh   (01_sql/10_interview.sql)"
    pgq_pretty "$PG_DB" -q -v ON_ERROR_STOP=1 -v cid="$CID" <<'SQL'
SELECT ord, code, q FROM iee1405.iv_questions(:'cid'::bigint) ORDER BY ord;
SQL
    exit 0
fi

if [[ "$MODE" == "list" ]]; then
    pgq_pretty "$PG_DB" -q -c "SELECT id, left(coalesce(name_fa,''), 48) AS نام,
                                      left(coalesce(activity,'—'), 30) AS حوزه_فعالیت
                                 FROM barghpa.company ORDER BY id LIMIT ${LIMIT};"
    exit 0
fi

DATA="$(run_ctx)"
if [[ -z "$DATA" ]]; then
    bad "شرکتی با این مشخصات در آینه نیست" "با «--list 10» فهرست را ببینید؛ نام ممکن است با فاصله/ي عربی نوشته شده باشد"
fi

if [[ $JSON_ONLY -eq 1 ]]; then
    printf '%s\n' "$DATA"
    exit 0
fi

echo "════════════════════════════════════════════════"
echo " بافت شرکت (آینهٔ barghpa)"
echo "════════════════════════════════════════════════"
printf '%s\n' "$DATA"

if [[ $PROMPT -eq 0 ]]; then
    cat <<'TIP'

این متن را با درخواست زیر به هوش مصنوعی بدهید (یا با --prompt بگیرید):
  bash 03_ops/prompt_company.sh --id <id> --prompt
TIP
    exit 0
fi

cat <<'PROMPT'
────────────────────────────────────────────────
این درخواست را همراه با JSON بالا به هوش مصنوعی بدهید:

تو دستیار یک تیم فروش B2B در صنعت برق هستی. ما در نمایشگاه بین‌المللی برق
۱۶ تا ۱۹ آبان ۱۴۰۵ از این شرکت بازدید می‌کنیم و می‌خواهیم در ۲ تا ۳ دقیقه
گفت‌وگو، اطلاعاتی بگیریم که در فهرست نمایشگاه نیست.

داده‌ای که از آینه داریم (تنها منبع مجاز):
<JSON بالا>

قواعد:
۱. حداکثر ۳ سؤال، هر کدام حداکثر ۲۵ کلمه، فارسی محاوره‌ای مؤدبانه.
۲. سؤال باید از دادهٔ بالا یا از صنعت برق برآید؛ هیچ عدد، نام مشتری،
   غرفه یا قراردادی نساز. اگر داده کم است، سؤال عمومی بپرس.
۳. سؤال قیمت، تخفیف، لیست مشتری و اطلاعات محرمانه نپرس.
۴. هر سؤال باید با «بله/خیر» یا یک جملهٔ کوتاه پاسخ‌پذیر باشد.
۵. خروجی را فقط به شکل JSON بده:
   [{"company_ref": <id>, "question": "..."}]
────────────────────────────────────────────────
بعد از گرفتن پاسخ، همین را اجرا کنید (JSON را جای [...] بگذارید):

  docker compose -f ~/xennic-infra/docker-compose.yml exec -T postgres \
    psql -U n8n -d xennic -c "
    WITH ai AS (
      SELECT * FROM jsonb_to_recordset('[...]'::jsonb)
             AS x(company_ref bigint, question text)
    )
    INSERT INTO iee1405.iv_company_q (company_ref, question, source)
    SELECT company_ref, question, 'ai' FROM ai
    ON CONFLICT (company_ref, question) DO NOTHING;"

و بازبینی سؤال‌های همان شرکت، پیش از رفتن سرِ غرفه:
  bash 03_ops/prompt_company.sh --questions --id <id>
PROMPT
