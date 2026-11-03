#!/usr/bin/env python3
"""انتخاب نامزدهای پایلوت بازدید — پیشنهاد، نه تصمیم.

  python3 pick_pilot.py --n 20                      # فقط نمایش (هیچ نوشتنی)
  python3 pick_pilot.py --n 20 --write --approve \
      --approved-by "احمد فیروزمندی بندپی"          # ثبت فهرست تأییدشده
  python3 pick_pilot.py --csv ../exports/pilot.csv  # خروجی برای بازبینی

قواعد رتبه‌بندی (همه صریح؛ هیچ وزن پنهانی نیست):
  ۱. شرکت باید دست‌کم یک راه ارتباطی داشته باشد (وگرنه پایلوت مذاکره بی‌معنی است)
  ۲. منبع «سایت رسمی» بالاتر از «پورتال» و «حدس دامنه»
  ۳. عضویت در وندور لیست توانیر امتیاز مثبت دارد
  ۴. دانش‌بنیان امتیاز مثبت دارد
  ۵. اولویت محاسبه‌شدهٔ مشارکت (همان که در کارت دیده می‌شود)
  ۶. تنوع سالن: حداکثر `--per-hall` شرکت از هر سالن (پیش‌فرض ۴)
  ۷. با `--cover-halls` اول از هر سالن دست‌کم یک شرکت برداشته می‌شود
     (سالن‌های کوچک‌تر اول)، بعد بقیهٔ جاها با امتیاز پر می‌شود.
     بدون این گزینه رتبه‌بندی فقط‌امتیازی است و سالن کوچک بی‌نامزد می‌ماند.

`first_check` برای هر نامزد نوشته می‌شود: اول چه چیزی را سر میز تأیید کنیم.
"""
from __future__ import annotations

import argparse
import csv
import sys
from datetime import datetime, timezone
from pathlib import Path

import bgdb

CONF_WEIGHT = {"official": 30, "portal": 12, "web_search": 8, "guessed": 0, "unknown": 0}
CONF_LABEL = {
    "official": "سایت رسمی (ادعای منبع)",
    "portal": "پورتال برق‌پا",
    "web_search": "جست‌وجوی وب",
    "guessed": "حدس دامنه — تأییدنشده",
    "unknown": "نامشخص",
}


def candidates(con, n: int, per_hall: int, include_empty: bool,
               max_group: int = 0, cover_halls: bool = False) -> list[dict]:
    rows = con.execute("""
        SELECT c.id, c.name_fa, c.website, c.provenance_class, c.official_site,
               v.halls, v.priority, v.contact_count, v.phones, v.emails,
               v.contact_confidence,
               EXISTS(SELECT 1 FROM company_flag f WHERE f.company_id=c.id
                       AND f.flag='tavanir_vendor') AS tavanir,
               EXISTS(SELECT 1 FROM company_flag f WHERE f.company_id=c.id
                       AND f.flag='daneshbonyan') AS danesh
          FROM company c JOIN v_company_card v ON v.company_id=c.id
         WHERE v.priority IS NOT NULL
    """).fetchall()

    scored = []
    for r in rows:
        if not include_empty and (r["contact_count"] or 0) == 0:
            continue
        conf = r["provenance_class"] or "unknown"
        score = (CONF_WEIGHT.get(conf, 0)
                 + (12 if r["tavanir"] else 0)
                 + (8 if r["danesh"] else 0)
                 + (6 if r["official_site"] else 0)
                 + min(r["priority"] or 0, 100) // 5)
        why = [f"منبع: {CONF_LABEL.get(conf, conf)}"]
        if r["tavanir"]:
            why.append("وندور لیست توانیر")
        if r["danesh"]:
            why.append("دانش‌بنیان")
        if r["official_site"]:
            why.append("دامنه در فهرست منابع فایل")
        if (r["priority"] or 0) > 0:
            why.append(f"اولویت {r['priority']}")

        confs = {x for x in (r["contact_confidence"] or "").split(",") if x}
        if "official" in confs:
            first = "تأیید شماره/ایمیل با سایت رسمی و ثبت شاهد"
        elif confs & {"guessed", "unknown"}:
            first = "تأیید شماره/ایمیل (دادهٔ حدسی) — قبل از هر پیشنهاد"
        else:
            first = "دریافت کارت ویزیت و ثبت شخص رابط"

        scored.append({
            "id": r["id"], "name": r["name_fa"], "halls": r["halls"] or "—",
            "website": r["website"], "conf": conf, "score": score,
            "priority": r["priority"], "contacts": r["contact_count"],
            "phones": r["phones"], "emails": r["emails"], "why": why, "first": first,
        })

    scored.sort(key=lambda d: (-d["score"], -d["contacts"], d["name"]))
    picked, per = [], {}

    def halls_of(c):
        return [h.strip() for h in c["halls"].split("·") if h.strip()] or ["—"]

    def group_ok(c):
        # سقف «خانواده»: چند شرکت با نام مشابه (مثل ایران ترانسفو) پشت‌سرهم نباشند
        if max_group <= 0:
            return True
        return sum(1 for p_ in picked if bgdb.same_family(p_["name"], c["name"])) < max_group

    def hall_room(c):
        return all(per.get(h, 0) < per_hall for h in halls_of(c))

    def take(c):
        for h in halls_of(c):
            per[h] = per.get(h, 0) + 1
        picked.append(c)

    if cover_halls:
        # سالن‌های کم‌جمعیت‌تر اول، تا جای کوچک با پرکردن جاهای بزرگ از دست نرود
        pool: dict[str, int] = {}
        for c in scored:
            for h in halls_of(c):
                pool[h] = pool.get(h, 0) + 1
        for hall in sorted(pool, key=lambda h: (pool[h], h)):
            if len(picked) >= n:
                break
            if per.get(hall, 0) > 0:
                continue
            for c in scored:
                if c in picked or hall not in halls_of(c):
                    continue
                if not (group_ok(c) and hall_room(c)):
                    continue
                c["why"] = c["why"] + [f"پوشش سالن {hall}"]
                take(c)
                break

    for c in scored:
        if len(picked) >= n:
            break
        if c in picked:
            continue
        if not (group_ok(c) and hall_room(c)):
            continue
        take(c)
    # رتبهٔ نمایش همیشه بر اساس امتیاز است؛ پوشش سالن فقط ترکیب فهرست را عوض می‌کند
    picked.sort(key=lambda d: (-d["score"], -d["contacts"], d["name"]))
    return picked


def hall_pool(con, include_empty: bool) -> dict[str, int]:
    """هر سالن و تعداد شرکت‌های واجدشرطش — مبنای گزارش پوشش."""
    rows = con.execute("""
        SELECT halls FROM v_company_card
         WHERE priority IS NOT NULL AND (? OR contact_count > 0)
    """, (1 if include_empty else 0,)).fetchall()
    pool: dict[str, int] = {}
    for r in rows:
        for h in (r["halls"] or "").split("·"):
            h = h.strip()
            if h:
                pool[h] = pool.get(h, 0) + 1
    return pool


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(Path.home() / "xennic-data" / "barghpa-26-iee1405"
                                        / "db" / "barghpa_iee1405.sqlite"))
    ap.add_argument("--n", type=int, default=20)
    ap.add_argument("--per-hall", type=int, default=4)

    ap.add_argument("--max-group", type=int, default=0,
                    help="حداکثر تعداد شرکت هم‌خانواده (نام مشترک) در فهرست؛ ۰ = بی‌سقف")
    ap.add_argument("--cover-halls", action="store_true",
                    help="اول از هر سالن دست‌کم یک نامزد بردار، بعد با امتیاز پر کن")
    ap.add_argument("--include-empty", action="store_true",
                    help="شرکت‌های بدون هیچ اطلاعات تماس هم وارد شوند")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--approve", action="store_true",
                    help="علامت‌گذاری به‌عنوان تأییدشده توسط مالک (لازم برای --write)")
    ap.add_argument("--approved-by", default="")
    ap.add_argument("--csv", help="نوشتن خروجی در فایل CSV")
    args = ap.parse_args()

    if args.write and not args.approve:
        print("❌ برای نوشتن باید --approve و --approved-by بدهید؛ "
              "این فهرست تصمیم مالک است، نه انتخاب ابزار.", file=sys.stderr)
        return 2

    con = bgdb.connect(Path(args.db).expanduser())
    applied = bgdb.migrate(con)
    if applied:
        print("مهاجرت: " + " · ".join(applied))

    picked = candidates(con, args.n, args.per_hall, args.include_empty, args.max_group,
                        args.cover_halls)
    print(f"\nنامزدهای پایلوت ({len(picked)} از حداکثر {args.n}) — "
          f"حداکثر {args.per_hall} شرکت از هر سالن"
          + (" — با پوشش سالن‌ها" if args.cover_halls else "") + "\n")
    print(f"{'#':>3}  {'شرکت':38s} {'سالن':10s} {'امتیاز':>6}  منبع")
    print("─" * 88)
    for i, c in enumerate(picked, 1):
        print(f"{i:>3}  {c['name'][:38]:38s} {c['halls'][:10]:10s} {c['score']:>6}  "
              f"{CONF_LABEL.get(c['conf'], c['conf'])}")
        print(f"      چرا: {' · '.join(c['why'])} | اول: {c['first']}")

    pool = hall_pool(con, args.include_empty)
    got = {h.strip() for c in picked for h in c["halls"].split("·") if h.strip()}
    missing = [h for h in pool if h not in got]
    print(f"\n   پوشش سالن: {len(got & set(pool))} از {len(pool)} سالن")
    if missing:
        print("   بی‌نامزد: " + " · ".join(f"{h} ({pool[h]} شرکت)" for h in sorted(missing))
              + " — با --cover-halls یا --per-hall بالاتر برطرف می‌شود")
    if len(picked) < args.n:
        print(f"   ⚠️ فقط {len(picked)} از {args.n} جا پر شد؛ سقف per-hall={args.per_hall}"
              + (f" یا max-group={args.max_group}" if args.max_group else "")
              + " اجازهٔ بیشتر نداد. برای فهرست کامل‌تر این سقف‌ها را بالا ببرید.")

    if args.csv:
        out = Path(args.csv).expanduser()
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(["rank", "company", "halls", "score", "provenance",
                        "contacts", "phones", "emails", "why", "first_check"])
            for i, c in enumerate(picked, 1):
                w.writerow([i, c["name"], c["halls"], c["score"],
                            CONF_LABEL.get(c["conf"], c["conf"]), c["contacts"],
                            c["phones"] or "", c["emails"] or "",
                            " · ".join(c["why"]), c["first"]])
        print(f"\nCSV: {out}")

    if not args.write:
        print("\nℹ️ حالت نمایش. برای ثبت: --write --approve --approved-by «نام شما»")
        con.close()
        return 0

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    con.execute("DELETE FROM visit_pilot")
    for i, c in enumerate(picked, 1):
        con.execute("""INSERT INTO visit_pilot
            (company_id, rank, reason, first_check, approved, approved_by, approved_at)
            VALUES (?,?,?,?,1,?,?)""",
            (c["id"], i, " · ".join(c["why"]), c["first"], args.approved_by, now))
    con.commit()
    print(f"\n✅ {len(picked)} نامزد در visit_pilot ثبت شد (approved=1، "
          f"تأییدکننده: {args.approved_by or '—'})")
    con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
