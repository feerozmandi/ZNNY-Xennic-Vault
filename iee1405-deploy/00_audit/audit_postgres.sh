#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# IEE 1405 — بازرسی PostgreSQL روی VPS (فقط خواندن)
# مستند مرجع: PRJ-IEE-010، PRJ-IEE-017
#
# اجرا روی VPS:
#   ssh -p 33878 xennic@185.192.113.199
#   cd ~ && bash iee1405-deploy/00_audit/audit_postgres.sh
#
# خروجی‌ها در 00_audit/out/<timestamp>/ :
#   audit-raw.txt        خروجی کامل psql (قابل پیوست به مستندات)
#   audit-report.md      خلاصه ساخت‌یافته
#   audit-*.json         داده ساخت‌یافته برای مقایسه و ماشین
#   host-info.txt        Docker / n8n / دیسک / سیستم‌عامل
#
# هیچ دستور نوشتنی اجرا نمی‌شود. فقط SELECT / \d / docker ps / df
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${OUT_DIR:-$HERE/out/$STAMP}"
mkdir -p "$OUT"

LOG="$OUT/audit-raw.txt"
MD="$OUT/audit-report.md"
HOSTINFO="$OUT/host-info.txt"

# ── پیکربندی اتصال (خودکار از docker کشف می‌شود) ──────────────────────
# روی این سرور: کانتینر xennic-infra-postgres-1 · کاربر n8n
# برای اجرای محلی:  PSQL_CMD="psql -h ... -U ... -d ..." bash 00_audit/audit_postgres.sh
# shellcheck source=/dev/null
source "$HERE/../03_ops/lib_common.sh"

if [[ -n "${PSQL_CMD:-}" ]]; then
    read -r -a PSQL <<< "$PSQL_CMD"
    psql_file() { "${PSQL[@]}" -P pager=off -f -; }
    psql_cmd()  { "${PSQL[@]}" "$@"; }
else
    if ! dk_detect || ! ct_detect; then
        echo "❌ Docker یا کانتینر PostgreSQL پیدا نشد."
        echo "   docker ps  را ببینید؛ یا PG_CONTAINER=<name> این اسکریپت را اجرا کنید."
        exit 1
    fi
    pg_user_detect || { echo "❌ اتصال به PostgreSQL برقرار نشد (کاربر $PG_USER)"; exit 1; }
    AUDIT_DB="${AUDIT_DB:-$PG_DB}"
    pg_db_exists "$AUDIT_DB" || AUDIT_DB="postgres"
    # بدون -t -A: سرستون‌ها لازم‌اند چون گزارش JSON از همین جدول‌ها ساخته می‌شود
    psql_file() { $DK exec -i "$PG_CT" psql -U "$PG_USER" -d "$AUDIT_DB" -X -P pager=off -f -; }
    psql_cmd()  { $DK exec -i "$PG_CT" psql -U "$PG_USER" -d "$AUDIT_DB" -X -t -A "$@"; }
    echo "کانتینر: $PG_CT · کاربر: $PG_USER · دیتابیس: $AUDIT_DB"
fi

say() { printf '%s\n' "$*" | tee -a "$MD"; }

say "# گزارش بازرسی PostgreSQL — $(date -u '+%Y-%m-%d %H:%M UTC')"
say ""
say "- میزبان: \`$(hostname)\`"
say "- تاریخ شمسی: $(TZ=Asia/Tehran date '+%Y-%m-%d')"
say "- حالت اجرا: \`${PG_CT:-${PSQL[*]}} / ${PG_USER:-?} / ${AUDIT_DB:-?}\`"
say ""

# ── ۱) دسترسی و نسخه ─────────────────────────────────────────────────
if ! psql_cmd -c 'SELECT 1' >/dev/null 2>>"$LOG"; then
    say "## ❌ اتصال برقرار نشد"
    say ""
    say "خروجی خطا در \`audit-raw.txt\` ثبت شد. موارد بررسی:"
    say "1. آیا کانتینر \`postgres\` بالاست؟ \`docker compose ps\`"
    say "2. کانتینر PostgreSQL بالاست؟ \`docker ps\`"
    say "3. کاربر/دیتابیس درست است؟ (\`PG_USER\` / \`PG_DB\`)"
    exit 1
fi

psql_file < "$HERE/audit.sql" >>"$LOG" 2>&1
RC=$?
say "## نتیجه اجرا"
say ""
say "- کد خروج psql: \`$RC\` (۰ یعنی همه پرسش‌ها اجرا شد)"
say "- خط خروجی خام: \`$LOG\`"
say ""

# ── ۲) اطلاعات میزبان، Docker و n8n ───────────────────────────────────
{
    echo "### OS";            uname -a; echo; cat /etc/os-release 2>/dev/null | head -5
    echo; echo "### UPTIME";  uptime
    echo; echo "### DISK";    df -h /
    echo; echo "### MEMORY";  free -h
    echo; echo "### DOCKER";  $DK ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' 2>&1
    echo; echo "### DOCKER_IMAGES"; docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' 2>&1 | head -20
    echo; echo "### N8N_VERSION"
    if [[ -n "${N8N_CT:-}" ]]; then $DK exec -i "$N8N_CT" n8n --version 2>&1 | tail -3; fi
    echo; echo "### FIREWALL"; ufw status 2>&1 | head -20
    echo; echo "### LISTEN";  ss -tlnp 2>/dev/null | head -25
    echo; echo "### POSTGRES_VOLUME"; docker volume ls 2>&1 | head -20
    echo; echo "### CRON";    crontab -l 2>&1 | head -20
} > "$HOSTINFO" 2>&1
say "## اطلاعات میزبان"
say ""
say "- خروجی: \`$HOSTINFO\`"
say ""

# ── ۳) استخراج داده ساخت‌یافته از بلوک‌های خروجی ──────────────────────
python3 - "$LOG" "$OUT" <<'PY' 2>/dev/null || echo "(استخراج JSON نیاز به python3 داشت؛ از خروجی خام استفاده کنید)" | tee -a "$MD"
import json, re, sys, os

log_path, out_dir = sys.argv[1], sys.argv[2]
raw = open(log_path, encoding="utf-8", errors="replace").read()

blocks, current, lines = {}, None, []
for line in raw.splitlines():
    m = re.match(r"^###(\d+)\|(\w+)$", line.strip())
    if m:
        if current: blocks[current] = lines
        current = m.group(2); lines = []
    elif current:
        lines.append(line)
if current: blocks[current] = lines

def parse_table(lines):
    rows = [l for l in lines if l.strip() and not set(l.strip()) <= set("-+ ") ]
    if len(rows) < 2: return []
    header = [c.strip() for c in rows[0].split("|")]
    out = []
    for r in rows[1:]:
        cells = [c.strip() for c in r.split("|")]
        if len(cells) != len(header): continue
        out.append(dict(zip(header, cells)))
    return out

data = {k: parse_table(v) for k, v in blocks.items()}
json.dump(data, open(os.path.join(out_dir, "audit-all.json"), "w"), ensure_ascii=False, indent=1)

# فایل‌های کوچک و قابل diff
for name, key in [("audit-version", "VERSION"), ("audit-extensions", "EXTENSIONS"),
                  ("audit-databases", "DATABASES"), ("audit-roles", "ROLES"),
                  ("audit-existing-objects", "EXISTING_IEE_OBJECTS"),
                  ("audit-settings", "KEY_SETTINGS")]:
    json.dump(data.get(key, []), open(os.path.join(out_dir, f"{name}.json"), "w"),
              ensure_ascii=False, indent=1)

# ── خلاصه تصمیم‌ها ──
ver = (data.get("VERSION") or [{}])[0]
dbs = data.get("DATABASES") or []
roles = data.get("ROLES") or []
exts = {e.get("extname"): e.get("extversion") for e in (data.get("EXTENSIONS") or [])}
have = data.get("EXISTING_IEE_OBJECTS") or []
settings = {s.get("name"): s.get("setting") for s in (data.get("KEY_SETTINGS") or [])}
limits = (data.get("CONNECTION_LIMITS") or [{}])[0]

L = []
L.append("## خلاصه")
L.append("")
L.append(f"| مورد | مقدار |")
L.append(f"|---|---|")
L.append(f"| نسخه PostgreSQL | `{ver.get('pg_version','?')}` |")
L.append(f"| دیتابیس جاری | `{ver.get('db','?')}` |")
L.append(f"| کاربر | `{ver.get('usr','?')}` |")
L.append(f"| دامنه uptime | `{ver.get('uptime','?')}` |")
L.append(f"| تعداد دیتابیس | {len(dbs)} |")
L.append(f"| تعداد کاربر DB | {len(roles)} |")
L.append(f"| max_connections | {limits.get('max_connections','?')} (فعال: {limits.get('client_backends','?')}) |")
L.append(f"| pg_trgm | {'✅ ' + exts['pg_trgm'] if 'pg_trgm' in exts else '❌ نصب نیست'} |")
L.append(f"| pgcrypto | {'✅ ' + exts['pgcrypto'] if 'pgcrypto' in exts else '➖ لازم نیست (PG≥13)'} |")
L.append(f"| listen_addresses | `{settings.get('listen_addresses','?')}` |")
L.append(f"| archive_mode | `{settings.get('archive_mode','?')}` |")
L.append(f"| ssl | `{settings.get('ssl','?')}` |")
L.append(f"| اشیای IEE از قبل موجود | {len(have)} |")
L.append("")
open(os.path.join(out_dir, "_summary.md"), "w", encoding="utf-8").write("\n".join(L))
PY

[[ -f "$OUT/_summary.md" ]] && cat "$OUT/_summary.md" >> "$MD"

# ── ۴) یافته‌های خودکار ───────────────────────────────────────────────
{
echo ""
echo "## یافته‌های خودکار"
echo ""
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
p = os.path.join(out, "audit-all.json")
if not os.path.exists(p):
    print("- (JSON ساخته نشد)"); raise SystemExit
d = json.load(open(p))

def tbl(k): return d.get(k) or []

findings = []
exts = {e.get("extname") for e in tbl("EXTENSIONS")}
if "pg_trgm" not in exts:
    findings.append(("info", "پسوند pg_trgm نصب نیست → جست‌وجوی نام با ILIKE انجام می‌شود. "
                             "اگر دسترسی superuser دارید: `CREATE EXTENSION pg_trgm;` (اختیاری، سرعت جست‌وجو را زیاد می‌کند)."))
else:
    findings.append(("ok", "pg_trgm فعال است → ایندکس سه‌گرام برای جست‌وجوی نام فعال می‌شود."))

have = tbl("EXISTING_IEE_OBJECTS")
if have:
    findings.append(("warn", f"{len(have)} شئ از قبل در schemaهای crm/iee1405 وجود دارد. "
                             "اسکریپت‌ها idempotent هستند، اما قبل از استقرار یک نسخه پشتیبان بگیرید."))
else:
    findings.append(("ok", "schemaهای crm/iee1405 خالی هستند → استقرار بدون تعارض انجام می‌شود."))

lim = (tbl("CONNECTION_LIMITS") or [{}])[0]
try:
    if int(lim.get("client_backends", 0)) > 0.7 * int(lim.get("max_connections", 100)):
        findings.append(("warn", "بیش از ۷۰٪ سهمیه اتصال مصرف شده؛ max_connections را بررسی کنید."))
except Exception:
    pass

settings = {s.get("name"): s for s in tbl("KEY_SETTINGS")}
_listen = str(settings.get("listen_addresses", {}).get("setting", "")).strip()
if _listen in ("", "*", "0.0.0.0", "all"):
    findings.append(("warn", f"listen_addresses = `{_listen or 'خالی/نامشخص'}` — باید صریحاً localhost باشد؛ "
                             "و پورت ۵۴۳۲ در ufw بسته بماند (بدون دسترسی عمومی)."))
else:
    findings.append(("ok", "listen_addresses محدود به localhost است (بدون دسترسی عمومی)."))

if str(settings.get("archive_mode", {}).get("setting", "")).lower() in ("off", "false"):
    findings.append(("info", "archive_mode خاموش است → برای این پروژه کافی است، اما pg_dump شبانه لازم است (PRJ-IEE-013)."))

tz = (tbl("DISK_AND_TIME") or [{}])[0].get("server_tz", "")
if "Tehran" not in str(tz):
    findings.append(("info", f"TimeZone سرور `{tz}` است؛ تاریخ‌های نمایشی در توابع صریحاً Asia/Tehran در نظر گرفته شده‌اند."))

tables = tbl("N8N_TABLES")
if tables:
    findings.append(("info", f"n8n از همان نمونه استفاده می‌کند ({len(tables)} جدول شناسایی شد) → "
                             "اتصال n8n→PostgreSQL از طریق شبکه داخلی Docker برقرار است (بدون نیاز به پورت عمومی)."))

for level, msg in findings:
    icon = {"ok": "✅", "warn": "⚠️", "info": "ℹ️"}.get(level, "•")
    print(f"- {icon} {msg}")
PY
echo ""
echo "## گام بعدی"
echo ""
echo "بر اساس نتایج بالا:"
echo ""
echo "1. اگر \`EXISTING_IEE_OBJECTS\` خالی است → استقرار مستقیم:"
echo "   \`bash 03_ops/deploy_local.sh\` (اسکریپت استقرار SQL روی همین کانتینر)"
echo "2. اگر چیزی از قبل هست → ابتدا \`bash 03_ops/backup_now.sh\` سپس استقرار."
echo "3. ایمپورت گردش‌کارهای n8n: \`bash 03_ops/import_workflows.sh\`"
} >> "$MD"

echo ""
echo "✅ بازرسی تمام شد"
echo "   گزارش: $MD"
echo "   خام:   $LOG"
echo "   میزبان: $HOSTINFO"
