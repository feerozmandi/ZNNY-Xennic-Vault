#!/usr/bin/env python3
"""Run .sql files against the local test cluster with ON_ERROR_STOP=1.
Used only for local verification before deploying to the VPS."""
import subprocess, sys, os
import pgserver
from pathlib import Path
POSTGRES_BIN_PATH = Path("/usr/local/lib/python3.11/dist-packages/pgserver/pginstall/bin")

srv = pgserver.get_server("/tmp/pgdata", cleanup_mode=None)
uri = srv.get_uri()

def run(sql: str, label: str = "sql") -> str:
    p = subprocess.run(
        [str(POSTGRES_BIN_PATH / "psql"), uri, "-v", "ON_ERROR_STOP=1", "-q", "-t"],
        input=sql.encode(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = p.stdout.decode("utf-8", "replace")
    if p.returncode != 0:
        print(f"[FAIL] {label}\n{out[-4000:]}")
        sys.exit(1)
    print(f"[ OK ] {label}")
    return out

if __name__ == "__main__":
    for f in sys.argv[1:]:
        run(open(f, encoding="utf-8").read(), os.path.basename(f))
