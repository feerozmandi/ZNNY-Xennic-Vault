#!/usr/bin/env python3
"""برنامهٔ روزهای بازدید از فهرست پایلوت — فقط‌خواندنی.

  python3 build_plan.py --days 4                       # می‌سازد، چیزی در پایگاه نمی‌نویسد
  python3 build_plan.py --days 4 --out ../exports/plan

خروجی:
  plan.html  — یک صفحهٔ A4 برای هر روز، با ستون خالیِ «نتیجه» برای دست‌نویس
  plan.csv   — همان برنامه برای بازبینی

قواعد صریح:
  * هیچ شرکتی از فهرست تأییدشده کم یا زیاد نمی‌شود؛ هر نامزد دقیقاً یک‌بار می‌آید.
  * سالن‌ها به‌صورت گروهی بین روزها پخش می‌شوند تا در یک روز پراکندگی نداشته باشیم.
  * ترتیب سالن‌ها یک **قرارداد** است، نه نقشهٔ تأییدشده؛ نقشهٔ نمایشگاه دیده نشده.
  * هشدارها بالای صفحه می‌آید: خانواده‌های هم‌نام، سالن‌های بدون پوشش، و اطمینان تماس.
"""
from __future__ import annotations

import argparse
import csv
import html
from pathlib import Path

import bgdb

HALL_ORDER = ["38A", "38B", "38", "40", "41", "44A", "44B", "31A", "31B", "فضای باز"]
CONF_FA = {"official": "سایت رسمی", "guessed": "حدس دامنه", "portal": "پورتال",
           "web_search": "جست‌وجوی وب", "unknown": "نامشخص"}

CSS = """
@page{size:A4;margin:12mm}
*{box-sizing:border-box}
body{font-family:Vazirmatn,Tahoma,sans-serif;direction:rtl;margin:0;color:#1c1c1c;line-height:1.6}
.day{page-break-after:always;padding:4mm}
.day:last-child{page-break-after:auto}
h1{font-size:14pt;margin:0 0 3mm}
h2{font-size:12pt;margin:0 0 2mm}
table{width:100%;border-collapse:collapse;font-size:9pt}
th,td{border:1px solid #999;padding:1.4mm;vertical-align:top;text-align:right}
th{background:#eee}
td.notes{height:12mm}
.meta{font-size:8.5pt;color:#555;margin:0 0 2mm}
.warn{border:1px solid #d4a017;background:#fff8e6;padding:2mm;font-size:9pt;margin:0 0 3mm}
.tag{font-size:8pt;background:#eef4f8;border-radius:3px;padding:0 2px}
.tag.cov{background:#fff3d6;border:1px solid #d4a017}
.check{font-size:9pt;margin:2mm 0 0;padding-right:5mm}
.check li{margin:0.8mm 0}
"""


def fa(n) -> str:
    """ارقام لاتین → فارسی، برای چاپ کاغذی (شمارهٔ سالن و تماس دست‌نخورده می‌مانند)."""
    return str(n).translate(str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹"))


def load(con):
    return con.execute("""
        SELECT p.rank, p.reason, p.first_check, c.id, c.name_fa,
               v.halls, v.phones, v.emails, v.provenance_class, v.contact_confidence
          FROM visit_pilot p
          JOIN company c ON c.id = p.company_id
          LEFT JOIN v_company_card v ON v.company_id = c.id
         ORDER BY p.rank
    """).fetchall()


def families(rows) -> list[list[str]]:
    """خوشه‌های هم‌نام: شرکت‌هایی که دو واژهٔ معنادار مشترک دارند.

    واژه‌های خیلی عمومی (که در بیش از نیمی از نام‌ها آمده‌اند) نادیده گرفته
    می‌شوند تا هشدار فقط خانوادهٔ واقعی را نشان دهد، نه هر نام مشابه.
    """
    names = [r["name_fa"] for r in rows]
    toks = [bgdb.name_tokens(n) for n in names]
    freq: dict[str, int] = {}
    for s in toks:
        for w in s:
            freq[w] = freq.get(w, 0) + 1
    generic = {w for w, c in freq.items() if c > max(2, len(names) // 2)}
    parent = list(range(len(names)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            if len((toks[i] - generic) & (toks[j] - generic)) >= 2:
                parent[find(i)] = find(j)
    groups: dict[int, list[str]] = {}
    for i, n in enumerate(names):
        groups.setdefault(find(i), []).append(n)
    return [g for g in groups.values() if len(g) > 1]


def warnings(rows) -> list[str]:
    out = []
    for i, g in enumerate(families(rows), 1):
        out.append(f"خانوادهٔ {fa(i)} (ممکن است یک گروه باشند، نه رقیب): "
                   + "، ".join(f"«{n}»" for n in g))
    # پوشش سالن‌ها
    covered = {h.strip() for r in rows for h in (r["halls"] or "").split("·") if h.strip()}
    missing = [h for h in HALL_ORDER if h not in covered]
    if missing:
        out.append("این سالن‌ها هیچ نامزدی در فهرست ندارند: " + " · ".join(missing)
                   + " — یا شرکت‌هایشان هیچ اطلاعات تماسی ندارند (با --include-empty "
                     "بررسی کنید) یا امتیازشان پایین بوده (با --per-hall یا --max-group "
                     "دوباره انتخاب کنید)")
    # اطمینان
    conf = {}
    for r in rows:
        for x in (r["contact_confidence"] or "").split(","):
            if x:
                conf[x] = conf.get(x, 0) + 1
    if conf:
        out.append("اطمینان تماس در فهرست: " + " · ".join(
            f"{CONF_FA.get(k, k)}={fa(v)}" for k, v in sorted(conf.items(), key=lambda kv: -kv[1])))
    guessed = sum(1 for r in rows if "guessed" in (r["contact_confidence"] or ""))
    unknown = sum(1 for r in rows if "unknown" in (r["contact_confidence"] or ""))
    if guessed or unknown:
        out.append(f"{fa(guessed)} شرکت دادهٔ تماس حدسی و {fa(unknown)} شرکت منبع نامشخص دارند: "
                   "شماره را پیش از هر پیشنهاد تأیید کنید.")
    return out


def split_days(rows, days: int):
    """سالن‌ها را به‌ترتیب قرارداد به چند تکهٔ **پیوسته** می‌شکند.

    پیوسته بودن مهم است: هر روز یک بازهٔ پشت‌سرهم از سالن‌ها می‌شود، نه چهار
    گوشهٔ سالن. نقطه‌های برش طوری انتخاب می‌شوند که سنگین‌ترین روز کم‌ترین
    تعداد شرکت را داشته باشد (برش بهینه، نه حریصانه).
    """
    by_hall: dict[str, list] = {}
    for r in rows:
        hs = [h.strip() for h in (r["halls"] or "").split("·") if h.strip()] or ["—"]
        by_hall.setdefault(hs[0], []).append(r)
    order = sorted(by_hall, key=lambda h: (HALL_ORDER.index(h) if h in HALL_ORDER else 99, h))
    w = [len(by_hall[h]) for h in order]
    n, k = len(order), min(max(days, 1), len(order))

    # dp[j][i] = کم‌ترین بیشینهٔ بار برای تقسیم i سالن اول به j تکه
    inf = (float("inf"), float("inf"))
    dp = [[inf] * (n + 1) for _ in range(k + 1)]
    back = [[0] * (n + 1) for _ in range(k + 1)]
    dp[0][0] = (0, 0)
    pre = [0]
    for x in w:
        pre.append(pre[-1] + x)
    for j in range(1, k + 1):
        for i in range(1, n + 1):
            for s in range(j - 1, i):
                if dp[j - 1][s] == inf:
                    continue
                load = pre[i] - pre[s]
                cand = (max(dp[j - 1][s][0], load), dp[j - 1][s][1] + load * load)
                if cand < dp[j][i]:
                    dp[j][i] = cand
                    back[j][i] = s
    cuts, i = [], n
    for j in range(k, 0, -1):
        s = back[j][i]
        cuts.append((s, i))
        i = s
    cuts.reverse()

    buckets = []
    for s, e in cuts:
        halls = order[s:e]
        day_rows = [r for h in halls for r in by_hall[h]]
        buckets.append({"halls": halls, "rows": day_rows})
    return [b for b in buckets if b["rows"]]


def render(rows, days: int, planned) -> str:
    w = warnings(rows)
    parts = [f"<!DOCTYPE html><html lang='fa' dir='rtl'><head><meta charset='utf-8'>"
             f"<meta name='viewport' content='width=device-width,initial-scale=1'>"
             f"<title>برنامهٔ بازدید — پایلوت {len(rows)} شرکت</title>"
             f"<style>{CSS}</style></head><body>"]
    parts.append("<div class='day'><h1>برنامهٔ بازدید نمایشگاه برق ۱۴۰۵ — پایلوت "
                 f"{fa(len(rows))} شرکت</h1>"
                 f"<div class='meta'>۱۶–۱۹ آبان ۱۴۰۵ · {fa(days)} روز · ترتیب سالن‌ها قرارداد "
                 "است، نه نقشهٔ تأییدشده؛ پیش از حرکت با نقشهٔ نمایشگاه تطبیق دهید.</div>")
    for i, x in enumerate(w, 1):
        parts.append(f"<div class='warn'>⚠️ {html.escape(x)}</div>")
    parts.append("<ul class='check'>"
                 "<li>صفحه‌های سالن (HTML) روی گوشی ذخیره شود و در حالت پرواز یک‌بار باز شود.</li>"
                 "<li>پیش از حرکت، خروجی JSON تعامل‌ها یک‌بار آزمایش شود.</li>"
                 "<li>برای هر شرکت، ستون «نتیجه» را همان‌جا پر کنید؛ بعد از نمایشگاه بازیابی سخت است.</li>"
                 "<li>شمارهٔ غرفه در منبع نبوده؛ غرفه را از راهنمای نمایشگاه یا تابلو بخوانید و ثبت کنید.</li>"
                 "<li>برچسب <span class='tag cov'>پوشش سالن</span> یعنی این شرکت برای "
                 "پوشش آن سالن آمده، نه برای امتیازش — سر میز کوتاه‌تر بایستید.</li>"
                 "</ul></div>")

    for d, b in enumerate(planned, 1):
        parts.append(f"<div class='day'><h2>روز {fa(d)} — سالن‌ها: "
                     f"{html.escape(' · '.join(b['halls']))} ({fa(len(b['rows']))} شرکت)</h2>")
        parts.append("<div class='meta'>در پایان روز: دکمهٔ «خروجی JSON تعامل‌ها» را بزنید.</div>")
        parts.append("<table><thead><tr><th style='width:6%'>#</th><th style='width:26%'>شرکت</th>"
                     "<th style='width:10%'>سالن</th><th style='width:20%'>تماس</th>"
                     "<th style='width:20%'>اولین کار</th><th style='width:18%'>نتیجه</th>"
                     "</tr></thead><tbody>")
        for r in b["rows"]:
            contact = (r["phones"] or "") + (" | " + r["emails"] if r["emails"] else "")
            conf = CONF_FA.get(r["provenance_class"] or "unknown", "—")
            cov = ("<br><span class='tag cov'>پوشش سالن</span>"
                   if "پوشش سالن" in (r["reason"] or "") else "")
            parts.append(
                f"<tr><td>{fa(r['rank'])}</td>"
                f"<td>{html.escape(r['name_fa'])}<br><span class='tag'>{html.escape(conf)}</span>{cov}</td>"
                f"<td>{html.escape(r['halls'] or '—')}</td>"
                f"<td>{html.escape(contact or '—')}</td>"
                f"<td>{html.escape(r['first_check'] or '—')}</td>"
                f"<td class='notes'></td></tr>")
        parts.append("</tbody></table></div>")
    parts.append("</body></html>")
    return "".join(parts)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(Path.home() / "xennic-data" / "barghpa-26-iee1405"
                                        / "db" / "barghpa_iee1405.sqlite"))
    ap.add_argument("--days", type=int, default=4)
    ap.add_argument("--out", default=str(Path.home() / "xennic-data" / "barghpa-26-iee1405"
                                         / "exports" / "plan"))
    args = ap.parse_args()

    con = bgdb.connect(Path(args.db).expanduser(), readonly=True)
    try:
        rows = load(con)
    except Exception as e:                                # noqa: BLE001
        print("❌ جدول پایلوت خوانده نشد. اول pick_pilot.py --write --approve را اجرا کنید.\n",
              e)
        return 1
    con.close()
    if not rows:
        print("❌ فهرست پایلوت خالی است.")
        return 1

    planned = split_days(rows, args.days)
    out = Path(args.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    (out / "plan.html").write_text(render(rows, len(planned), planned), encoding="utf-8")

    with (out / "plan.csv").open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["day", "halls", "rank", "company", "hall", "phones", "emails",
                    "provenance", "first_check"])
        for d, b in enumerate(planned, 1):
            for r in b["rows"]:
                w.writerow([d, " · ".join(b["halls"]), r["rank"], r["name_fa"],
                            r["halls"], r["phones"] or "", r["emails"] or "",
                            CONF_FA.get(r["provenance_class"] or "unknown", "—"),
                            r["first_check"] or ""])

    print(f"برنامهٔ {len(planned)} روزه ساخته شد: {len(rows)} شرکت")
    for d, b in enumerate(planned, 1):
        print(f"  روز {d}: {' · '.join(b['halls'])} — {len(b['rows'])} شرکت")
    print(f"\n  {out / 'plan.html'}\n  {out / 'plan.csv'}")
    for x in warnings(rows):
        print(f"  ⚠️ {x}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
