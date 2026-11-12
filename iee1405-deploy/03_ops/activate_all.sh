#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — ساخت اعتبارنامه و فعال‌سازی گردش‌کارها
#
# اجرا:
#   bash 03_ops/activate_all.sh
#
# چرا یک اسکریپت جدا؟
#   ایمپورت گردش‌کار، خودش کافی نیست. سه چیز باید درست انجام شود:
#     ۱. اعتبارنامه PostgreSQL در n8n وجود داشته باشد — وگرنه هر گره با
#        «credential not found» شکست می‌خورد.
#     ۲. گردش‌کار «منتشر» شود. در n8n نسخه ۲، دستور قدیمی
#        «update:workflow --active=true» منسوخ است و به publish:workflow
#        منتقل شده؛ استفاده از دستور قدیمی فقط هشدار می‌دهد.
#     ۳. n8n باید ری‌استارت شود. خود CLI هشدار می‌دهد:
#        «تغییرات تا زمانی که n8n در حال اجراست اثر نمی‌کند».
#
# اجرای دوباره بی‌خطر است (idempotent).
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib_common.sh"

CRED_ID="XENNIC-PG-CREDENTIAL"
CRED_NAME="Xennic PostgreSQL"
PASS_FILE="$HOME/.iee1405-app-password"

if ! dk_detect || ! ct_detect; then
    c_bad "Docker یا کانتینر n8n پیدا نشد"
    exit 1
fi
if [[ -z "${N8N_CT:-}" ]]; then
    c_bad "کانتینر n8n در حال اجرا نیست"
    c_hint "cd $INFRA_DIR && docker compose up -d n8n"
    exit 1
fi

# </dev/null حیاتی است: docker exec -i وگرنه stdin فراخوان (مثلاً حلقه read) را می‌خورد
n8n() { $DK exec -i "$N8N_CT" n8n "$@" </dev/null; }

c_head "۰) میزبان دیتابیس از دید n8n"
# نام سرویس در compose ممکن است «postgres» نباشد؛ به‌جای حدس، اتصال واقعی
# TCP از داخل خودِ کانتینر n8n آزموده می‌شود. هر نامی که جواب داد، همان در
# کارت اعتبارنامه نوشته می‌شود.
probe_host() {
    $DK exec -i "$N8N_CT" node -e '
const net = require("net");
const host = process.argv[1];
const s = net.connect(5432, host);
s.setTimeout(4000);
s.on("connect", () => { console.log("OK"); s.destroy(); process.exit(0); });
s.on("timeout", () => { s.destroy(); console.log("TIMEOUT"); process.exit(1); });
s.on("error", (e) => { console.log("ERR " + (e.code || e.message)); process.exit(1); });
' "$1" 2>&1 | tail -1
}

CRED_HOST="${PG_HOST:-}"
if [[ -n "$CRED_HOST" ]]; then
    R="$(probe_host "$CRED_HOST")"
    [[ "$R" == "OK" ]] && c_ok "میزبان تعیین‌شده PG_HOST=$CRED_HOST وصل شد" \
        || { c_warn "PG_HOST=$CRED_HOST وصل نشد ($R) — خودکار انتخاب می‌شود"; CRED_HOST=""; }
fi
if [[ -z "$CRED_HOST" ]]; then
    for cand in postgres "$PG_SERVICE" "$PG_CT"; do
        [[ -z "$cand" ]] && continue
        R="$(probe_host "$cand")"
        if [[ "$R" == "OK" ]]; then
            CRED_HOST="$cand"
            c_ok "میزبان دیتابیس برای کارت اعتبارنامه: $cand"
            break
        else
            c_hint "«$cand» وصل نشد ($R)"
        fi
    done
fi
if [[ -z "$CRED_HOST" ]]; then
    c_bad "هیچ‌یک از نام‌های دیتابیس از داخل n8n قابل دسترس نبود"
    c_hint "نام سرویس را ببینید: cd $INFRA_DIR && docker compose config --services"
    c_hint "سپس: PG_HOST=<نام سرویس> bash 03_ops/activate_all.sh"
    exit 1
fi

c_head "۱) اعتبارنامه PostgreSQL"

FORCE_CRED=0
if [[ -f "$PASS_FILE" ]]; then
    APP_PASS="$(tr -d '\r\n' < "$PASS_FILE")"
fi

# خودترمیمی: اگر فایل رمز نیست، رمز تازه ساخته و در دیتابیس تنظیم می‌شود.
# (بی‌این‌که این کار انجام شود، هر گره PostgreSQL با «password authentication
#  failed» شکست می‌خورد و هیچ پیامی در bot_state نوشته نمی‌شود.)
if [[ -z "${APP_PASS:-}" || ! -f "$PASS_FILE" ]]; then
    c_warn "فایل رمز برنامه پیدا نشد — رمز تازه ساخته می‌شود"
    APP_PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)"
    if pgq "$PG_DB" -v ON_ERROR_STOP=1 -v app_password="$APP_PASS" -f - \
            < "$HERE/../01_sql/06_roles.sql" >/dev/null 2>/tmp/iee_roles.err; then
        mkdir -p "$(dirname "$PASS_FILE")"
        if printf '%s' "$APP_PASS" > "$PASS_FILE" 2>/dev/null && chmod 600 "$PASS_FILE"; then
            c_ok "رمز تازه تنظیم شد و در $PASS_FILE ذخیره شد"
        else
            c_bad "نوشتن فایل رمز ناموفق بود: $PASS_FILE"
            c_hint "دسترسی پوشه خانه را بررسی کنید؛ رمز در دیتابیس تنظیم شد اما ذخیره نشد"
            exit 1
        fi
    else
        c_bad "تنظیم رمز نقش ناموفق بود"
        grep -m3 ERROR /tmp/iee_roles.err | sed 's/^/     /'
        exit 1
    fi
else
    c_ok "رمز برنامه از $PASS_FILE خوانده شد"
    if pgq "$PG_DB" -v ON_ERROR_STOP=1 -v app_password="$APP_PASS" -f - \
            < "$HERE/../01_sql/06_roles.sql" >/dev/null 2>/tmp/iee_roles.err; then
        c_ok "رمز نقش‌های دیتابیس با فایل رمز هم‌تراز شد"
    else
        c_warn "هم‌تراز کردن رمز نقش‌ها ناموفق بود (کارت اعتبارنامه ممکن است رمز قدیمی داشته باشد)"
        grep -m3 ERROR /tmp/iee_roles.err | sed 's/^/     /'
    fi
fi
FORCE_CRED=1   # کارت اعتبارنامه همیشه از همین رمز بازسازی می‌شود (idempotent)
[[ -z "${APP_PASS:-}" ]] && { c_bad "رمز خالی است"; exit 1; }

# بررسی وجود اعتبارنامه (export بدون رمز، فقط برای دیدن نام‌ها)
HAVE_CRED=0
if [[ "$FORCE_CRED" == "0" ]] && n8n export:credentials --all --output=/tmp/cred-check.json --decrypted=false >/dev/null 2>&1; then
    if $DK exec -i "$N8N_CT" sh -c 'cat /tmp/cred-check.json' 2>/dev/null | grep -q "\"$CRED_NAME\""; then
        HAVE_CRED=1
    fi
    $DK exec -i "$N8N_CT" sh -c 'rm -f /tmp/cred-check.json' 2>/dev/null || true
fi

if [[ "$HAVE_CRED" == "1" ]]; then
    c_ok "اعتبارنامه «$CRED_NAME» از قبل وجود دارد"
else
    echo "  ساخت اعتبارنامه «$CRED_NAME» (id ثابت، مطابق ارجاع گردش‌کارها)"
    # فایل اعتبارنامه فقط داخل کانتینر و فقط برای چند لحظه وجود دارد
    N8N_CT="$N8N_CT" CRED_ID="$CRED_ID" CRED_NAME="$CRED_NAME" \
    DB_HOST="$CRED_HOST" DB_NAME="$PG_DB" DB_USER="iee_app" DB_PASS="$APP_PASS" \
    python3 -c '
import json, os
e = os.environ
cred = [{
    "id": e["CRED_ID"],
    "name": e["CRED_NAME"],
    "type": "postgres",
    "data": {
        "host": e["DB_HOST"],
        "database": e["DB_NAME"],
        "user": e["DB_USER"],
        "password": e["DB_PASS"],
        "port": 5432,
        "ssl": "disable",
        "maxConnections": 10
    }
}]
print(json.dumps(cred, ensure_ascii=False))
' | $DK exec -i "$N8N_CT" sh -c 'cat > /tmp/iee-cred.json && chmod 600 /tmp/iee-cred.json'

    if n8n import:credentials --input=/tmp/iee-cred.json 2>&1 | tee /tmp/iee-cred.out | grep -q "Successfully imported"; then
        c_ok "اعتبارنامه ساخته شد"
    else
        c_bad "ایمپورت اعتبارنامه ناموفق"
        tail -5 /tmp/iee-cred.out | sed 's/^/     /'
        $DK exec -i "$N8N_CT" sh -c 'rm -f /tmp/iee-cred.json' 2>/dev/null || true
        exit 1
    fi
    $DK exec -i "$N8N_CT" sh -c 'rm -f /tmp/iee-cred.json'
    c_ok "فایل موقت اعتبارنامه پاک شد"
fi

# تأیید از خود دیتابیس n8n (خروجی CLI تنها سند نیست)
N8N_DB="$($DK exec -i "$N8N_CT" printenv DB_POSTGRESDB_DATABASE 2>/dev/null | tr -d '\r\n')"
N8N_DB="${N8N_DB:-n8n}"
CRED_IN_DB="$(pgq "$N8N_DB" -c "SELECT count(*) FROM credentials_entity WHERE id = '$CRED_ID'" 2>/dev/null | tr -d '[:space:]')"
if [[ "$CRED_IN_DB" == "1" ]]; then
    c_ok "تأیید از دیتابیس n8n: کارت اعتبارنامه موجود است (میزبان: $CRED_HOST)"
elif [[ -n "$CRED_IN_DB" ]]; then
    c_warn "کارت اعتبارنامه در دیتابیس n8n دیده نشد (خروجی: $CRED_IN_DB)"
    c_hint "اگر گردش‌کار خطای credential داد: bash 03_ops/diagnose_n8n.sh"
fi

c_head "۱.۵) آزمون واقعی اتصال (قبل از انتشار)"
# آیا iee_app با همین رمز می‌تواند وارد شود؟ (خطای «password authentication failed»
# شایع‌ترین علت شکست گره‌های SQL است و هیچ اثری در bot_state نمی‌گذارد)
if $DK exec -e PGPASSWORD="$APP_PASS" -i "$PG_CT" psql -U iee_app -d "$PG_DB" -X -t -A \
        -c 'SELECT 1' 2>/dev/null | grep -q '^1$'; then
    c_ok "ورود iee_app به دیتابیس $PG_DB موفق بود"
else
    c_bad "ورود iee_app به دیتابیس $PG_DB ناموفق بود"
    c_hint "یعنی گره‌های PostgreSQL در n8n هم همین خطا را می‌گیرند"
    c_hint "bash 03_ops/deploy_sql.sh   # نقش‌ها و رمز را از نو تنظیم می‌کند"
fi

c_head "۲) انتشار گردش‌کارها (با شناسه ثابت)"

# چرا از CLI برای گرفتن شناسه استفاده نمی‌کنیم؟
#   «n8n list:workflow» در 2.44.7 فهرست کامل/قابل‌اتکا نمی‌دهد و هر ایمپورت
#   بدون شناسه ثابت، یک گردش‌کار تازه می‌سازد (همان تکراری‌های فعلی). پس
#   شناسه‌ها از فایل‌های خود مخزن خوانده و از دیتابیس n8n تأیید می‌شوند.
FIXED_IDS="$(python3 - "$HERE/../02_n8n" <<'PYEOF'
import glob, json, os, sys
d = sys.argv[1]
ids = []
for f in sorted(glob.glob(os.path.join(d, "wf-*.json"))):
    wf = json.load(open(f, encoding="utf-8"))
    if wf.get("id"):
        ids.append("%s|%s" % (wf["id"], wf["name"]))
print("\n".join(ids))
PYEOF
)"
if [[ -z "$FIXED_IDS" ]]; then
    c_bad "شناسه گردش‌کارها در فایل‌های 02_n8n پیدا نشد"
    exit 1
fi

# گردش‌کارهای تکراری (ایمپورت‌های قبلی) غیرفعال می‌شوند تا دو بار polling نکنند
STALE_SQL="SELECT string_agg(id, ' ') FROM workflow_entity
            WHERE name LIKE 'IEE1405%'
              AND id <> ALL (ARRAY[$(printf "'%s'," $(echo "$FIXED_IDS" | cut -d'|' -f1) | sed 's/,$//')])"
STALE="$(pgq "$N8N_DB" -c "$STALE_SQL" 2>/dev/null | tr -d '\r\n' | sed 's/[[:space:]]*$//')"
if [[ -n "$STALE" && "$STALE" != "" ]]; then
    pgq "$N8N_DB" -c "UPDATE workflow_entity SET active = false, \"activeVersionId\" = NULL
                       WHERE name LIKE 'IEE1405%'
                         AND id <> ALL (ARRAY[$(printf "'%s'," $(echo "$FIXED_IDS" | cut -d'|' -f1) | sed 's/,$//')])" >/dev/null 2>&1
    c_warn "گردش‌کارهای تکراری غیرفعال شدند (از ایمپورت‌های قبلی): $STALE"
    c_hint "پاک‌کردن نهایی: در n8n → Workflows → گردش‌کارهای IEE1405 بدون تیک Active را حذف کنید"
fi

COUNT=0
while IFS='|' read -r wid wname <&3; do
    [[ -z "${wid:-}" ]] && continue
    EXISTS="$(pgq "$N8N_DB" -c "SELECT count(*) FROM workflow_entity WHERE id = '$wid'" 2>/dev/null | tr -d '[:space:]')"
    if [[ "$EXISTS" != "1" ]]; then
        c_bad "$wname ($wid) در n8n نیست"
        c_hint "bash 03_ops/import_workflows.sh import"
        continue
    fi
    printf '  → %s (%s) ' "$wname" "$wid"
    if n8n publish:workflow --id="$wid" >/tmp/iee_pub.log 2>&1; then
        echo "✅ منتشر شد"
        COUNT=$((COUNT + 1))
    else
        echo "❌"
        tail -3 /tmp/iee_pub.log | sed 's/^/     /'
    fi
done 3<<< "$FIXED_IDS"

if [[ "$COUNT" == "0" ]]; then
    c_bad "هیچ گردش‌کاری منتشر نشد"
    exit 1
fi
c_ok "$COUNT گردش‌کار منتشر شد"

c_head "۲.۵) بستن اجراهای مرده"
# ردیف‌های running قدیمی فقط گزارش را قرمز می‌کنند و شمارش خطا را بالا می‌برند.
# همان کاری انجام می‌شود که n8n در crash-recovery می‌کند: running → crashed.
if [[ -x "$HERE/clean_executions.sh" || -f "$HERE/clean_executions.sh" ]]; then
    bash "$HERE/clean_executions.sh" 2>&1 | grep -E "✅|⚠️|❌" | sed 's/^/  /'
fi

c_head "۳) ری‌استارت n8n (لازم است تا انتشار اثر کند)"
if ( cd "$INFRA_DIR" && docker compose restart "$N8N_SERVICE" >/dev/null 2>&1 ); then
    c_ok "n8n ری‌استارت شد"
else
    c_warn "ری‌استارت با compose انجام نشد؛ تلاش با docker restart"
    $DK restart "$N8N_CT" >/dev/null 2>&1 && c_ok "n8n ری‌استارت شد" || c_bad "ری‌استارت ناموفق"
fi

echo "→ انتظار برای بالا آمدن n8n"
for i in $(seq 1 30); do
    if $DK exec -i "$N8N_CT" n8n --version >/dev/null 2>&1; then break; fi
    sleep 2
done
sleep 5
c_ok "n8n پاسخ می‌دهد"

c_head "۴) تأیید فعال بودن"
ACTIVE="$(pgq "$N8N_DB" -c "SELECT count(*) FROM workflow_entity
                               WHERE name LIKE 'IEE1405%'
                                 AND active AND \"activeVersionId\" IS NOT NULL" 2>/dev/null | tr -d '[:space:]')"
printf '  گردش‌کارهای فعال IEE1405: %s (انتظار: %s)\n' "${ACTIVE:-0}" "$COUNT"
if [[ "${ACTIVE:-0}" -ge "$COUNT" ]]; then
    c_ok "همه گردش‌کارها فعال هستند"
else
    c_warn "برخی گردش‌کارها فعال نشدند — در رابط n8n دکمه Active را بزنید"
    c_hint "http://127.0.0.1:5678 (از طریق تونل SSH)"
fi

c_head "۵) تأیید واقعی: آیا گردش‌کار به PostgreSQL وصل شده؟"
# اگر WF-01 در حال اجرا باشد، هر ۲۰ ثانیه last_poll_at را به‌روز می‌کند
BEFORE="$(pgq "$PG_DB" -c "SELECT coalesce(value,'-') FROM iee1405.bot_state WHERE key='last_poll_at'" 2>/dev/null | tr -d '[:space:]')"
echo "  انتظار ۳۰ ثانیه برای یک دور اجرای گردش‌کار..."
sleep 30
AFTER="$(pgq "$PG_DB" -c "SELECT coalesce(value,'-') FROM iee1405.bot_state WHERE key='last_poll_at'" 2>/dev/null | tr -d '[:space:]')"

if [[ "$AFTER" != "-" && "$AFTER" != "$BEFORE" ]]; then
    c_ok "گردش‌کار در حال اجراست (last_poll_at به‌روز شد)"
elif [[ "$AFTER" != "-" ]]; then
    c_warn "last_poll_at ثبت شده اما تازه نشد — ممکن است اجراها با خطا متوقف شده باشند"
    c_hint "bash 03_ops/smoke_test.sh   # جزئیات خطاها"
else
    c_warn "هنوز هیچ دور اجرایی ثبت نشده"
    c_hint "bash 03_ops/diagnose_n8n.sh   # نشان می‌دهد گردش‌کار اجرا می‌شود یا نه و چه خطایی دارد"
    c_hint "یا ۳۰ ثانیه بعد: bash 03_ops/smoke_test.sh"
fi

echo ""
echo "════ کار تمام شد ════"
echo "  حالا از گوشی خود به ربات «XennicNotifierbot» در بله /start بفرستید."
echo "  سپس:  bash 03_ops/smoke_test.sh"
