#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — آزمون دودی: آیا زنجیره «بله → n8n → PostgreSQL → بله» کار می‌کند؟
#
# اجرا (بعد از activate_all.sh و بعد از فرستادن /start در بله):
#   bash 03_ops/smoke_test.sh
#
# چه چیزی را با شاهد واقعی بررسی می‌کند (نه با حدس)؟
#   • گردش‌کار در n8n فعال است
#   • دریافت پیام‌ها در ۲ دقیقه گذشته اجرا شده (bot_state.last_poll_at)
#   • پیام‌های بله در پایگاه‌داده ثبت شده‌اند (bot_updates)
#   • پاسخ‌ها ارسال شده‌اند (delivered_at)
#   • خطای ربات وجود ندارد (bot_errors)
#   • تطبیق شناسه گفت‌وگو با کاربران ثبت‌شده
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib_common.sh"

TEST_MSG=0
for a in "$@"; do [[ "$a" == "--test-message" ]] && TEST_MSG=1; done

FAILS=0
pass() { c_ok "$*"; }
fail() { c_bad "$*"; FAILS=$((FAILS + 1)); }
info() { printf '     %s\n' "$*"; }

if ! dk_detect || ! ct_detect; then
    c_bad "Docker یا کانتینرها در دسترس نیستند"
    exit 1
fi
n8n() { $DK exec -i "$N8N_CT" n8n "$@"; }

# فراخوانی API بله بدون چاپ توکن؛ خروجی: بدنه پاسخ
bale_api() {
    local method="$1" url
    url="$(bale_url_detect)" || return 1
    url="$url/$method"
    if command -v curl >/dev/null 2>&1; then
        curl -s --max-time 15 "$url"
    else
        python3 -c "import sys,urllib.request; print(urllib.request.urlopen(sys.argv[1], timeout=15).read().decode())" "$url" 2>/dev/null || echo \'{"ok":false}\'
    fi
}

c_head "۰) اتصال به بله"
if ! bale_url_detect >/dev/null 2>&1; then
    fail "توکن بله در .env پیدا نشد"
    info "bash 03_ops/setup_env.sh"
else
    ME="$(bale_api getMe)"
    if printf '%s' "$ME" | grep -q '"ok":true'; then
        BOTNAME="$(printf '%s' "$ME" | sed -n 's/.*"username":"\([^"]*\)".*/\1/p')"
        pass "توکن معتبر است (ربات: @${BOTNAME:-?})"
    elif [[ -z "$ME" ]]; then
        fail "پاسخی از tapi.bale.ai نیامد (شبکه یا فایروال)"
        info "بررسی: curl -sS --max-time 10 https://tapi.bale.ai"
        info "اگر سرور به اینترنت دسترسی ندارد، ربات هم نمی‌تواند کار کند."
    else
        fail "توکن بله معتبر نیست — پاسخ: $(printf '%s' "$ME" | head -c 160)"
        info "توکن را در .env (BALE_TOKEN_BOT) بررسی کنید"
    fi
fi

c_head "۱) n8n (از دیتابیس خود n8n خوانده می‌شود)"
# چرا از CLI نه؟ «n8n list:workflow --active=true» در 2.44.7 فهرست کامل نمی‌دهد
# و گزارش «هیچ گردش‌کار فعالی نیست» می‌داد در حالی که ۴ گردش‌کار فعال بود.
N8N_DB="$(n8n_db_detect)"
if [[ -n "$N8N_DB" ]]; then
    ACTIVE_LIST="$(pgq "$N8N_DB" -c "
        SELECT id || ' | ' || name
          FROM workflow_entity
         WHERE name LIKE 'IEE1405%' AND active AND \"activeVersionId\" IS NOT NULL
         ORDER BY name" 2>/dev/null)"
    ACTIVE_COUNT="$(printf '%s' "$ACTIVE_LIST" | grep -c . || true)"
    DUPES="$(pgq "$N8N_DB" -c "
        SELECT count(*) FROM workflow_entity
         WHERE name LIKE 'IEE1405%' AND active AND id NOT LIKE 'IEE1405-%'" 2>/dev/null | tr -d '[:space:]')"
    if [[ "${ACTIVE_COUNT:-0}" -ge 4 ]]; then
        pass "$ACTIVE_COUNT گردش‌کار فعال:"
        printf '%s\n' "$ACTIVE_LIST" | sed 's/^/       /'
    elif [[ "${ACTIVE_COUNT:-0}" -gt 0 ]]; then
        warn "$ACTIVE_COUNT از ۴ گردش‌کار فعال است:"
        printf '%s\n' "$ACTIVE_LIST" | sed 's/^/       /'
        info "bash 03_ops/activate_all.sh"
    else
        fail "هیچ گردش‌کار فعال IEE1405 نیست"
        info "bash 03_ops/activate_all.sh"
    fi
    if [[ -n "${DUPES:-}" && "$DUPES" != "0" ]]; then
        fail "$DUPES گردش‌کار تکراری (با شناسه قدیمی) هم فعال است — دو بار getUpdates می‌شود"
        info "bash 03_ops/activate_all.sh   # تکراری‌ها را غیرفعال می‌کند"
    fi
else
    warn "دیتابیس n8n پیدا نشد — بررسی فعال بودن انجام نشد"
fi

# اجراهای گیرکرده: نشانه timeout/معلق‌ماندن درخواست
if [[ -n "$N8N_DB" ]]; then
    STUCK="$(pgq "$N8N_DB" -c "
        SELECT count(*) FROM execution_entity
         WHERE status = 'running' AND \"startedAt\" < now() - interval '2 minutes'" 2>/dev/null | tr -d '[:space:]')"
    if [[ -n "${STUCK:-}" && "${STUCK:-0}" -gt 0 ]]; then
        fail "$STUCK اجرای «در حال اجرا» بیش از ۲ دقیقه — درخواست معلق مانده"
        info "bash 03_ops/diagnose_n8n.sh   # و timeout گره HTTP را بررسی کنید"
    fi
fi

c_head "۲) وضعیت دریافت پیام (bot_state)"
LAST_POLL="$(pgq "$PG_DB" -c "SELECT value FROM iee1405.bot_state WHERE key='last_poll_at'" 2>/dev/null | tr -d '\r\n')"
OFFSET="$(pgq "$PG_DB" -c "SELECT value FROM iee1405.bot_state WHERE key='bale_offset'" 2>/dev/null | tr -d '[:space:]')"
if [[ -z "$LAST_POLL" || "$LAST_POLL" == "" ]]; then
    fail "last_poll_at خالی است — گردش‌کار ۰۱ هنوز اجرا نشده"
    info "bash 03_ops/diagnose_n8n.sh   # آیا اجرا می‌شود و چه خطایی دارد"
    info "bash 03_ops/activate_all.sh   # اعتبارنامه + انتشار + ری‌استارت"
else
    # فاصله زمانی تا الان — محاسبه در SQL تا برش رشته، timestamp را خراب نکند
    AGE="$(pgq "$PG_DB" -c "
        SELECT EXTRACT(EPOCH FROM (now() - value::timestamptz))::int
          FROM iee1405.bot_state WHERE key = 'last_poll_at'" 2>/dev/null | tr -d '[:space:]')"
    if [[ -n "$AGE" ]] && [[ "$AGE" -lt 180 ]]; then
        pass "آخرین دریافت $AGE ثانیه پیش بود (گردش‌کار زنده است)"
    else
        fail "آخرین دریافت ${AGE:-?} ثانیه پیش بود — گردش‌کار متوقف شده"
        info "bash 03_ops/activate_all.sh  یا اجرای دستی در n8n"
    fi
fi
[[ -n "$OFFSET" ]] && info "offset فعلی بله: $OFFSET"

# خطای بازِ getUpdates: «سکوت» را از «قطعی» جدا می‌کند
LAST_ERR="$(pgq "$PG_DB" -c "
    SELECT COALESCE((
        SELECT left(message, 80) FROM iee1405.bot_errors
         WHERE stage = 'bale_getupdates'
           AND occurred_at > COALESCE((SELECT value::timestamptz
                                         FROM iee1405.bot_state
                                        WHERE key = 'last_poll_at'),
                                      '-infinity'::timestamptz)
         ORDER BY occurred_at DESC LIMIT 1), '')" 2>/dev/null | tr -d '\r\n')"
LAST_ERR="$(printf '%s' "$LAST_ERR" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
if [[ -n "$LAST_ERR" ]]; then
    fail "آخرین درخواست getUpdates خطا داد: $LAST_ERR"
    info "اگر خطای شبکه‌ای است، سرور به tapi.bale.ai نمی‌رسد (فیلتر/DNS/پروکسی)"
    info "تست دستی: curl -s -m 10 -o /dev/null -w '%{http_code}\n' https://tapi.bale.ai"
fi

c_head "۳) پیام‌های دریافتی"
if [[ "$(pgq "$PG_DB" -c "SELECT count(*) FROM iee1405.bot_updates" 2>/dev/null | tr -d '[:space:]')" == "0" ]]; then
    fail "هیچ پیامی ثبت نشده — در بله به ربات /start بفرستید و این اسکریپت را دوباره اجرا کنید"
else
    pass "پیام‌ها ثبت شده‌اند:"
    pgq_pretty "$PG_DB" -c "
        SELECT update_id, actor, status,
               to_char(received_at AT TIME ZONE 'Asia/Tehran', 'MM-DD HH24:MI:SS') AS received,
               (delivered_at IS NOT NULL) AS delivered,
               left(coalesce(reply_text, error, ''), 40) AS reply
          FROM iee1405.bot_updates
         ORDER BY update_id DESC LIMIT 8" | sed 's/^/       /'
fi

c_head "۴) تطبیق کاربران"
pgq_pretty "$PG_DB" -c "
    SELECT username, role,
           coalesce(bale_chat_id::text, '—') AS chat_id,
           CASE WHEN last_seen_at IS NOT NULL
                THEN to_char(last_seen_at AT TIME ZONE 'Asia/Tehran', 'MM-DD HH24:MI')
                ELSE '—' END AS last_seen
      FROM crm.users ORDER BY role, username" | sed 's/^/     /'

UNLINKED="$(pgq "$PG_DB" -c "SELECT count(*) FROM crm.users WHERE bale_chat_id IS NULL AND role IN ('owner','field_agent')" | tr -d '[:space:]')"
if [[ "${UNLINKED:-0}" == "0" ]]; then
    pass "همه کاربران میدانی شناسه گفت‌وگو دارند"
else
    fail "$UNLINKED کاربر بدون شناسه گفت‌وگو — ربات به آن‌ها پاسخ نمی‌دهد"
    info "در بله /start بفرستید؛ شناسه نمایش داده می‌شود؛ سپس در .env → BALE_CHAT_ID"
fi

c_head "۵) خطاها"
ERRS="$(pgq "$PG_DB" -c "SELECT iee1405.recent_error_count(interval '24 hours')" | tr -d '[:space:]')"
if [[ ! "$ERRS" =~ ^[0-9]+$ ]]; then
    fail "شمارش خطاها خوانده نشد (خروجی: ${ERRS:-خالی})"
    info "تایید کنید تابع iee1405.recent_error_count ساخته شده: bash 03_ops/deploy_sql.sh"
elif [[ "$ERRS" == "0" ]]; then
    pass "هیچ خطای بازی در ۲۴ ساعت گذشته ثبت نشده"
else
    fail "$ERRS خطای باز در ۲۴ ساعت گذشته:"
    pgq_pretty "$PG_DB" -c "
        SELECT to_char(occurred_at AT TIME ZONE 'Asia/Tehran','MM-DD HH24:MI') AS at,
               stage, left(message, 60) AS message, detail
          FROM iee1405.bot_errors ORDER BY occurred_at DESC LIMIT 5" | sed 's/^/       /'
fi

c_head "۶) داده‌ای که تا حالا ثبت شده"
pgq_pretty "$PG_DB" -c "
    SELECT (SELECT count(*) FROM crm.organizations)      AS companies,
           (SELECT count(*) FROM crm.interactions)       AS meetings,
           (SELECT count(*) FROM crm.tasks WHERE status='open') AS open_tasks,
           (SELECT count(*) FROM crm.claims)             AS claims,
           (SELECT count(*) FROM crm.attachments)        AS files" | sed 's/^/     /'

if [[ "$TEST_MSG" == "1" ]]; then
    c_head "۷) ارسال پیام آزمایشی به بله"
    CHAT="$(env_get BALE_CHAT_ID || true)"
    URL="$(bale_url_detect || true)"
    if [[ -z "$CHAT" ]]; then
        fail "BALE_CHAT_ID در .env نیست"
    elif [[ -z "$URL" ]]; then
        fail "توکن بله پیدا نشد"
    else
        RESP="$(curl -s --max-time 15 -X POST "$URL/sendMessage" -d "chat_id=$CHAT" --data-urlencode "text=آزمون اتصال Xennic — این پیام از smoke_test.sh ارسال شد." 2>/dev/null)"
        if printf '%s' "$RESP" | grep -q '"ok":true'; then
            pass "پیام آزمایشی ارسال شد — در بله ببینید"
        else
            fail "ارسال ناموفق: $(printf '%s' "$RESP" | head -c 160)"
        fi
    fi
fi

echo ""
if [[ "$FAILS" == "0" ]]; then
    c_ok "زنجیره کامل سالم است — از همین حالا می‌توانید در نمایشگاه استفاده کنید"
    exit 0
fi
c_warn "$FAILS مورد نیاز به توجه دارد (بالا را ببینید)"
exit 1
