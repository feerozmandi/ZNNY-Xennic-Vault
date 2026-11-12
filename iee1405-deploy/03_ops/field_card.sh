#!/usr/bin/env bash
# نمایش کارت میدانی (همان متنی که در گوشی نگه می‌دارید)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec cat "$HERE/field_card.txt"
