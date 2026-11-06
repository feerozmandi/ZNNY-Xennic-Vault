#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — شبیه‌سازی سرتاسری گردش‌کار n8n روی PostgreSQL واقعی
#
# پرس‌وجوها از خود فایل JSON گردش‌کار خوانده می‌شوند (نه کپی‌شده)،
# تا اگر فایل عوض شود و کسی کوئری را نشکند، این آزمون هم همان را بسنجد.
#
# قواعد شبیه‌سازی، دقیقاً مثل n8n:
#   • گره Postgres برای «هر آیتم ورودی» یک بار اجرا می‌شود
#   • گره دارای executeOnce فقط یک بار اجرا می‌شود
#   • اگر گره‌ای صفر ردیف برگرداند، گره‌های بعدی اجرا نمی‌شوند
#   • تماس‌های HTTP به «بله جعلی» می‌روند (هیچ درخواست واقعی ارسال نمی‌شود)
#
# اجرا: python3 03_ops/test_workflow_e2e.py
# ═══════════════════════════════════════════════════════════════════════
import json
import os
import subprocess
import sys
import pathlib

import pgserver
from pathlib import Path as P

# مسیر باینری‌ها: اول متغیر محیطی، بعد مسیر نصب سیستمی، بعد محل نصب همین بسته.
# (روی سرور آزمایشی و در محیط محلی این دو یکی نیستند؛ مسیر ثابت، آزمون را می‌شکند.)
_BIN_CANDIDATES = [
    P(os.environ["PG_BIN"]) if os.environ.get("PG_BIN") else None,
    P("/usr/local/lib/python3.11/dist-packages/pgserver/pginstall/bin"),
    P(pgserver.__file__).resolve().parent / "pginstall" / "bin",
]
BIN = next((b for b in _BIN_CANDIDATES if b and (b / "psql").exists()),
           _BIN_CANDIDATES[1])
ROOT = pathlib.Path(__file__).resolve().parent.parent
WF = ROOT / "02_n8n"

srv = pgserver.get_server("/tmp/pgdata", cleanup_mode=None)


def _pick_db(srv):
    """همان دیتابیسی را انتخاب می‌کند که در تولید استفاده می‌شود.

    چرا؟ خوشه تست می‌تواند چند نسخه از ساختار داشته باشد (postgres و xennic).
    اگر آزمون روی «پیش‌فرض» اجرا شود، سبز بودنش به این بستگی دارد کدام نسخه
    سالم مانده باشد — و کمبود دسترسی نقش در نسخه دیگر پنهان می‌ماند.
    """
    base = srv.get_uri()
    for name in (os.environ.get("IEE_TEST_DB"), "xennic", "postgres"):
        if not name:
            continue
        cand = base.replace("/postgres?", f"/{name}?")
        try:
            r = subprocess.run(
                [str(BIN / "psql"), cand, "-X", "-t", "-A", "-v", "ON_ERROR_STOP=1",
                 "-c", "SELECT to_regclass('iee1405.bot_state') IS NOT NULL"],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10)
            if r.stdout.decode().strip() == "t":
                return cand
        except Exception:
            continue
    return base


URI = _pick_db(srv)

PASS, FAIL = [], []
print(f"پایگاه‌داده آزمون: {URI.rsplit('/', 1)[-1].split('?')[0]}")
OWNER_CHAT = 900001
UNKNOWN_CHAT = 900999


def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(f"{'✅' if cond else '❌'} {name}" + (f"   [{detail}]" if detail else ""))


def psql(sql, params=None, fail_ok=False):
    cmd = sql.rstrip().rstrip(";")
    if params:
        binds = " ".join("'" + str(p).replace("'", "''") + "'" for p in params)
        cmd += f"\n\\bind {binds}\n\\g"
    p = subprocess.run([str(BIN / "psql"), URI, "-v", "ON_ERROR_STOP=1", "-q", "-t", "-A",
                        "-F", "\x1f", "-R", "\x1e"],
                       input=cmd.encode(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = p.stdout.decode("utf-8", "replace").strip()
    if p.returncode != 0 and not fail_ok:
        raise RuntimeError(f"SQL failed: {sql[:200]}\n{out[:600]}")
    return [r.split("\x1f") for r in out.split("\x1e") if r.strip() != ""]


def psql_as(role, sql, params=None):
    """اجرا با نقش مشخص. n8n با iee_app کار می‌کند، نه با postgres؛ پس هر
    دسترسی که در این نقش نباشد، در تولید به «permission denied» می‌رسد."""
    cmd = sql.rstrip().rstrip(";")
    if params:
        binds = " ".join("'" + str(x).replace("'", "''") + "'" for x in params)
        cmd += f"\n\\bind {binds}\n\\g"
    p = subprocess.run([str(BIN / "psql"), URI, "-v", "ON_ERROR_STOP=1", "-q", "-t", "-A",
                        "-F", "\x1f", "-R", "\x1e"],
                       input=f"SET ROLE {role};\n{cmd}".encode(),
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = p.stdout.decode("utf-8", "replace").strip()
    if p.returncode != 0:
        raise RuntimeError(f"SQL as {role} failed: {sql[:160]}\n{out[:500]}")
    return [r.split("\x1f") for r in out.split("\x1e") if r.strip() != ""]


def node(name, wf):
    return next(n for n in wf["nodes"] if n["name"] == name)


def query_of(name, wf):
    return node(name, wf)["parameters"]["query"]


def fake_bale(offset, updates):
    """getUpdates جعلی: فقط آپدیت‌های بعد از offset."""
    return [u for u in updates if u["update_id"] >= offset + 1]


def send_message(chat_id, text):
    """بله جعلی: فقط ثبت می‌کنیم چه چیزی ارسال می‌شد."""
    return {"ok": True, "result": {"message_id": len(OUTBOX) + 1, "chat": {"id": chat_id},
                                   "text": text}}


OUTBOX = []


def main():
    wf = json.loads((WF / "wf-01-bale-ingest.json").read_text(encoding="utf-8"))
    psql("BEGIN;")
    # وضعیت پایدار را در همین تراکنش صفر می‌کنیم تا آزمون به اجرای قبلی وابسته نباشد
    psql("DELETE FROM iee1405.bot_updates;")
    psql("SELECT iee1405.poll_reset(0);")
    psql("UPDATE crm.users SET bale_chat_id = $1 WHERE username = 'ahmad';", [OWNER_CHAT])

    def msg(uid, chat, text):
        """شکل واقعی آپدیت بله: message.chat.id و message.text"""
        return {"update_id": uid,
                "message": {"message_id": uid, "chat": {"id": chat, "type": "private"},
                            "from": {"id": chat}, "date": 1762000000, "text": text}}

    updates = [
        msg(7001, OWNER_CHAT, "/start"),
        msg(7002, UNKNOWN_CHAT, "/start"),
        msg(7003, OWNER_CHAT, "/new"),
        msg(7004, OWNER_CHAT, "شرکت برق‌آوران پارس"),
        msg(7005, OWNER_CHAT, "1"),
        msg(7006, OWNER_CHAT, "38-12"),
        msg(7007, OWNER_CHAT, "/today"),
        # پیام بدون متن (عکس) — نباید خطا بدهد و نباید چیزی را از دست بدهد
        {"update_id": 7008,
         "message": {"message_id": 7008, "chat": {"id": OWNER_CHAT, "type": "private"},
                     "from": {"id": OWNER_CHAT}, "date": 1762000100,
                     "photo": [{"file_id": "abc", "width": 1280, "height": 720}]}},
        # پست کانال — ساختار متفاوت، نباید کل دسته را از بین ببرد
        {"update_id": 7009,
         "channel_post": {"message_id": 1, "chat": {"id": -1001234567890, "type": "channel"},
                          "date": 1762000200, "text": "اطلاعیه"}},
    ]

    # ── اجرای گردش‌کار ──
    offset_rows = psql(query_of("📍 خواندن offset", wf))
    offset = int(offset_rows[0][0])

    incoming = fake_bale(offset, updates)
    check("دریافت پیام جدید", len(incoming) == len(updates), str(len(incoming)))

    # همان گره‌ای که در گردش‌کار واقعی بعد از دریافت اجرا می‌شود: بارزسی پاسخ
    # بله و ثبت شناسه‌های همین دسته. بدون آن، offset جلو نمی‌رود — و این
    # درست است: از نسخهٔ ۰.۱.۳۲ `poll_advance` فقط شناسه‌هایی را می‌شمارد که
    # خودِ بله در همان دریافت داده، تا یک ردیف دستی با شناسهٔ غول‌آسا نتواند
    # offset را مسموم کند و getUpdates را به ۵۰۰ بیندازد.
    psql(query_of("🩺 بازرسی پاسخ بله", wf),
         [json.dumps({"ok": True, "result": incoming}, ensure_ascii=False)])

    dispatched = 0
    for u in incoming:                                  # splitOut → یک آیتم per update
        rows = psql(query_of("🧠 پردازش در PostgreSQL", wf),
                    [json.dumps(u, ensure_ascii=False)])
        dispatched += len(rows)

    # گره «پاسخ‌های آماده ارسال» executeOnce = فقط یک بار
    pending = psql(query_of("📤 پاسخ‌های آماده ارسال", wf))
    check("پاسخ‌ها در صف ارسال قرار گرفتند", len(pending) == len(incoming),
          f"{len(pending)} صف / {len(incoming)} ورودی")

    for row in pending:                                 # ارسال to هر پاسخ
        update_id, chat_id, text = int(row[0]), int(row[1]), row[2]
        send_message(chat_id, text)
        OUTBOX.append({"chat_id": chat_id, "text": text})
        # همان دو ورودی گره واقعی: update_id از گره صف + پاسخ بله از گره ارسال
        psql(query_of("✅ ثبت ارسال", wf),
             [update_id, '{"ok":true,"result":{"message_id":1}}'])

    remaining = psql(query_of("📤 پاسخ‌های آماده ارسال", wf))
    check("صف پس از ارسال خالی شد (تحویل تضمین‌شده)", len(remaining) == 0, str(len(remaining)))

    new_offset = int(psql(query_of("⏭ ثبت زمان دریافت", wf))[0][0])
    check("offset به آخرین آپدیتِ همین دسته رسید", new_offset >= 7009, str(new_offset))

    # ── بررسی رفتار ──
    owner_msgs = [m for m in OUTBOX if m["chat_id"] == OWNER_CHAT]
    unknown_msgs = [m for m in OUTBOX if m["chat_id"] == UNKNOWN_CHAT]

    check("کاربر مجاز ۷ پاسخ گرفت (۶ متن + ۱ راهنمای رسانه)", len(owner_msgs) == 7,
          str(len(owner_msgs)))
    check("پیام عکس خطا نداد و راهنما داد",
          any("فقط متن ثبت می‌شود" in m["text"] for m in owner_msgs))
    check("پست کانال پردازش شد (بدون گم شدن بقیه)",
          any(m["chat_id"] == -1001234567890 for m in OUTBOX))
    check("کاربر ناشناس فقط پیام عدم دسترسی گرفت",
          len(unknown_msgs) == 1 and "مجاز نیست" in unknown_msgs[0]["text"],
          unknown_msgs[0]["text"][:60] if unknown_msgs else "—")
    check("راهنما ارسال شد", any("راهنمای ربات" in m["text"] for m in owner_msgs))

    org = psql("SELECT code, legal_name FROM crm.organizations "
               "WHERE legal_name = 'شرکت برق‌آوران پارس'")
    check("شرکت در پایگاه‌داده ثبت شد", len(org) == 1 and org[0][0].startswith("ORG-"),
          org[0][0] if org else "—")

    booth = psql("SELECT coalesce(p.hall,'') || '-' || coalesce(p.booth_number,'') "
                 "FROM iee1405.participations p JOIN crm.organizations o ON o.id = p.organization_id "
                 "WHERE o.legal_name = 'شرکت برق‌آوران پارس'")
    check("سالن/غرفه ۳۸-۱۲ ثبت شد", booth and booth[0][0] == "38-12",
          booth[0][0] if booth else "—")

    cat = psql("SELECT cl.value_text FROM crm.claims cl JOIN crm.organizations o ON o.id = cl.subject_id "
               "WHERE o.legal_name = 'شرکت برق‌آوران پارس' AND cl.attribute = 'capability.category'")
    check("دسته محصول به‌عنوان ادعای reported ثبت شد",
          cat and cat[0][0] == "TAB_MV", cat[0][0] if cat else "—")

    # ── مسیر جایگزین: بله پیام را با دکمه رد می‌کند ──
    # سناریوی واقعی ۰.۱.۳۵: پیام با reply_markup رد شد، «ثبت ارسال» با شکست
    # ثبت شد و ربات تا پنج تلاش ساکت ماند. اکنون باید بدون دکمه برسد.
    psql("UPDATE iee1405.bot_state SET value = '0' WHERE key = 'help_dedupe_seconds';")
    psql("UPDATE iee1405.bot_state SET value = '0' WHERE key = 'markup_failures';")
    psql("UPDATE iee1405.bot_state SET value = 'true' WHERE key = 'keyboard_enabled';")
    psql(query_of("🧠 پردازش در PostgreSQL", wf),
         [json.dumps(msg(7101, OWNER_CHAT, "/help"), ensure_ascii=False)])
    pend = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
    check("پیام آزمون مسیر جایگزین در صف است", len(pend) == 1, str(len(pend)))
    fb_id, fb_chat, fb_text = pend[0][0], pend[0][1], pend[0][2]

    # قفل ارسال: اجرای دوم نباید همان ردیف را دوباره بردارد (پیام تکراری)
    dup = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
    check("اجرای هم‌زمان همان پیام را دو بار برنمی‌دارد (قفل ارسال)", len(dup) == 0,
          str(len(dup)))

    bad = ('{"ok":false,"error_code":400,'
           '"description":"Bad Request: reply_markup"}')
    psql(query_of("✅ ثبت ارسال", wf), [fb_id, bad])
    still = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
    check("ارسال ناموفق در صف می‌ماند (تضمین تحویل)", len(still) == 1, str(len(still)))

    OUTBOX.append({"chat_id": fb_chat, "text": fb_text})
    psql(query_of("✅ ثبت ارسال بدون دکمه", wf),
         [fb_id, '{"ok":true,"result":{"message_id":2}}'])
    after_fb = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
    check("ارسال دوباره بدون دکمه پیام را تحویل داد", len(after_fb) == 0, str(len(after_fb)))
    check("پیام جایگزین همان متن را دارد", OUTBOX[-1]["text"] == fb_text,
          OUTBOX[-1]["text"][:40])
    fails = psql("SELECT value FROM iee1405.bot_state WHERE key = 'markup_failures'")
    check("تلاش جایگزین ثبت شد", fails and fails[0][0] == "1", fails[0][0] if fails else "—")

    # سه بار پشت سر هم = دکمه‌ها روی این نسخهٔ بله کار نمی‌کنند → خودکار خاموش
    psql("UPDATE iee1405.bot_state SET value = '2' WHERE key = 'markup_failures';")
    psql(query_of("🧠 پردازش در PostgreSQL", wf),
         [json.dumps(msg(7102, OWNER_CHAT, "/today"), ensure_ascii=False)])
    pend2 = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
    if pend2:
        psql(query_of("✅ ثبت ارسال بدون دکمه", wf),
             [pend2[0][0], '{"ok":true,"result":{"message_id":3}}'])
    kb = psql("SELECT value FROM iee1405.bot_state WHERE key = 'keyboard_enabled'")
    check("پس از سه شکست پیاپی، دکمه‌ها خودکار خاموش شدند",
          kb and kb[0][0] == "false", kb[0][0] if kb else "—")
    psql("UPDATE iee1405.bot_state SET value = 'true' WHERE key = 'keyboard_enabled';")
    psql("UPDATE iee1405.bot_state SET value = '0' WHERE key = 'markup_failures';")
    psql("UPDATE iee1405.bot_state SET value = '45' WHERE key = 'help_dedupe_seconds';")

    has_mirror = psql("SELECT iee1405.mirror_ready()")[0][0] == "t"

    # ── ویرایش به‌جای پیام تازه (callback) ──
    if has_mirror:
        psql("UPDATE iee1405.bot_sessions SET state = 'idle', payload = '{}' "
             "WHERE chat_id = $1;", [OWNER_CHAT])
        psql(query_of("🧠 پردازش در PostgreSQL", wf),
             [json.dumps(msg(8201, OWNER_CHAT, "/list"), ensure_ascii=False)])
        first = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
        check("فهرست برای آزمون ویرایش در صف است", len(first) == 1, str(len(first)))
        if first:
            psql(query_of("✅ ثبت ارسال", wf),
                 [int(first[0][0]), '{"ok":true,"result":{"message_id":21}}'])
            cb = {"update_id": 8202,
                  "callback_query": {"id": "cb9", "data": "l:2",
                                     "from": {"id": OWNER_CHAT},
                                     "message": {"message_id": 21,
                                                 "chat": {"id": OWNER_CHAT, "type": "private"}}}}
            psql(query_of("🧠 پردازش در PostgreSQL", wf),
                 [json.dumps(cb, ensure_ascii=False)])
            row = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
            check("پاسخ به دکمه، شناسهٔ همان پیام را برای ویرایش دارد",
                  row and row[0][4] == "21", row[0][4] if row else "—")

            # همان شناسه در گرهٔ «روش ارسال» باید شاخهٔ ویرایش را انتخاب کند
            edit_expr = node("🔀 روش ارسال", wf)["parameters"]["conditions"]["conditions"][0]["leftValue"]
            check("گرهٔ «روش ارسال» بر پایهٔ edit_message_id تصمیم می‌گیرد",
                  "edit_message_id" in edit_expr, edit_expr[:60])

            # «message is not modified» باید تحویل حساب شود، نه شکست
            psql(query_of("✅ ثبت ارسال", wf),
                 [int(row[0][0]),
                  '{"ok":false,"error_code":400,"description":"Bad Request: message is not modified"}'])
            left_after = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
            check("«message is not modified» شکست حساب نمی‌شود (پیام دوباره فرستاده نمی‌شود)",
                  len(left_after) == 0, str(len(left_after)))

    # ── مصاحبهٔ غرفه از مسیر واقعی گردش‌کار ──
    if has_mirror:
        co_id = psql("SELECT min(id) FROM barghpa.company")[0][0]
        psql("UPDATE iee1405.bot_sessions SET state = 'idle', payload = '{}' "
             "WHERE chat_id = $1;", [OWNER_CHAT])
        psql("DELETE FROM iee1405.interviews;")
        start = {"update_id": 8301,
                 "callback_query": {"id": "cb10", "data": "i:" + co_id,
                                    "from": {"id": OWNER_CHAT},
                                    "message": {"message_id": 31,
                                                "chat": {"id": OWNER_CHAT, "type": "private"}}}}
        psql(query_of("🧠 پردازش در PostgreSQL", wf), [json.dumps(start, ensure_ascii=False)])
        q = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
        check("دکمهٔ «مصاحبه» اول نام مصاحبه‌شونده را می‌پرسد",
              q and "نام مصاحبه" in q[0][2], q[0][2][:40] if q else "—")
        if q:
            check("پیام پرسش نام، همان پیام کارت را ویرایش می‌کند",
                  q[0][4] == "31", q[0][4])
            psql(query_of("✅ ثبت ارسال", wf),
                 [int(q[0][0]), '{"ok":true,"result":{"message_id":31}}'])

        # به ترتیب همان شش سؤال پیش‌فرض: فعالیت · توان · ظرفیت · گلوگاه · همکاری · پیگیری
        scripted = ["سارا موسوی", "کارشناس فروش",
                    "تولید تابلوی فشار متوسط",
                    "تابلوهای MV و پست کمپکت",
                    "تا ۳۶ کیلوولت، ۲۰ عدد در ماه",
                    "رله حفاظتی را وارد می‌کنیم",
                    "نمایندگی",
                    "آقای رضایی ۰۹۱۲۰۰۰۰۰۰۰"]
        for i, txt in enumerate(scripted):
            psql(query_of("🧠 پردازش در PostgreSQL", wf),
                 [json.dumps(msg(8310 + i, OWNER_CHAT, txt), ensure_ascii=False)])
            pend = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
            for r in pend:
                psql(query_of("✅ ثبت ارسال", wf),
                     [int(r[0]), '{"ok":true,"result":{"message_id":40}}'])

        iv = psql("SELECT interviewee_name, interviewee_role, jsonb_array_length(answers), "
                  "state, cooperation FROM iee1405.interviews")
        check("مصاحبه در پایگاه ثبت شد", len(iv) == 1, str(len(iv)))
        if iv:
            check("نام و سمت مصاحبه‌شونده ثبت شد",
                  iv[0][0] == "سارا موسوی" and iv[0][1] == "کارشناس فروش",
                  f"{iv[0][0]} — {iv[0][1]}")
            check("همهٔ سؤال‌ها پاسخ گرفتند",
                  iv[0][2] == "6", iv[0][2])
            check("مصاحبه کامل علامت خورد", iv[0][3] == "done", iv[0][3])
            check("علاقهٔ همکاری از پاسخ «coop» برداشته شد",
                  iv[0][4] == "نمایندگی", str(iv[0][4]))
        card = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
        psql("DELETE FROM iee1405.interviews;")

    # ── شرکت ثبت‌شده در ربات، در فهرست و جست‌وجو ──
    # گزارش مالک: «با ثبت شرکت جدید، در لیست شرکت‌ها ثبت نمی‌گردد و در جست‌وجو
    # بالا نمی‌آید.» مسیر کامل /new از گره‌های واقعی گردش‌کار عبور می‌کند.
    if has_mirror:
        psql("DELETE FROM crm.organizations WHERE legal_name = 'آزمون سرتاسری ثبت ربات';")
        psql("UPDATE iee1405.bot_sessions SET state = 'idle', payload = '{}' "
             "WHERE chat_id = $1;", [OWNER_CHAT])
        for i, txt in enumerate(["/new", "آزمون سرتاسری ثبت ربات", "TAB_MV", "41-07"]):
            psql(query_of("🧠 پردازش در PostgreSQL", wf),
                 [json.dumps(msg(8401 + i, OWNER_CHAT, txt), ensure_ascii=False)])
            for r in psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf)):
                psql(query_of("✅ ثبت ارسال", wf),
                     [int(r[0]), '{"ok":true,"result":{"message_id":50}}'])

        saved = psql("SELECT code FROM crm.organizations "
                     "WHERE legal_name = 'آزمون سرتاسری ثبت ربات'")
        check("شرکت تازه با /new در CRM ثبت شد", len(saved) == 1, str(len(saved)))

        if saved:
            new_org = saved[0][0]
            psql(query_of("🧠 پردازش در PostgreSQL", wf),
                 [json.dumps(msg(8410, OWNER_CHAT, "/list"), ensure_ascii=False)])
            row = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
            check("فهرست شرکت‌ها، بخش «ثبت‌شده در ربات» را دارد",
                  row and "ثبت" in row[0][2] and "ربات" in row[0][2],
                  row[0][2][:40] if row else "—")
            check("دکمهٔ کارت همان شرکت روی فهرست هست",
                  row and row[0][3] and ("o:" + new_org) in row[0][3],
                  (row[0][3] or "—")[:60] if row else "—")
            for r in row:
                psql(query_of("✅ ثبت ارسال", wf),
                     [int(r[0]), '{"ok":true,"result":{"message_id":51}}'])

            psql(query_of("🧠 پردازش در PostgreSQL", wf),
                 [json.dumps(msg(8411, OWNER_CHAT, "سرتاسری ثبت"), ensure_ascii=False)])
            srow = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
            check("جست‌وجو شرکت ثبت‌شده را پیدا می‌کند",
                  srow and "آزمون سرتاسری ثبت ربات" in srow[0][2],
                  srow[0][2][:40] if srow else "—")
            for r in srow:
                psql(query_of("✅ ثبت ارسال", wf),
                     [int(r[0]), '{"ok":true,"result":{"message_id":52}}'])

            cb = {"update_id": 8412,
                  "callback_query": {"id": "cb11", "data": "o:" + new_org,
                                     "from": {"id": OWNER_CHAT},
                                     "message": {"message_id": 52,
                                                 "chat": {"id": OWNER_CHAT, "type": "private"}}}}
            psql(query_of("🧠 پردازش در PostgreSQL", wf),
                 [json.dumps(cb, ensure_ascii=False)])
            crow = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
            check("دکمهٔ o: کارت شرکت CRM را می‌آورد",
                  crow and "آزمون سرتاسری ثبت ربات" in crow[0][2],
                  crow[0][2][:40] if crow else "—")
            check("کارت CRM هم پیام قبلی را ویرایش می‌کند (نه پیام تازه)",
                  crow and crow[0][4] == "52", crow[0][4] if crow else "—")
            for r in crow:
                psql(query_of("✅ ثبت ارسال", wf),
                     [int(r[0]), '{"ok":true,"result":{"message_id":53}}'])

        psql("DELETE FROM crm.organizations WHERE legal_name = 'آزمون سرتاسری ثبت ربات';")

    # ── idempotency: همان آپدیت دوباره ──
    before = len(psql("SELECT update_id FROM iee1405.bot_updates"))
    psql(query_of("🧠 پردازش در PostgreSQL", wf),
         [json.dumps(msg(7004, OWNER_CHAT, "شرکت برق‌آوران پارس"), ensure_ascii=False)])
    after = len(psql("SELECT update_id FROM iee1405.bot_updates"))
    dup_org = psql("SELECT count(*) FROM crm.organizations WHERE legal_name = 'شرکت برق‌آوران پارس'")
    check("آپدیت تکراری دوباره پردازش نشد", before == after, f"{before}→{after}")
    check("شرکت تکراری ساخته نشد", dup_org[0][0] == "1", dup_org[0][0])

    # ── اجرای بی‌پیام: باید last_poll_at را تازه کند (باگ طراحی قبلی) ──
    psql("UPDATE iee1405.bot_state SET value = '2000-01-01 00:00:00+00' WHERE key = 'last_poll_at';")
    idle_rows = psql(query_of("⏭ ثبت زمان دریافت", wf))
    fresh = psql("SELECT (value::timestamptz > '2020-01-01'::timestamptz) FROM iee1405.bot_state "
                 "WHERE key = 'last_poll_at'")
    check("اجرای بی‌پیام هم زمان دریافت را ثبت می‌کند",
          fresh and fresh[0][0] == "t", str(fresh))

    # ── بازرسی پاسخ بله (ok:false با HTTP 200) ──
    errors_before = int(psql("SELECT count(*) FROM iee1405.bot_errors")[0][0])
    watch_ok = psql(query_of("🩺 بازرسی پاسخ بله", wf),
                    ['{"ok":true,"result":[]}'])
    check("پاسخ موفق بله خطایی ثبت نمی‌کند",
          int(psql("SELECT count(*) FROM iee1405.bot_errors")[0][0]) == errors_before,
          str(watch_ok)[:80])
    watch_bad = psql(query_of("🩺 بازرسی پاسخ بله", wf),
                     ['{"ok":false,"error_code":401,"description":"Unauthorized"}'])
    check("پاسخ ناموفق بله ثبت می‌شود (نه سکوت)",
          int(psql("SELECT count(*) FROM iee1405.bot_errors")[0][0]) == errors_before + 1,
          str(watch_bad)[:80])
    err_text = psql("SELECT message FROM iee1405.bot_errors ORDER BY occurred_at DESC LIMIT 1")[0][0]
    check("پیام خطا خواناست", "Unauthorized" in err_text, err_text[:60])
    psql("DELETE FROM iee1405.bot_errors WHERE stage = 'bale_getupdates'")

    # ── جریان‌های باقی‌مانده روی داده واقعی ──
    code = org[0][0]
    flows = [
        (8001, f"/log {code} | جلسه با مدیر فنی، نیاز به تابلوی ۲۰kV | ارسال کاتالوگ"),
        (8002, f"/cap {code} | تولید تابلوی MV تا 36kV"),
        (8003, f"/visit {code}"),
        (8004, f"/task {code} | تماس با مدیرعامل | 2"),
        (8005, f"/find برق‌آوران"),
        (8006, f"/org {code}"),
    ]
    for uid, txt in flows:
        psql(query_of("🧠 پردازش در PostgreSQL", wf),
             [json.dumps(msg(uid, OWNER_CHAT, txt), ensure_ascii=False)])

    replies = [r[2] for r in psql(query_of("📤 پاسخ‌های آماده ارسال", wf))]
    check("مذاکره ثبت شد", any("مذاکره ثبت شد" in r for r in replies))
    check("توانمندی ثبت شد", any("توانمندی ثبت شد" in r for r in replies))
    check("بازدید ثبت شد", any("بازدید ثبت شد" in r for r in replies))
    check("پیگیری ثبت شد", any("پیگیری ثبت شد" or "ثبت شد" in r for r in replies))
    check("جست‌وجو نتیجه داد", any("نتایج جست‌وجو" in r for r in replies))
    check("کارت شرکت ساخته شد", any("ORG-" in r and "غرفه" in r for r in replies))

    tasks = psql("SELECT count(*) FROM crm.tasks WHERE status = 'open'")
    inter = psql("SELECT count(*) FROM crm.interactions")
    check("وظیفه در پایگاه‌داده ساخته شد", int(tasks[0][0]) >= 2, tasks[0][0])
    check("تعامل در پایگاه‌داده ثبت شد", int(inter[0][0]) >= 1, inter[0][0])

    audit = psql("SELECT count(*) FROM crm.audit_events")
    check("ردیف ممیزی ثبت شد", int(audit[0][0]) >= 5, audit[0][0])

    # ── گره‌های زنجیره دریافت: ورودی گره HTTP باید واقعاً وجود داشته باشد ──
    # باگ واقعی ۰.۱.۹: گره ضربان فقط {at} می‌داد و گره HTTP بعد از آن
    # $json.offset را undefined می‌دید → offset=NaN → بله: 400 malformed request.
    beat = next(n for n in wf["nodes"] if n["name"] == "💓 ضربان دریافت")
    get = next(n for n in wf["nodes"] if n["name"] == "📥 دریافت پیام‌ها")
    offset_expr = next(
        q["value"] for q in get["parameters"]["queryParameters"]["parameters"]
        if q["name"] == "offset"
    )
    field = offset_expr.replace("={{", "").replace("}}", "").replace("$json.", "").strip()
    psql("BEGIN;")
    beat_out = psql(beat["parameters"]["query"])
    psql("ROLLBACK;")
    # نام ستون‌ها از psql به شکل «نام» برمی‌گردد؛ خود تابع را هم می‌سنجیم
    beat_now = psql("SELECT iee1405.poll_offset() + 1 AS next_offset, iee1405.poll_heartbeat() AS at")
    check("گره ضربان، next_offset را برمی‌گرداند", len(beat_now[0]) == 2, str(beat_now[0]))
    check(f"عبارت offset گره HTTP فیلد «{field}» را از ورودی می‌خواند",
          field == "next_offset", offset_expr)
    check("عبارت offset هرگز NaN نمی‌شود (بدون محاسبه در n8n)",
          "Number(" not in offset_expr, offset_expr)

    psql("ROLLBACK;")

    # ── گردش‌کارهای زمان‌بندی‌شده ──
    for wfname in ("wf-02-reminders.json", "wf-03-digest.json", "wf-04-health.json"):
        w = json.loads((WF / wfname).read_text(encoding="utf-8"))
        pg = [n for n in w["nodes"] if n["type"].endswith("postgres")][0]
        psql("BEGIN;")
        out = psql(pg["parameters"]["query"], fail_ok=True)
        psql("ROLLBACK;")
        check(f"{wfname} پرس‌وجو اجرا شد", True, f"{len(out)} ردیف")

    # ── رفتار دسته‌ای دریافت: ترتیب، offset و پاسخ تکراری ──
    # واقعیت روی سرور: پس از قطعی، ۸ «/start» با هم می‌رسند. سه چیز باید درست
    # باشد: offset جلو برود (نه صفر بماند)، فقط یک راهنما فرستاده شود، و
    # آپدیتی که پردازش نشد گردش‌کار را در حلقه بی‌پایان نیندازد.
    psql("DELETE FROM iee1405.bot_updates;")
    psql("DELETE FROM iee1405.bot_errors;")
    psql("SELECT iee1405.poll_reset(0);")
    psql("UPDATE crm.users SET bale_chat_id = $1 WHERE username = 'ahmad';", [OWNER_CHAT])

    batch = [msg(8001, OWNER_CHAT, "/start"), msg(8002, OWNER_CHAT, "/start"),
             msg(8003, OWNER_CHAT, "/start")]
    psql("SELECT iee1405.poll_watch($1::jsonb);", [json.dumps({"ok": True, "result": batch})])
    for u in batch:
        psql("SELECT * FROM iee1405.bot_dispatch_json($1::jsonb);", [json.dumps(u, ensure_ascii=False)])
    off = psql("SELECT iee1405.poll_advance();")[0][0]
    check("offset بعد از یک دسته سه‌تایی جلو رفت", off == "8003", off)

    pend = psql("SELECT count(*) FROM iee1405.pending_replies(20);")[0][0]
    check("سه «/start» تکراری یک راهنما می‌فرستد", pend == "1", pend)
    kept = psql("SELECT count(*) FROM iee1405.bot_updates;")[0][0]
    check("همه سه آپدیت ثبت شدند (هیچ داده‌ای دور نریخته شد)", kept == "3", kept)

    psql("SELECT iee1405.poll_watch($1::jsonb);", [json.dumps({"ok": True, "result": []})])
    off2 = psql("SELECT iee1405.poll_advance();")[0][0]
    check("دسته خالی offset را عقب نمی‌برد", off2 == "8003", off2)

    # آپدیتی که پردازش نشود نباید باعث طوفان درخواست شود
    psql("SELECT iee1405.poll_reset(0);")
    psql("SELECT iee1405.poll_watch($1::jsonb);",
         [json.dumps({"ok": True, "result": [{"update_id": 9001}, {"update_id": 9002}]})])
    off3 = psql("SELECT iee1405.poll_advance();")[0][0]
    check("آپدیت پردازش‌نشده offset را قفل نمی‌کند", off3 == "9002", off3)
    lost = psql("SELECT count(*) FROM iee1405.bot_errors WHERE stage = 'unrecorded';")[0][0]
    check("آپدیت گم‌شده ثبت شد", lost == "2", lost)
    psql("SELECT iee1405.poll_advance();")
    lost2 = psql("SELECT count(*) FROM iee1405.bot_errors WHERE stage = 'unrecorded';")[0][0]
    check("ثبت گم‌شده تکرار نمی‌شود", lost2 == "2", lost2)

    # ── ثبت ارسال بر اساس پاسخ واقعی بله ──
    # باگ واقعی ۰.۱.۱۱: گره ثبت ارسال update_id را از $json می‌خواند که در
    # خروجی sendMessage وجود ندارد → mark_delivered(NULL) → پیام هر ۲۰ ثانیه
    # دوباره فرستاده می‌شد.
    psql("DELETE FROM iee1405.bot_updates WHERE update_id BETWEEN 9101 AND 9102;")
    psql("DELETE FROM iee1405.bot_errors;")
    psql("INSERT INTO iee1405.bot_updates (update_id, chat_id, raw, reply_text) "
         "VALUES (9101, 900001, '{}'::jsonb, 'سلام'), (9102, 900001, '{}'::jsonb, 'سلام');")

    ok = psql("SELECT iee1405.mark_sent(9101, $1::jsonb);", ['{"ok":true,"result":{"message_id":9}}'])[0][0]
    check("ارسال موفق «تحویل‌شده» ثبت می‌شود", ok == "delivered", ok)
    left = psql("SELECT count(*) FROM iee1405.pending_replies(50) WHERE update_id = 9101;")[0][0]
    check("پیام تحویل‌شده در صف نمی‌ماند", left == "0", left)

    bad = '{"ok":false,"error_code":400,"description":"chat not found"}'
    results = [psql("SELECT iee1405.mark_sent(9102, $1::jsonb);", [bad])[0][0] for _ in range(5)]
    check("ارسال ناموفق تا ۵ بار تلاش می‌کند", results[:4] == ["retry"] * 4, results[:4])
    check("بعد از ۵ تلاش رها می‌شود (حلقه بی‌پایان نمی‌شود)", results[4] == "gave-up", results[4])
    errs = psql("SELECT count(*) FROM iee1405.bot_errors WHERE stage = 'send';")[0][0]
    check("هر تلاش ناموفق در bot_errors ثبت می‌شود", errs == "5", errs)
    noid = psql("SELECT iee1405.mark_sent(NULL, NULL);")[0][0]
    check("شناسه تهی، خطا نمی‌دهد", noid == "no-id", noid)

    # ── دسترسی‌های نقش واقعی (iee_app) ──
    # خطای واقعی روی سرور: «permission denied for sequence bot_errors_id_seq»
    # و «permission denied for table users». هیچ‌کدام در نقش postgres دیده
    # نمی‌شوند، پس کل مسیر ربات باید با همان نقش n8n آزموده شود.
    psql("DELETE FROM iee1405.bot_errors;")
    psql("DELETE FROM iee1405.bot_updates;")
    psql("SELECT iee1405.poll_reset(0);")
    psql("UPDATE crm.users SET bale_chat_id = $1 WHERE username = 'ahmad';", [OWNER_CHAT])

    gaps = psql_as("iee_app", "SELECT count(*) FROM iee1405.privilege_gaps();")[0][0]
    check("نقش iee_app کمبود دسترسی ندارد", gaps == "0", gaps)

    # دقیقاً همان INSERTی که خطای سرور داد: بدون USAGE روی سیکوئنس، شکست می‌خورد.
    # (فراخوانی bot_dispatch_json به‌تنهایی این را نشان نمی‌دهد، چون برای پیام
    # مجاز مسیر خطا طی نمی‌شود و به bot_errors نمی‌نویسد.)
    try:
        psql_as("iee_app", "BEGIN; INSERT INTO iee1405.bot_errors (stage, message) "
                           "VALUES ('e2e', 'x') RETURNING id; ROLLBACK;")
        seq_ok = True
    except RuntimeError:
        seq_ok = False
    check("iee_app می‌تواند در bot_errors بنویسد (سیکوئنس USAGE دارد)", seq_ok)
    seq_priv = psql("SELECT has_sequence_privilege('iee_app', "
                    "'iee1405.bot_errors_id_seq', 'USAGE');")[0][0]
    check("USAGE روی bot_errors_id_seq صریحاً تأیید شد", seq_priv == "t", seq_priv)

    as_app_errors = []
    for i, text in enumerate(["/start", "/help", "/new", "شرکت آزمون دسترسی", "1",
                              "38-12", "/today", "/find پارس", "/status", "/cancel"]):
        uid = 9800 + i
        upd = json.dumps(msg(uid, OWNER_CHAT, text), ensure_ascii=False)
        try:
            st = psql_as("iee_app", "SELECT status FROM iee1405.bot_dispatch_json($1::jsonb);", [upd])[0][0]
        except RuntimeError as e:
            as_app_errors.append(f"{text}: {e}")
            continue
        if st == "error":
            as_app_errors.append(text)
    check("کل مسیر ربات با نقش iee_app بدون خطا اجرا شد", not as_app_errors, str(as_app_errors[:3]))

    db_errs = psql("SELECT count(*) FROM iee1405.bot_errors;")[0][0]
    check("هیچ خطای دسترسی در bot_errors نماند", db_errs == "0", db_errs)

    # ارسال هم باید با همین نقش ثبت شود (سیکوئنس bot_errors و bot_updates)
    try:
        psql_as("iee_app", "SELECT iee1405.mark_sent($1::bigint, $2::jsonb);",
                ["9800", '{"ok":false,"error_code":400}'])
        send_ok = True
    except RuntimeError:
        send_ok = False
    check("ثبت ارسال ناموفق با iee_app مجاز است", send_ok)

    # ── پیمایش خالی و بازخوانی ──
    # واقعیت روی سرور: وقتی result=[] است، گره پردازش صفر ردیف می‌دهد. بدون
    # alwaysOutputData، n8n همه گره‌های بعدی (از جمله ارسال پاسخ‌های معوق) را
    # رد می‌کند و تضمین تحویل می‌شکند.
    dispatch = node("🧠 پردازش در PostgreSQL", wf)
    check("گره پردازش در پیمایش خالی زنجیره را قطع نمی‌کند",
          dispatch.get("alwaysOutputData") is True)

    rows = psql("SELECT count(*) FROM iee1405.bot_dispatch_json('{}'::jsonb);")[0][0]
    check("ورودی خالی {} خطا نمی‌دهد و ردیفی نمی‌سازد", rows == "0", rows)

    # بازخوانی باید ایمن باشد: پردازش دوباره همان آپدیت‌ها → همه duplicate
    psql("DELETE FROM iee1405.bot_updates;")
    psql("DELETE FROM iee1405.bot_errors;")
    psql("SELECT iee1405.poll_reset(0);")
    replay = [msg(9901, OWNER_CHAT, "/start"), msg(9902, OWNER_CHAT, "/help")]
    seq_status = []
    for _ in range(2):                      # دو دور کامل روی همان دو آپدیت
        psql("SELECT iee1405.poll_watch($1::jsonb);",
             [json.dumps({"ok": True, "result": replay})])
        for u in replay:
            r = psql("SELECT status FROM iee1405.bot_dispatch_json($1::jsonb);",
                     [json.dumps(u, ensure_ascii=False)])
            seq_status.append(r[0][0])
        psql("SELECT iee1405.poll_advance();")
        for rid in [x[0] for x in psql("SELECT update_id FROM iee1405.pending_replies(20);")]:
            psql("SELECT iee1405.mark_sent($1::bigint, $2::jsonb);", [rid, '{"ok":true}'])

    check("دور اول آپدیت‌ها را پردازش می‌کند", seq_status[:2] == ["ok", "ok"], str(seq_status[:2]))
    check("دور دوم همه را «تکراری» می‌شناسد (بازخوانی ایمن است)",
          seq_status[2:] == ["duplicate", "duplicate"], str(seq_status[2:]))
    total = psql("SELECT count(*) FROM iee1405.bot_updates;")[0][0]
    check("بازخوانی داده تکراری نمی‌سازد", total == "2", total)
    sent = psql("SELECT count(*) FROM iee1405.bot_updates WHERE reply_text IS NOT NULL;")[0][0]
    check("بازخوانی پیام تکراری نمی‌فرستد", sent == "1", sent)

    # ── نگهبان سلامت: خودترمیمی واقعی + سکوت ──
    # باگ واقعی ۰.۱.۱۶: «WITH rec AS (SELECT recover_if_dead())» هرگز اجرا
    # نمی‌شد (هرس CTE) و هشدار هم فاصله نداشت → ۴۸ پیام در روز.
    # پیش‌شرط روشن: بدون خطا، پیمایش تازه، بدون قبضه قبلی
    psql("DELETE FROM iee1405.bot_errors;")
    psql("SELECT iee1405.health_alert_reset();")
    psql("UPDATE iee1405.bot_state SET value = clock_timestamp()::text WHERE key = 'last_poll_at';")
    health = psql("SELECT count(*) FROM iee1405.health_watch();")[0][0]
    check("در حالت سالم هیچ هشدار سلامتی نمی‌آید", health == "0", health)

    psql("INSERT INTO iee1405.bot_errors (stage, message) VALUES ('e2e-health', 'x');")
    psql("SELECT iee1405.health_alert_reset();")   # بازه سکوت را صفر می‌کنیم
    # هشدار سلامت به **همهٔ** دارندگان نقش owner می‌رود، پس انتظار = تعداد آن‌ها.
    n_owners = psql("SELECT count(*) FROM crm.users WHERE role = 'owner' "
                    "AND is_active AND bale_chat_id IS NOT NULL")[0][0]
    h1 = psql("SELECT count(*) FROM iee1405.health_watch();")[0][0]
    h2 = psql("SELECT count(*) FROM iee1405.health_watch();")[0][0]
    check("با وجود خطا برای هر owner یک هشدار می‌آید", h1 == n_owners, f"{h1} از {n_owners}")
    check("اجرای بعدی همان هشدار را تکرار نمی‌کند (بازه ۳ ساعت)", h2 == "0", h2)
    h3 = psql("SELECT count(*) FROM iee1405.health_watch('0 seconds');")[0][0]
    check("پس از پایان بازه، هشدار دوباره مجاز است", h3 == n_owners, f"{h3} از {n_owners}")

    # ── فهرست دکمه‌ای شرکت‌ها در همان مسیر واقعی گردش‌کار ──
    # این بخش عمداً از گره‌های خودِ wf-01 استفاده می‌کند (نه فراخوانی مستقیم تابع)
    # تا اثبات شود دکمه‌ها از همان لوله به صف ارسال می‌رسند.
    if has_mirror:
        psql("UPDATE iee1405.bot_sessions SET state = 'idle', payload = '{}' "
             "WHERE chat_id = $1;", [OWNER_CHAT])
        psql(query_of("🧠 پردازش در PostgreSQL", wf),
             [json.dumps(msg(8101, OWNER_CHAT, "🏢 لیست شرکت‌ها"), ensure_ascii=False)])
        page = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
        check("دکمهٔ «لیست شرکت‌ها» یک پاسخ در صف گذاشت", len(page) == 1, str(len(page)))
        if page:
            p1_uid, p1_chat, p1_text, p1_markup = int(page[0][0]), int(page[0][1]), page[0][2], page[0][3]
            check("پاسخ فهرست، دکمهٔ شیشه‌ای دو‌ستونی دارد",
                  "inline_keyboard" in (p1_markup or "") and "c:" in (p1_markup or ""),
                  (p1_markup or "")[:70])
            # دکمهٔ «صفحه بعد» را مثل بله به گردش‌کار می‌دهیم
            nxt = None
            import re as _re
            m = _re.search(r'"callback_data":\s*"(l:\d+)"', p1_markup or "")
            # آخرین l:<n> در JSON ردیف ناوبری، همان «صفحه بعد» است
            all_l = _re.findall(r'"callback_data":\s*"(l:\d+)"', p1_markup or "")
            if all_l:
                nxt = all_l[-1]
            psql(query_of("✅ ثبت ارسال", wf),
                 [p1_uid, '{"ok":true,"result":{"message_id":11}}'])
            if nxt:
                cb = {"update_id": 8102,
                      "callback_query": {"id": "cb1", "data": nxt,
                                         "from": {"id": OWNER_CHAT},
                                         "message": {"message_id": 11,
                                                     "chat": {"id": OWNER_CHAT, "type": "private"}}}}
                rows = psql(query_of("🧠 پردازش در PostgreSQL", wf),
                            [json.dumps(cb, ensure_ascii=False)])
                page2 = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
                check("دکمهٔ «صفحه بعد» از مسیر گردش‌کار عبور کرد و پاسخ ساخت",
                      len(page2) == 1, str(len(page2)))
                if page2:
                    check("صفحهٔ دوم واقعاً صفحهٔ دیگری است",
                          page2[0][2] != p1_text, page2[0][2][:40])
                    psql(query_of("✅ ثبت ارسال", wf),
                         [int(page2[0][0]), '{"ok":true,"result":{"message_id":12}}'])
            else:
                check("دکمهٔ ناوبری در صفحه‌کلید پیدا شد", False, (p1_markup or "")[:60])

        # انتخاب با شماره: مسیر بی‌دکمه (اگر بله callback_query ندهد)
        psql(query_of("🧠 پردازش در PostgreSQL", wf),
             [json.dumps(msg(8103, OWNER_CHAT, "3"), ensure_ascii=False)])
        numbered = psql(query_of("📤 پاسخ\u200cهای آماده ارسال", wf))
        check("شمارهٔ شرکت (مسیر بی‌دکمه) کارت ساخت",
              len(numbered) == 1 and "🏭" in numbered[0][2],
              numbered[0][2][:40] if numbered else "—")
        for r in numbered:
            psql(query_of("✅ ثبت ارسال", wf),
                 [int(r[0]), '{"ok":true,"result":{"message_id":13}}'])
    else:
        check("آینه بارگذاری شده (برای آزمون فهرست)", False, "barghpa خالی است")

    # خودترمیمی باید حتی در حالت سالم هم اجرا شود
    psql("DELETE FROM iee1405.bot_errors;")
    psql("SELECT iee1405.health_alert_reset();")
    psql("UPDATE iee1405.bot_state SET value = "
         "(clock_timestamp() - interval '40 minutes')::text WHERE key = 'last_poll_at';")
    psql("SELECT count(*) FROM iee1405.health_watch();")
    rec = psql("SELECT count(*) FROM iee1405.bot_errors WHERE stage = 'self_recovery';")[0][0]
    check("خودترمیمی واقعاً اجرا می‌شود (نه در کات هرس‌شده)", rec == "1", rec)
    fresh = psql("SELECT value::timestamptz > clock_timestamp() - interval '1 minute' "
                 "FROM iee1405.bot_state WHERE key = 'last_poll_at';")[0][0]
    check("خودترمیمی زمان پیمایش را جلو می‌برد", fresh == "t", fresh)

    print(f"\n{len(PASS)} موفق · {len(FAIL)} ناموفق")
    if FAIL:
        print("ناموفق‌ها:", ", ".join(FAIL))
    return 0 if not FAIL else 1


if __name__ == "__main__":
    sys.exit(main())
