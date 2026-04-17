#!/usr/bin/env bash
# Read a top-level scalar from a simple key: value YAML file (e.g. variables/k8s.yml).
# Usage: k8s-read-yaml-value.sh <key> <yaml-file>
# Prefers mikefarah yq when installed; otherwise Ruby (Psych) or Python 3.
set -euo pipefail

key="${1:?usage: $0 <key> <yaml-file>}"
file="${2:?usage: $0 <key> <yaml-file>}"

if [[ ! -f "$file" ]]; then
  echo >&2 "ERROR: file not found: $file"
  exit 1
fi

if command -v yq >/dev/null 2>&1; then
  exec yq ".${key}" "$file"
fi

if command -v ruby >/dev/null 2>&1 && ruby -ryaml -e 'exit' 2>/dev/null; then
  exec ruby -ryaml -e 'puts YAML.load_file(ARGV[0])[ARGV[1]]' "$file" "$key"
fi

if command -v python3 >/dev/null 2>&1; then
  exec python3 - "$file" "$key" <<'PY'
import re
import sys

path, key = sys.argv[1], sys.argv[2]
val = None
with open(path, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^([^:]+):\s*(.*)$", line)
        if not m:
            continue
        k, v = m.group(1).strip(), m.group(2).strip()
        if k != key:
            continue
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        val = v
        break
if val is None:
    print(f"ERROR: missing key {key!r} in {path}", file=sys.stderr)
    sys.exit(1)
print(val)
PY
fi

echo >&2 "ERROR: need yq (https://github.com/mikefarah/yq), or ruby with yaml, or python3"
exit 1
