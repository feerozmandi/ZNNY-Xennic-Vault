#!/usr/bin/env python3
"""ساخت ابزار بازدید آفلاین: یک صفحه برای هر سالن + فهرست جست‌وجوپذیر.

  python3 build_html.py --db ../db/barghpa_iee1405.sqlite --out ../exports/field

خروجی: HTML تک‌فایلی بدون CDN، قابل باز کردن از حافظهٔ گوشی در حالت پرواز.
  * موبایل: کارت‌های عمودی، دکمهٔ تماس/ایمیل واقعی (tel:/mailto:).
  * چاپ A4: کارت هر شرکت در بلوک چاپی جدا.
  * شمارهٔ غرفه فقط اگر در داده باشد نمایش می‌یابد؛ در غیر این صورت
    «غرفه ثبت نشده» نوشته می‌شود — هرگز حدس زده نمی‌شود.
  * ثبت تعامل در localStorage و خروجی JSON برای ورود به پایگاه.
"""
from __future__ import annotations

import argparse
import html
import json
from datetime import datetime, timezone
from pathlib import Path

import bgdb

CSS = """
:root{--bd:#d6d6d6;--ink:#1c1c1c;--mut:#666;--acc:#0b5c8a;--ok:#1a7f37;--warn:#9a6700}
*{box-sizing:border-box}
body{margin:0;font-family:Vazirmatn,Tahoma,"Iranian Sans",sans-serif;color:var(--ink);
     background:#fafafa;direction:rtl;line-height:1.6}
header{position:sticky;top:0;background:#fff;border-bottom:1px solid var(--bd);padding:.6rem .8rem;z-index:9}
h1{font-size:1.05rem;margin:0 0 .5rem}
.bar{display:flex;gap:.5rem;align-items:center;flex-wrap:wrap}
input[type=search]{flex:1;min-width:9rem;padding:.55rem;border:1px solid var(--bd);border-radius:.5rem;font:inherit}
.btn{padding:.5rem .7rem;border:1px solid var(--bd);border-radius:.5rem;background:#fff;
     font:inherit;cursor:pointer;text-decoration:none;color:var(--acc)}
.btn.pri{background:var(--acc);color:#fff;border-color:var(--acc)}
main{padding:.7rem;max-width:60rem;margin:0 auto}
.card{background:#fff;border:1px solid var(--bd);border-radius:.7rem;padding:.7rem;margin:0 0 .7rem}
.card h2{font-size:.98rem;margin:0 0 .3rem}
.meta{font-size:.78rem;color:var(--mut);margin:.15rem 0}
.prio{font-size:.75rem;background:#eef4f8;color:var(--acc);border-radius:.4rem;padding:.2rem .45rem;display:inline-block}
.prio.zero{background:#fff6e5;color:var(--warn)}
.rows{display:flex;flex-wrap:wrap;gap:.35rem;margin:.45rem 0 0}
.tel,.mail,.web{font-size:.85rem;border:1px solid var(--bd);border-radius:.45rem;
                padding:.3rem .5rem;text-decoration:none;color:var(--ink)}
.tel{border-color:#bfe3c6}.mail{border-color:#cfe0f0}
.none{font-size:.8rem;color:var(--warn)}
.conf-ok{font-size:.72rem;background:#e8f5ec;color:#1a7f37;border-radius:.35rem;padding:.15rem .4rem}
.conf-warn{font-size:.72rem;background:#fff4e5;color:#9a6700;border-radius:.35rem;padding:.15rem .4rem}
.conf-mid{font-size:.72rem;background:#eef1f4;color:#555;border-radius:.35rem;padding:.15rem .4rem}
details{margin-top:.5rem}
summary{font-size:.82rem;color:var(--acc);cursor:pointer}
.acts{display:flex;gap:.35rem;flex-wrap:wrap;margin-top:.5rem}
.acts select,.acts input{font:inherit;font-size:.82rem;padding:.35rem;border:1px solid var(--bd);border-radius:.4rem}
.state{font-size:.75rem;color:var(--ok)}
footer{padding:1rem .7rem 3rem;text-align:center;font-size:.75rem;color:var(--mut)}
#logbar{position:fixed;bottom:0;inset-inline:0;background:#fff;border-top:1px solid var(--bd);
        padding:.5rem .7rem;display:flex;gap:.5rem;align-items:center;font-size:.8rem}
@media print{
  @page{size:A4;margin:12mm}
  body{background:#fff}
  header,#logbar,.acts,.noprint{display:none!important}
  main{max-width:none;padding:0}
  .card{break-inside:avoid;page-break-inside:avoid;border:1px solid #999;margin:0 0 6mm}
  .card h2{font-size:11pt}.meta,.tel,.mail,.web,.prio{font-size:9pt}
  a{color:#000;text-decoration:none}
}
"""

JS = """
const LOG_KEY='bg_interactions_v1';
function load(){try{return JSON.parse(localStorage.getItem(LOG_KEY)||'[]')}catch(e){return []}}
function save(a){localStorage.setItem(LOG_KEY,JSON.stringify(a));render()}
function addIx(o){const a=load();a.push(o);save(a)}
function render(){
  const box=document.getElementById('cnt');
  if(box){const a=load();box.textContent=a.length?('ثبت‌شده: '+a.length):'تعاملی ثبت نشده'}
}
function exportIx(){
  const a=load();
  if(!a.length){alert('چیزی برای خروجی نیست');return}
  const s=JSON.stringify(a,null,0);
  const b=new Blob([s],{type:'application/json'});
  const u=URL.createObjectURL(b);
  const d=new Date().toISOString().slice(0,19).replace(/[:T]/g,'-');
  const l=document.createElement('a');l.href=u;l.download='interactions-'+d+'.json';
  document.body.appendChild(l);l.click();l.remove();
  setTimeout(()=>URL.revokeObjectURL(u),2000);
}
function filter(q){
  q=(q||'').trim().toLowerCase();
  document.querySelectorAll('.card').forEach(c=>{
    c.style.display=(!q||c.dataset.search.includes(q))?'':'none';
  });
}
document.addEventListener('DOMContentLoaded',()=>{
  render();
  const s=document.getElementById('q');
  if(s)s.addEventListener('input',e=>filter(e.target.value));
  document.querySelectorAll('form.ix').forEach(f=>{
    f.addEventListener('submit',ev=>{
      ev.preventDefault();
      const g=n=>f.querySelector('[name='+n+']').value;
      addIx({uid:g('company')+'-'+Date.now(),company:g('company'),company_name:g('cname'),
             at_utc:new Date().toISOString().slice(0,19)+'Z',kind:g('kind'),
             outcome:g('outcome'),next_action:g('next'),next_due:g('due'),note:g('note')});
      f.reset();
      const t=f.querySelector('.state');if(t){t.textContent='✔ ثبت شد';setTimeout(()=>t.textContent='',2500)}
    });
  });
});
"""


def esc(s) -> str:
    return html.escape(str(s if s is not None else ""), quote=True)


def tel_href(v: str) -> str:
    return "tel:" + str(v).translate(str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")).replace(" ", "")


def card(r, ix_lookup) -> str:
    halls = r["halls"] or "—"
    prio = r["priority"] or 0
    reason = r["priority_reason"] or ""
    # غرفه: اول مقدار پاک‌شده، بعد مقدار خام منبع، وگرنه صریحاً «ثبت نشده».
    # هیچ‌گاه از سالن یا نام شرکت حدس زده نمی‌شود.
    if r["booths"]:
        booth_note = f'غرفه {r["booths"]}'
    elif r["booths_raw"]:
        booth_note = f'غرفه (خام منبع، تأییدنشده): {r["booths_raw"]}'
    else:
        booth_note = "غرفه ثبت نشده"
    phones = [p.strip() for p in (r["phones"] or "").split("|") if p.strip()]
    emails = [e.strip() for e in (r["emails"] or "").split("|") if e.strip()]
    socials = [s.strip() for s in (r["socials"] or "").split("|") if s.strip()]

    parts = [f'<article class="card" data-search="{esc(bgdb.norm_text(r["name_fa"]) + " " + bgdb.norm_text(halls))}">']
    parts.append(f'<h2>{esc(r["name_fa"])}</h2>')
    if r["name_en"]:
        parts.append(f'<div class="meta">{esc(r["name_en"])}</div>')
    parts.append(f'<div class="meta">سالن: <b>{esc(halls)}</b> · {esc(booth_note)}'
                 + (f' · استان: {esc(r["province_label"])}' if r["province_label"] else "") + '</div>')
    badge = f'<span class="prio{" zero" if prio == 0 else ""}">اولویت {prio}' + \
            (f' — {esc(reason)}' if reason else '') + '</span>'
    parts.append(f'<div class="meta">{badge}</div>')

    # اطمینان منبع: «حدس دامنه» باید روی کارت دیده شود، نه در حافظهٔ بازدیدکننده
    conf = (r["provenance_class"] or "unknown")
    conf_map = {
        "official": ("منبع: سایت رسمی (ادعای منبع)", "conf-ok"),
        "guessed": ("منبع: حدس دامنه — تأییدنشده", "conf-warn"),
        "portal": ("منبع: پورتال برق‌پا", "conf-mid"),
        "web_search": ("منبع: جست‌وجوی وب", "conf-mid"),
    }
    label, cls = conf_map.get(conf, ("منبع: نامشخص", "conf-mid"))
    parts.append(f'<div class="meta"><span class="{cls}">{esc(label)}</span></div>')

    buttons = []
    for p in phones[:3]:
        buttons.append(f'<a class="tel" href="{esc(tel_href(p))}">📞 {esc(p)}</a>')
    for e in emails[:2]:
        buttons.append(f'<a class="mail" href="mailto:{esc(e)}">✉️ {esc(e)}</a>')
    if r["company_page"]:
        buttons.append(f'<a class="web" href="{esc(r["company_page"])}" target="_blank" rel="noopener">🔗 صفحهٔ برق‌پا</a>')
    if r["website"]:
        w = r["website"]
        buttons.append(f'<a class="web" href="{esc(w)}" target="_blank" rel="noopener">🌐 وب‌سایت</a>')
    if socials:
        parts.append('<div class="rows">' + "".join(
            f'<span class="web">{esc(s)}</span>' for s in socials[:4]) + '</div>')
    if r["official_site"]:
        buttons.append('<span class="web">✅ دامنه در فهرست منابع خودِ فایل آمده</span>')
    if buttons:
        parts.append('<div class="rows">' + "".join(buttons) + '</div>')
    else:
        parts.append('<div class="none">هیچ راه ارتباطی در منبع نبود — «ناقص»، نه «عدم تمایل»</div>')
        if r["google_search"]:
            parts.append('<div class="rows noprint"><a class="web" href="' + esc(r["google_search"])
                         + '" target="_blank" rel="noopener">🔍 جست‌وجوی دستی (نیازمند اینترنت)</a></div>')

    if r["address"]:
        parts.append(f'<div class="meta">آدرس: {esc(r["address"])}</div>')

    ix = ix_lookup.get(r["company_id"], [])
    if ix:
        parts.append('<details open><summary>تعامل‌های ثبت‌شده</summary>' + "".join(
            f'<div class="meta">• {esc(i["at_utc"][:16])} · {esc(i["kind"])} · '
            f'{esc(i["outcome"] or "")} '
            + (f'· بعدی: {esc(i["next_action"])}' if i["next_action"] else '') + '</div>'
            for i in ix) + '</details>')

    parts.append(f'''<div class="acts noprint">
      <form class="ix" data-company="{r["company_id"]}">
        <input type="hidden" name="company" value="{r["company_id"]}">
        <input type="hidden" name="cname" value="{esc(r["name_fa"])}">
        <select name="kind" aria-label="نوع"><option value="visit">بازدید</option>
          <option value="call">تماس</option><option value="note">یادداشت</option>
          <option value="followup">پیگیری</option></select>
        <select name="outcome" aria-label="نتیجه"><option value="interested">علاقه‌مند</option>
          <option value="not_relevant">نامرتبط</option><option value="callback">تماس بعدی</option>
          <option value="quoted">پیش‌فاکتور</option><option value="none">نامشخص</option></select>
        <input name="next" placeholder="اقدام بعدی" maxlength="80">
        <input name="due" type="date" aria-label="موعد">
        <input type="hidden" name="note" value="">
        <button class="btn pri" type="submit">ثبت</button>
        <span class="state"></span>
      </form></div>''')
    parts.append('</article>')
    return "".join(parts)


def page(title: str, body: str, *, with_search: bool, nav: str = "") -> str:
    return f"""<!DOCTYPE html><html lang="fa" dir="rtl"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(title)}</title><style>{CSS}</style></head><body>
<header><h1>{esc(title)}</h1>
<div class="bar">{nav}</div>
{'<div class="bar" style="margin-top:.5rem"><input id="q" type="search" placeholder="جست‌وجوی نام شرکت…" autocomplete="off"><a class="btn" href="#" onclick="window.print();return false">چاپ A4</a></div>' if with_search else ''}
</header><main>{body}</main>
<div id="logbar"><span id="cnt">…</span><button class="btn" onclick="exportIx()">خروجی JSON تعامل‌ها</button></div>
<footer>دادهٔ نمایشگاه برق ۱۴۰۵ · تولید آفلاین · {esc(datetime.now(timezone.utc).strftime('%Y-%m-%d'))}
 · شمارهٔ غرفه فقط از منبع نمایش داده می‌شود</footer>
<script>{JS}</script></body></html>"""


def build(db: Path, out: Path, *, exhibition: str = "iee1405") -> dict:
    # پایگاه را باز می‌کنیم و مهاجرت‌های نبوده را اعمال می‌کنیم؛ وگرنه نما ممکن
    # است قدیمی باشد و ستون‌های تازه (غرفه) بیرون بیفتند.
    con = bgdb.connect(db)
    applied = bgdb.migrate(con)
    if applied:
        print("مهاجرت‌های اعمال‌شده: " + " · ".join(applied))
    rows = con.execute("""
        SELECT c.id AS company_id, c.name_fa, c.name_en, c.website,
               c.company_page, c.province_label,
               v.halls, v.booths, v.booths_raw, v.priority, v.priority_reason,
               v.phones, v.emails, v.socials, v.address, v.contact_count, v.verified,
               v.provenance_class, v.official_site, v.google_search
          FROM company c JOIN v_company_card v ON v.company_id = c.id
         ORDER BY v.priority DESC, c.name_fa
    """).fetchall()
    ix = {}
    try:
        for r in con.execute("SELECT company_id, at_utc, kind, outcome, next_action "
                             "FROM visit_interaction ORDER BY at_utc DESC"):
            ix.setdefault(r["company_id"], []).append(dict(r))
    except Exception:                                    # noqa: BLE001
        pass
    halls = [r["code"] for r in con.execute(
        "SELECT h.code FROM hall h JOIN exhibition e ON e.id=h.exhibition_id "
        "WHERE e.code=? ORDER BY h.code", (exhibition,))]
    con.close()

    out.mkdir(parents=True, exist_ok=True)
    by_hall: dict[str, list] = {h: [] for h in halls}
    multi = []
    for r in rows:
        hs = [h.strip() for h in (r["halls"] or "").split("·") if h.strip()]
        if len(hs) > 1:
            multi.append(r)
        for h in hs:
            by_hall.setdefault(h, []).append(r)

    # فهرست سالن‌ها
    nav = "".join(
        f'<a class="btn" href="hall-{esc(h).replace(" ", "_")}.html">{esc(h)}'
        f' <small>({len(by_hall.get(h, []))})</small></a>' for h in sorted(by_hall))
    idx_body = ['<div class="card noprint"><h2>چطور استفاده کنم؟</h2>'
                '<div class="meta">صفحهٔ هر سالن را باز کنید؛ کارت‌ها به ترتیب اولویت‌اند. '
                'دکمهٔ 📞 تماس می‌گیرد و ✉️ ایمیل می‌سازد (آفلاین کار می‌کند). '
                'ثبت تعامل فقط در همین گوشی ذخیره می‌شود؛ در پایان روز «خروجی JSON» بگیرید '
                'و با log_interaction.py وارد پایگاه کنید.</div></div>']
    if multi:
        idx_body.append('<div class="card"><h2>شرکت‌های چندسالنه</h2>' + "".join(
            f'<div class="meta">{esc(r["name_fa"])} — {esc(r["halls"])}</div>' for r in multi)
            + '</div>')
    (out / "index.html").write_text(
        page("فهرست سالن‌ها — نمایشگاه برق ۱۴۰۵", "".join(idx_body),
             with_search=False, nav=nav), encoding="utf-8")

    made = {"index.html": len(rows)}
    for h, items in by_hall.items():
        body = "".join(card(r, ix) for r in items)
        fname = f"hall-{h.replace(' ', '_')}.html"
        nav2 = f'<a class="btn" href="index.html">← همهٔ سالن‌ها</a>'
        n_off = sum(1 for r in items if (r["provenance_class"] or "") == "official")
        n_guess = sum(1 for r in items if (r["provenance_class"] or "") == "guessed")
        n_none = sum(1 for r in items if (r["contact_count"] or 0) == 0)
        summary = (f'<div class="card noprint"><div class="meta">'
                   f'در این سالن: {len(items)} شرکت · '
                   f'<b>{n_off}</b> با منبع «سایت رسمی» · '
                   f'<b>{n_guess}</b> با «حدس دامنه» (تأییدنشده) · '
                   f'<b>{n_none}</b> بدون هیچ اطلاعات تماس</div></div>')
        (out / fname).write_text(
            page(f"سالن {h} — {len(items)} شرکت", summary + body,
                 with_search=True, nav=nav2),
            encoding="utf-8")
        made[fname] = len(items)

    (out / "interactions-README.txt").write_text(
        "در پایان هر روز بازدید، دکمهٔ «خروجی JSON تعامل‌ها» را بزنید و فایل را با دستور زیر وارد کنید:\n"
        "  python3 log_interaction.py --db ../db/barghpa_iee1405.sqlite --import <file>.json\n",
        encoding="utf-8")
    return made


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(Path.home() / "xennic-data" / "barghpa-26-iee1405"
                                        / "db" / "barghpa_iee1405.sqlite"))
    ap.add_argument("--out", default=str(Path.home() / "xennic-data" / "barghpa-26-iee1405"
                                         / "exports" / "field"))
    ap.add_argument("--exhibition", default="iee1405")
    args = ap.parse_args()
    made = build(Path(args.db).expanduser(), Path(args.out).expanduser(),
                 exhibition=args.exhibition)
    print("ساخته شد:")
    for k, v in made.items():
        print(f"  {k:26s} {v}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
