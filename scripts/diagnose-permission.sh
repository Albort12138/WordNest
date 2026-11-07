#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="${SUBTITLE_LOOKUP_APP_DIR:-$project_dir/work/build/WordNest.app}"
# Read signature/version and optional previous-build identity compatibility; never access TCC or reset permissions.
# With a previous app: return 0 for compatible identity, 2 for incompatible; this does not inspect permission grants.
python3 - "$app_dir" "${1:-}" <<'PY'
from pathlib import Path
import plistlib
import subprocess
import sys

current = Path(sys.argv[1]).resolve()
if not current.is_dir():
    raise SystemExit('App not found: ' + str(current))
info = plistlib.loads((current / 'Contents/Info.plist').read_bytes())
print('APP:', current, flush=True)
print('VERSION:', info.get('CFBundleShortVersionString'), flush=True)
print('BUNDLE_ID:', info.get('CFBundleIdentifier'), flush=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(current)], check=True)
print('SIGNATURE_INTEGRITY: PASS', flush=True)

def requirement(app):
    result = subprocess.run(['codesign', '-d', '-r-', str(app)], capture_output=True, text=True, check=True)
    for line in (result.stdout + result.stderr).splitlines():
        line = line.removeprefix('# ')
        if line.startswith('designated => '):
            return line.removeprefix('designated => ')
    raise RuntimeError('No designated requirement found for ' + str(app))

rule = requirement(current)
print('IDENTITY_REQUIREMENT:', rule, flush=True)
print('IDENTITY_KIND:', 'per-build cdhash' if rule.startswith('cdhash ') else 'certificate/other', flush=True)
if sys.argv[2]:
    previous = Path(sys.argv[2]).resolve()
    previous_rule = requirement(previous)
    # Prefix an inline -R requirement with '=' so codesign does not treat it as a file path.
    result = subprocess.run(['codesign', '--verify', '-R', '=' + previous_rule, str(current)], capture_output=True, text=True)
    print('MATCHES_PREVIOUS_IDENTITY:', result.returncode == 0, flush=True)
    if result.returncode:
        print('The current build does not satisfy the previous code identity. Old privacy authorization may not apply.', flush=True)
        raise SystemExit(2)
PY
