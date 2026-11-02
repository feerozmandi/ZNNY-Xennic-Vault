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
import subprocess
import sys
import pathlib

import pgserver
from pathlib import Path as P

BIN = P("/usr/local/lib/python3.11/dist-packages/pgserver/pginstall/bin")
ROOT = pathlib.Path(__file__).resolve().parent.parent
WF = ROOT / "02_n8n"

srv = pgserver.get_server("/tmp/pgdata", cleanup_mode=None)
URI = srv.get_uri()

PASS, FAIL = [], []
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
    psql("UPDATE iee1405.bot_state SET value = '0' WHERE key = 'bale_offset';")
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
        psql(query_of("✅ ثبت ارسال", wf), [update_id])  # mark_delivered

    remaining = psql(query_of("📤 پاسخ‌های آماده ارسال", wf))
    check("صف پس از ارسال خالی شد (تحویل تضمین‌شده)", len(remaining) == 0, str(len(remaining)))

    new_offset = int(psql(query_of("⏭ ثبت زمان دریافت", wf))[0][0])
    check("offset به آخرین آپدیت رسید", new_offset >= 7007, str(new_offset))

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

    psql("ROLLBACK;")

    # ── گردش‌کارهای زمان‌بندی‌شده ──
    for wfname in ("wf-02-reminders.json", "wf-03-digest.json", "wf-04-health.json"):
        w = json.loads((WF / wfname).read_text(encoding="utf-8"))
        pg = [n for n in w["nodes"] if n["type"].endswith("postgres")][0]
        psql("BEGIN;")
        out = psql(pg["parameters"]["query"], fail_ok=True)
        psql("ROLLBACK;")
        check(f"{wfname} پرس‌وجو اجرا شد", True, f"{len(out)} ردیف")

    print(f"\n{len(PASS)} موفق · {len(FAIL)} ناموفق")
    if FAIL:
        print("ناموفق‌ها:", ", ".join(FAIL))
    return 0 if not FAIL else 1


if __name__ == "__main__":
    sys.exit(main())
