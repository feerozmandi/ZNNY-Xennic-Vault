#!/usr/bin/env python3
"""IEE 1405 — کشف محیط آزمون PostgreSQL (بدون هیچ فرض سخت‌کدشده).

سه آزمون این بسته (`02_n8n/validate_workflows.py`، `03_ops/test_workflow_e2e.py`
و `03_ops/test_import.py`) به یک کلاستر PostgreSQL **آزمایشی** نیاز دارند که
هیچ ارتباطی با تولید ندارد. قبلاً مسیر باینری‌ها و URI اتصال در هر فایل
سخت‌کد شده بود؛ نتیجه این بود که آزمون‌ها فقط روی یک محیط خاص اجرا می‌شدند و
روی هر ماشین دیگری با `ModuleNotFoundError: pgserver` می‌افتادند.

این ماژول همان دو مقدار را به ترتیب اولویت کشف می‌کند:

۱. **متغیرهای محیطی** (روی VPS یا CI):

   ```bash
   export IEE_TEST_PG_URI='postgresql://postgres:@/postgres?host=/tmp/pgdata'
   export IEE_TEST_PG_BIN=/usr/lib/postgresql/16/bin
   ```

۲. **بسته `pgserver`** در هر مسیری که نصب شده باشد (نه فقط dist-packages).

۳. **کلاستر محلی موجود** در `IEE_TEST_PG_DATA` (پیش‌فرض `/tmp/pgdata`) با
   باینری‌های استاندارد سیستم (`pg_config --bindir`).

اگر هیچ‌کدام پیدا نشد، خطای روشن با دستور نصب چاپ می‌شود — نه `Traceback`.
"""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

# مسیرهای متداول نصب باینری PostgreSQL در توزیع‌های مختلف
_COMMON_BIN_DIRS = [
    "/usr/lib/postgresql/16/bin",
    "/usr/lib/postgresql/15/bin",
    "/usr/pgsql-16/bin",
    "/usr/local/pgsql/bin",
    "/opt/homebrew/opt/postgresql@16/bin",
    "/usr/local/opt/postgresql@16/bin",
]

DATA_DIR = Path(os.environ.get("IEE_TEST_PG_DATA", "/tmp/pgdata"))


class TestEnvError(RuntimeError):
    """محیط آزمون آماده نیست — پیام باید قابل‌اقدام باشد، نه Traceback."""


def bin_dir() -> Path:
    """پوشه باینری‌های psql/initdb."""
    explicit = os.environ.get("IEE_TEST_PG_BIN")
    if explicit:
        p = Path(explicit)
        if (p / "psql").exists():
            return p
        raise TestEnvError(f"IEE_TEST_PG_BIN={explicit} است ولی {p / 'psql'} وجود ندارد")

    psql = shutil.which("psql")
    if psql:
        return Path(psql).resolve().parent

    for cand in _COMMON_BIN_DIRS:
        if (Path(cand) / "psql").exists():
            return Path(cand)

    try:
        out = subprocess.run(["pg_config", "--bindir"], capture_output=True, text=True, timeout=10)
        if out.returncode == 0 and (Path(out.stdout.strip()) / "psql").exists():
            return Path(out.stdout.strip())
    except (OSError, subprocess.SubprocessError):
        pass

    try:
        import pgserver  # noqa: F401  (فقط برای کشف مسیر بسته)

        pkg_bin = Path(pgserver.__file__).parent / "pginstall" / "bin"
        if (pkg_bin / "psql").exists():
            return pkg_bin
    except ImportError:
        pass

    raise TestEnvError(
        "باینری psql پیدا نشد.\n"
        "  راه ۱: pip install pgserver\n"
        "  راه ۲: export IEE_TEST_PG_BIN=$(pg_config --bindir)"
    )


def _pgserver_uri() -> str | None:
    try:
        import pgserver
    except ImportError:
        return None
    try:
        return pgserver.get_server(str(DATA_DIR), cleanup_mode=None).get_uri()
    except Exception:
        return None


def uri() -> str:
    """رشته اتصال به کلاستر آزمایشی."""
    explicit = os.environ.get("IEE_TEST_PG_URI")
    if explicit:
        return explicit
    found = _pgserver_uri()
    if found:
        return found
    if (DATA_DIR / "PG_VERSION").exists():
        # کلاستر از قبل ساخته شده ولی pgserver نصب نیست
        return f"postgresql://postgres:@/postgres?host={DATA_DIR}"
    raise TestEnvError(
        "کلاستر آزمون PostgreSQL در دسترس نیست.\n"
        "  راه ۱: pip install pgserver\n"
        f"  راه ۲: export IEE_TEST_PG_URI='postgresql://postgres:@/postgres?host={DATA_DIR}'"
    )


def psql() -> Path:
    return bin_dir() / "psql"


def describe() -> str:
    """یک خط توضیح برای سرصفحه خروجی آزمون‌ها."""
    return f"psql={psql()} · uri={uri()}"


def main() -> int:
    """اجرای مستقیم: `python3 03_ops/testenv.py` وضعیت را چاپ می‌کند."""
    try:
        where = describe()          # اول کشف، بعد اعلام موفقیت
        p = subprocess.run([str(psql()), uri(), "-X", "-t", "-A", "-c", "SELECT version()"],
                           capture_output=True, text=True, timeout=20)
        print("✅ محیط آزمون آماده است")
        print("   ", where)
        print("   ", (p.stdout or p.stderr).strip().split("\n")[0])
        return 0
    except TestEnvError as e:
        print(f"❌ محیط آزمون آماده نیست:\n{e}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
