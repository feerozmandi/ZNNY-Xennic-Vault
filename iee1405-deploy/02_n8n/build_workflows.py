#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — سازنده گردش‌کارهای n8n
#
# چرا با اسکریپت؟ چون گردش‌کار n8n یک فایل JSON است و نوشتن دستی آن
# منبع خطاست. اینجا هر گره و هر پرس‌وجو به‌صورت صریح تعریف می‌شود،
# سپس validate_workflows.py همه را (از جمله SQL را روی PostgreSQL واقعی)
# آزمایش می‌کند.
#
# اجرا:  python3 02_n8n/build_workflows.py
# خروجی: 02_n8n/wf-01-bale-ingest.json … wf-04-health.json
# ═══════════════════════════════════════════════════════════════════════
import json
import pathlib
import uuid

HERE = pathlib.Path(__file__).parent
CRED_NAME = "Xennic PostgreSQL"
CRED_ID = "XENNIC-PG-CREDENTIAL"      # پس از ساخت اعتبارنامه در n8n جای‌گذاری شود
CRED_TYPE = "postgres"

TAG = {"name": "IEE1405"}

# شناسه ثابت برای اجراهای تکراری (idempotent)
NS = uuid.UUID("5f2a9c1e-1405-4b1e-9c3a-000000000000")


def nid(name: str) -> str:
    return str(uuid.uuid5(NS, name))


def pg_node(name, position, query, *, params_expr=None, execute_once=False,
            notes=None, always_output=False):
    """گره PostgreSQL — همه پرس‌وجوها با پارامتر bind، بدون چسباندن رشته."""
    p = {
        "operation": "executeQuery",
        "resource": "database",
        "query": query,
    }
    opts = {}
    if params_expr:
        # فرم آرایه: هر مقدار مستقل bind می‌شود ($1..$n)
        opts["queryReplacement"] = "={{ " + params_expr + " }}"
    if always_output:
        opts["outputColumns"] = []
    p["options"] = opts
    node = {
        "parameters": p,
        "id": nid(name),
        "name": name,
        "type": "n8n-nodes-base.postgres",
        "typeVersion": 2.6,
        "position": position,
        "credentials": {CRED_TYPE: {"id": CRED_ID, "name": CRED_NAME}},
    }
    if execute_once:
        node["executeOnce"] = True
    if notes:
        node["notes"] = notes
        node["notesInFlow"] = True
    return node


def schedule_node(name, position, *, seconds=None, cron=None):
    if cron:
        rule = {"interval": [{"field": "cronExpression", "expression": cron}]}
    else:
        rule = {"interval": [{"field": "seconds", "secondsInterval": seconds}]}
    return {
        "parameters": {"rule": rule},
        "id": nid(name),
        "name": name,
        "type": "n8n-nodes-base.scheduleTrigger",
        "typeVersion": 1.3,
        "position": position,
        "notes": ("زمان‌بندی به وقت تهران (GENERIC_TIMEZONE=Asia/Tehran)" if cron
                  else f"هر {seconds} ثانیه"),
        "notesInFlow": False,
    }


def split_node(name, position, field):
    return {
        "parameters": {
            "fieldToSplitOut": field,
            "options": {},
            "include": "noOtherFields",
        },
        "id": nid(name),
        "name": name,
        "type": "n8n-nodes-base.splitOut",
        "typeVersion": 1,
        "position": position,
    }


def bale_call(name, position, method, *, query_params=None, body_params=None,
              notes=None):
    url = "=https://tapi.bale.ai/bot{{ $env.BALE_BOT_TOKEN }}/" + method
    params = {
        "method": "POST" if body_params else "GET",
        "url": url,
        "options": {},
    }
    if query_params:
        params["sendQuery"] = True
        params["queryParameters"] = {
            "parameters": [{"name": k, "value": v} for k, v in query_params.items()]
        }
    if body_params:
        params["sendBody"] = True
        params["contentType"] = "form-urlencoded"
        params["bodyParameters"] = {
            "parameters": [{"name": k, "value": v} for k, v in body_params.items()]
        }
    node = {
        "parameters": params,
        "id": nid(name),
        "name": name,
        "type": "n8n-nodes-base.httpRequest",
        "typeVersion": 4.2,
        "position": position,
        "retryOnFail": True,
        "maxTries": 3,
        "waitBetweenTries": 3000,
        "onError": "continueRegularOutput",
    }
    if notes:
        node["notes"] = notes
        node["notesInFlow"] = True
    return node


def send_message_node(name, position, *, text_field="text_body", notes=None):
    """ارسال پیام به بله؛ chat_id و متن از آیتم قبلی می‌آید."""
    return bale_call(
        name, position, "sendMessage",
        body_params={
            "chat_id": "={{ $json.chat_id }}",
            "text": "={{ $json." + text_field + " }}",
        },
        notes=notes,
    )


def meta(description):
    return {
        "templateCredsSetupCompleted": False,
        "description": description,
    }


def flow(*names):
    """زنجیره خطی: هر گره به گره بعدی وصل می‌شود."""
    conns = {}
    for a, b in zip(names, names[1:]):
        conns[a] = {"main": [[{"node": b, "type": "main", "index": 0}]]}
    return conns


# ═══════════════════════════════════════════════════════════════════════
# WF-01 — دریافت پیام‌های بله و ثبت در PostgreSQL
# ═══════════════════════════════════════════════════════════════════════
def wf_inbound():
    n_sched = schedule_node("⏱ هر ۲۰ ثانیه", [0, 0], seconds=20)

    n_offset = pg_node(
        "📍 خواندن offset", [220, 0],
        "SELECT iee1405.poll_offset() AS \"offset\";",
        notes="offset پایدار در جدول bot_state؛ با ری‌استارت از دست نمی‌رود",
    )

    n_get = bale_call(
        "📥 دریافت پیام‌ها", [440, 0], "getUpdates",
        query_params={
            "offset": "={{ Number($json.offset) + 1 }}",
            "limit": "50",
            "timeout": "0",
        },
        notes="long-poll = 0 تا اجرای زمان‌بند معطل نماند",
    )

    n_split = split_node("✂️ تفکیک آپدیت‌ها", [660, 0], "result")

    n_dispatch = pg_node(
        "🧠 پردازش در PostgreSQL", [880, 0],
        "SELECT chat_id, status, reply_text, org_code\n"
        "  FROM iee1405.bot_dispatch($1::bigint, $2::bigint, $3::text, $4::jsonb);",
        params_expr=(
            "[$json.update_id,\n"
            "  $json.message.chat.id,\n"
            "  ($json.message.text || ''),\n"
            "  JSON.stringify($json)]"
        ),
        notes="کل منطق ربات داخل تابع SQL است؛ این گره فقط لوله است",
    )

    n_pending = pg_node(
        "📤 پاسخ‌های آماده ارسال", [1100, 0],
        "SELECT update_id, chat_id, text_body\n"
        "  FROM iee1405.pending_replies(20);",
        execute_once=True,   # حیاتی: بدون این، به تعداد آیتم‌ها پیام تکراری می‌رود
        notes="ارسال تضمین‌شده: اگر بله خطا داد، پیام در اجرای بعدی دوباره فرستاده می‌شود",
    )

    n_send = send_message_node("💬 ارسال پاسخ", [1320, 0])

    n_mark = pg_node(
        "✅ ثبت ارسال", [1540, 0],
        "SELECT iee1405.mark_delivered($1::bigint);",
        params_expr="[$json.update_id]",
    )

    n_advance = pg_node(
        "⏭ جلو بردن offset", [1760, 0],
        "SELECT iee1405.poll_advance() AS \"offset\";",
        execute_once=True,
        notes="offset از max(update_id) محاسبه می‌شود؛ نه از حافظه n8n",
    )

    nodes = [n_sched, n_offset, n_get, n_split, n_dispatch,
             n_pending, n_send, n_mark, n_advance]
    wf = {
        "name": "IEE1405-01 — دریافت پیام‌های بله",
        "nodes": nodes,
        "connections": flow(*[n["name"] for n in nodes]),
        "settings": {
            "executionOrder": "v1",
            "timezone": "Asia/Tehran",
            "saveManualExecutions": True,
            "saveExecutionProgress": False,
            "saveDataErrorExecution": "all",
            "saveDataSuccessExecution": "none",
            "callerPolicy": "workflowsFromSameOwner",
        },
        "staticData": None,
        "meta": meta("دریافت آپدیت‌های بله و ثبت شرکت/مذاکره/پیگیری در PostgreSQL"),
        "pinData": {},
        "tags": [TAG],
        "active": False,
    }
    return wf


# ═══════════════════════════════════════════════════════════════════════
# WF-02 — یادآور پیگیری‌ها
# ═══════════════════════════════════════════════════════════════════════
def wf_reminders():
    n_sched = schedule_node("⏱ هر روز ۰۷:۳۰", [0, 0], cron="0 30 7 * * *")
    n_q = pg_node(
        "📋 پیگیری‌های باز", [220, 0],
        "SELECT chat_id, actor, text_body FROM iee1405.reminder_items();",
        notes="یک پیام به‌ازای هر مسئول؛ اگر چیزی نیست، هیچ پیامی نمی‌رود",
    )
    n_send = send_message_node("💬 ارسال یادآور", [440, 0])
    nodes = [n_sched, n_q, n_send]
    return {
        "name": "IEE1405-02 — یادآور پیگیری‌ها",
        "nodes": nodes,
        "connections": flow(*[n["name"] for n in nodes]),
        "settings": {
            "executionOrder": "v1",
            "timezone": "Asia/Tehran",
            "saveDataSuccessExecution": "none",
            "saveDataErrorExecution": "all",
            "callerPolicy": "workflowsFromSameOwner",
        },
        "staticData": None,
        "meta": meta("یادآور پیگیری‌های سررسیدشده تا ۳ روز آینده"),
        "pinData": {},
        "tags": [TAG],
        "active": False,
    }


# ═══════════════════════════════════════════════════════════════════════
# WF-03 — خلاصه پایان روز
# ═══════════════════════════════════════════════════════════════════════
def wf_digest():
    n_sched = schedule_node("⏱ هر روز ۲۰:۳۰", [0, 0], cron="0 30 20 * * *")
    n_q = pg_node(
        "📊 خلاصه روز", [220, 0],
        "SELECT o.chat_id, iee1405.digest_text() AS text_body\n"
        "  FROM iee1405.owner_chat_ids() o;",
        notes="متن از v_today_digest ساخته می‌شود (تست‌شده در SQL)",
    )
    n_send = send_message_node("💬 ارسال خلاصه", [440, 0])
    nodes = [n_sched, n_q, n_send]
    return {
        "name": "IEE1405-03 — خلاصه پایان روز",
        "nodes": nodes,
        "connections": flow(*[n["name"] for n in nodes]),
        "settings": {
            "executionOrder": "v1",
            "timezone": "Asia/Tehran",
            "saveDataSuccessExecution": "none",
            "saveDataErrorExecution": "all",
            "callerPolicy": "workflowsFromSameOwner",
        },
        "staticData": None,
        "meta": meta("خلاصه شمارشی روز برای مدیر"),
        "pinData": {},
        "tags": [TAG],
        "active": False,
    }


# ═══════════════════════════════════════════════════════════════════════
# WF-04 — پایش سلامت
# ═══════════════════════════════════════════════════════════════════════
def wf_health():
    n_sched = schedule_node("⏱ هر ۳۰ دقیقه", [0, 0], cron="0 */30 * * * *")
    n_q = pg_node(
        "🩺 بررسی سلامت", [220, 0],
        "SELECT chat_id, text_body FROM iee1405.health_alert_rows();",
        notes="فقط وقتی مشکل هست ردیف برمی‌گرداند؛ در حالت سالم ساکت است",
    )
    n_send = send_message_node("💬 هشدار", [440, 0])
    nodes = [n_sched, n_q, n_send]
    return {
        "name": "IEE1405-04 — پایش سلامت",
        "nodes": nodes,
        "connections": flow(*[n["name"] for n in nodes]),
        "settings": {
            "executionOrder": "v1",
            "timezone": "Asia/Tehran",
            "saveDataSuccessExecution": "none",
            "saveDataErrorExecution": "all",
            "callerPolicy": "workflowsFromSameOwner",
        },
        "staticData": None,
        "meta": meta("هشدار خودکار در صورت توقف دریافت پیام، خطای ربات یا انبوهی تأخیر"),
        "pinData": {},
        "tags": [TAG],
        "active": False,
    }


FILES = {
    "wf-01-bale-ingest.json": wf_inbound,
    "wf-02-reminders.json": wf_reminders,
    "wf-03-digest.json": wf_digest,
    "wf-04-health.json": wf_health,
}


def main():
    written = []
    for filename, fn in FILES.items():
        wf = fn()
        path = HERE / filename
        path.write_text(json.dumps(wf, ensure_ascii=False, indent=2) + "\n",
                        encoding="utf-8")
        written.append((filename, len(wf["nodes"])))
    print("✅ گردش‌کارها ساخته شد:")
    for f, n in written:
        print(f"   {f}  ({n} گره)")


if __name__ == "__main__":
    main()
