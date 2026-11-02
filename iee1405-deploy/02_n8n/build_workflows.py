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
            notes=None):
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


def split_node(name, position, field, always_output=False):
    node = {
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
    if always_output:
        node["alwaysOutputData"] = True
    return node


def bale_call(name, position, method, *, query_params=None, body_params=None,
              notes=None):
    # BALE_API_URL تنها متغیری است که setup_env.sh می‌سازد و preflight.sh تأیید
    # می‌کند (https://tapi.bale.ai/bot<TOKEN>). ارجاع به نام دیگری مثل
    # BALE_BOT_TOKEN باعث می‌شد آدرس به «botundefined» تبدیل شود و هرگز کار نکند.
    url = "={{ $env.BALE_API_URL }}/" + method
    params = {
        "method": "POST" if body_params else "GET",
        "url": url,
        "options": {
            # بدون timeout، یک اتصال معلق اجرا را دقیقه‌ها در حالت running
            # نگه می‌داشت و صف اجراها پر می‌شد.
            "timeout": 20000,
        },
    }
    if query_params:
        params["sendQuery"] = True
        # specifyQuery پیش‌فرض کد 'keypair' است؛ صریح می‌نویسیم تا به نسخه وابسته نباشیم
        params["specifyQuery"] = "keypair"
        params["queryParameters"] = {
            "parameters": [{"name": k, "value": v} for k, v in query_params.items()]
        }
    if body_params:
        params["sendBody"] = True
        params["contentType"] = "form-urlencoded"
        # ⚠️ حیاتی: در کد گره، specifyBody با پیش‌فرض '' خوانده می‌شود؛
        # اگر غایب باشد هیچ شاخه‌ای اجرا نمی‌شود و بدنه خالی ارسال می‌شود
        params["specifyBody"] = "keypair"
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
        # تلاش دوباره این‌جا لازم نیست: پاسخ‌ها در دیتابیس می‌مانند و اجرای
        # بعدی (هر ۲۰ ثانیه) خودش بازفرست می‌کند. تلاش دوباره فقط صف را
        # شلوغ می‌کرد و خطا را دیر نشان می‌داد.
        "retryOnFail": False,
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

    n_beat = pg_node(
        "💓 ضربان دریافت", [440, 0],
        "SELECT iee1405.poll_heartbeat() AS \"at\";",
        execute_once=True,
        notes="هر اجرا این را ثبت می‌کند؛ پس «سکوت بله» از «توقف گردش‌کار» جدا می‌شود",
    )

    n_get = bale_call(
        "📥 دریافت پیام‌ها", [660, 0], "getUpdates",
        query_params={
            "offset": "={{ Number($json.offset) + 1 }}",
            "limit": "50",
            "timeout": "0",
        },
        notes="long-poll = 0 تا اجرای زمان‌بند معطل نماند",
    )
    n_get["onError"] = "continueErrorOutput"

    n_watch = pg_node(
        "🩺 بازرسی پاسخ بله", [880, 0],
        "SELECT iee1405.poll_watch($1::jsonb) AS response;",
        params_expr="[JSON.stringify($json)]",
        execute_once=True,
        notes="بله خطاها را با HTTP 200 و ok:false برمی‌گرداند؛ این‌جا ثبت می‌شود",
    )

    # alwaysOutputData حیاتی است: در اجرای بی‌پیام، split هیچ آیتمی تولید نمی‌کند
    # و گره‌های بعدی اجرا نمی‌شدند؛ در نتیجه last_poll_at هرگز تازه نمی‌شد و
    # پایش سلامت، «سکوت» را با «قطعی» اشتباه می‌گرفت.
    n_split = split_node("✂️ تفکیک آپدیت‌ها", [1100, 0], "response.result", always_output=True)

    n_dispatch = pg_node(
        "🧠 پردازش در PostgreSQL", [1320, 0],
        "SELECT chat_id, status, reply_text, org_code\n"
        "  FROM iee1405.bot_dispatch_json($1::jsonb);",
        params_expr="JSON.stringify($json)",
        notes="کل منطق ربات داخل تابع SQL است؛ این گره فقط یک JSON می‌فرستد",
    )

    # بلافاصله بعد از پردازش: در هر اجرا (حتی بی‌پیام) زمان دریافت ثبت می‌شود
    n_advance = pg_node(
        "⏭ ثبت زمان دریافت", [1100, 0],
        "SELECT iee1405.poll_advance() AS \"offset\";",
        execute_once=True,
        notes="offset از max(update_id) محاسبه می‌شود، نه از حافظه n8n",
    )

    n_pending = pg_node(
        "📤 پاسخ‌های آماده ارسال", [1540, 0],
        "SELECT update_id, chat_id, text_body\n"
        "  FROM iee1405.pending_replies(20);",
        execute_once=True,   # حیاتی: بدون این، به تعداد آیتم‌ها پیام تکراری می‌رود
        notes="ارسال تضمین‌شده: اگر بله خطا داد، پیام در اجرای بعدی دوباره فرستاده می‌شود",
    )

    n_send = send_message_node("💬 ارسال پاسخ", [1760, 0])

    n_mark = pg_node(
        "✅ ثبت ارسال", [1980, 0],
        "SELECT iee1405.mark_delivered($1::bigint);",
        params_expr="[$json.update_id]",
    )

    # شاخه خطا: اگر getUpdates شکست بخورد، ثبت می‌شود تا قطعی از سکوت تفکیک شود
    # شاخه خطا باید هرگز خودش اجرا را نکشد: ورودی را عیناً JSON می‌فرستیم
    # (اگر $json.error وجود نداشته باشد، دسترسی به .message کل اجرا را می‌شکست)
    # و تحلیل پیام در خود SQL انجام می‌شود.
    n_pollerr = pg_node(
        "🛑 ثبت خطای دریافت", [880, 200],
        "SELECT iee1405.record_poll_error($1::text);",
        params_expr="[JSON.stringify($json)]",
        execute_once=True,
        notes="خروجی خطای گره HTTP به اینجا می‌آید؛ پیام در SQL استخراج می‌شود",
    )
    n_pollerr["onError"] = "continueRegularOutput"

    nodes = [n_sched, n_offset, n_beat, n_get, n_watch, n_split, n_dispatch,
             n_advance, n_pending, n_send, n_mark, n_pollerr]

    conns = {
        n_sched["name"]:  {"main": [[{"node": n_offset["name"],  "type": "main", "index": 0}]]},
        n_offset["name"]: {"main": [[{"node": n_beat["name"],    "type": "main", "index": 0}]]},
        n_beat["name"]:   {"main": [[{"node": n_get["name"],     "type": "main", "index": 0}]]},
        n_get["name"]:    {"main": [
                                [{"node": n_watch["name"], "type": "main", "index": 0}],
                                [{"node": n_pollerr["name"], "type": "main", "index": 0}],
                          ]},
        n_watch["name"]:  {"main": [[{"node": n_split["name"], "type": "main", "index": 0}]]},
        n_split["name"]:  {"main": [[{"node": n_advance["name"], "type": "main", "index": 0}]]},
        n_advance["name"]:  {"main": [[{"node": n_dispatch["name"], "type": "main", "index": 0}]]},
        n_dispatch["name"]: {"main": [[{"node": n_pending["name"], "type": "main", "index": 0}]]},
        n_pending["name"]:  {"main": [[{"node": n_send["name"], "type": "main", "index": 0}]]},
        n_send["name"]:     {"main": [[{"node": n_mark["name"], "type": "main", "index": 0}]]},
    }

    wf = {
        "name": "IEE1405-01 — دریافت پیام‌های بله",
        "nodes": nodes,
        "connections": conns,
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


# شناسه ثابت گردش‌کارها — بدون این، هر ایمپورت یک گردش‌کار *تازه* می‌سازد
# و نسخه قبلی فعال می‌ماند (دو بار polling و پیام تکراری).
FIXED_IDS = {
    "wf-01-bale-ingest.json": "IEE1405-01",
    "wf-02-reminders.json":   "IEE1405-02",
    "wf-03-digest.json":      "IEE1405-03",
    "wf-04-health.json":      "IEE1405-04",
}


def main():
    written = []
    for filename, fn in FILES.items():
        wf = fn()
        wf = {"id": FIXED_IDS[filename], **wf}
        path = HERE / filename
        path.write_text(json.dumps(wf, ensure_ascii=False, indent=2) + "\n",
                        encoding="utf-8")
        written.append((filename, len(wf["nodes"])))
    print("✅ گردش‌کارها ساخته شد:")
    for f, n in written:
        print(f"   {f}  ({n} گره)")


if __name__ == "__main__":
    main()
