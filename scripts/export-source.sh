#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-}" in
  ''|--check-only) ;;
  *) printf 'Usage: bash scripts/export-source.sh [--check-only]\n' >&2; exit 2 ;;
esac
# Export the reviewed file manifest without publishing private history or touching the Git index.
python3 - "$project_dir" "${1:-}" <<'PY'
from pathlib import Path, PurePosixPath
import gzip
import hashlib
import io
import json
import os
import re
import tarfile
import sys

project = Path(sys.argv[1]).resolve(strict=True)
check_only = sys.argv[2] == '--check-only'
public_directories = ('Sources', 'Tests', 'scripts', 'config', 'docs', '.github', 'Assets')
root_files = {'.gitignore', 'README.md', 'README.zh-CN.md', 'LICENSE', 'NOTICE',
              'CONTRIBUTING.md', 'SECURITY.md', 'PRIVACY.md', 'CHANGELOG.md', 'THIRD-PARTY-NOTICES.md'}
manifest_name = 'config/source-files.txt'


def checked_input(relative, directory=False):
    """Require an in-project regular input without symlinks in any path component."""
    pure = PurePosixPath(relative)
    if pure.is_absolute() or '..' in pure.parts or str(pure) != relative or not pure.parts:
        raise SystemExit('Unsafe source manifest path: ' + relative)
    current = project
    for index, component in enumerate(pure.parts):
        current = current / component
        if current.is_symlink():
            raise SystemExit('Refusing a source symlink: ' + relative)
        needs_directory = directory or index < len(pure.parts) - 1
        if needs_directory and not current.is_dir():
            raise SystemExit('Missing source directory: ' + relative)
    if not directory and not current.is_file():
        raise SystemExit('Missing or non-regular source file: ' + relative)
    if project not in current.resolve(strict=True).parents:
        raise SystemExit('Source escaped the project root: ' + relative)
    return current


for directory in public_directories:
    checked_input(directory, directory=True)
manifest_file = checked_input(manifest_name)
selected = set()
for number, original in enumerate(manifest_file.read_text().splitlines(), 1):
    entry = original.strip()
    if not entry or entry.startswith('#'):
        continue
    if entry != original:
        raise SystemExit('Whitespace in source manifest entry on line ' + str(number))
    if entry in selected:
        raise SystemExit('Duplicate source manifest entry: ' + entry)
    pure = PurePosixPath(entry)
    if entry not in root_files and (len(pure.parts) < 2 or pure.parts[0] not in public_directories):
        raise SystemExit('Source manifest path is outside approved public roots: ' + entry)
    checked_input(entry)
    selected.add(entry)
missing = (root_files | {manifest_name, 'config/product.env', 'config/WordNest.entitlements',
                         'Assets/Branding/WordNest.png', 'Assets/Branding/LICENSE', 'scripts/build.sh', 'scripts/test.sh'}) - selected
if missing:
    raise SystemExit('Required public files missing from manifest: ' + ', '.join(sorted(missing)))

# Reject new files until their distribution scope has been reviewed in the manifest.
# Walk without following links, and check directory entries before descending.
for directory in public_directories:
    for parent, directories, filenames in os.walk(project / directory, followlinks=False):
        for name in directories + filenames:
            path = Path(parent) / name
            relative = path.relative_to(project).as_posix()
            if path.is_symlink():
                raise SystemExit('Refusing a source symlink: ' + relative)
            if name == '.DS_Store':
                if path.is_dir():
                    raise SystemExit('Unexpected directory named .DS_Store: ' + relative)
                continue
            if path.is_file():
                if relative not in selected:
                    raise SystemExit('Review unexpected public file before adding it to the source manifest: ' + relative)
            elif not path.is_dir():
                raise SystemExit('Refusing non-regular source entry: ' + relative)

version_text = checked_input('config/product.env').read_text()
match = re.search(r'^WORDNEST_VERSION=([0-9]+\.[0-9]+\.[0-9]+)$', version_text, re.M)
build_match = re.search(r'^WORDNEST_BUILD_NUMBER=([0-9]+)$', version_text, re.M)
if not match or not build_match:
    raise SystemExit('Missing product version or build number.')
base = 'wordnest-' + match.group(1) + '-build' + build_match.group(1) + '-source'
output = project / 'work/source-distribution'
# Fixed output still needs ancestor checks: a symlinked work/ must not redirect writes.
current = project
for component in output.relative_to(project).parts:
    current = current / component
    if current.is_symlink():
        raise SystemExit('Refusing a symlink output ancestor: ' + str(current.relative_to(project)))
    if current.exists() and not current.is_dir():
        raise SystemExit('Output ancestor is not a directory: ' + str(current.relative_to(project)))
if project not in output.resolve().parents:
    raise SystemExit('Output escaped the project root.')
archive = output / (base + '.tar.gz')
checksums = output / (base + '-SHA256SUMS.txt')
manifest_path = output / (base + '-manifest.json')
for path in (archive, checksums, manifest_path):
    if path.is_symlink():
        raise SystemExit('Refusing a symlink output: ' + path.name)
if not check_only and any(path.exists() for path in (archive, checksums, manifest_path)):
    raise SystemExit('Source export already exists; review it or choose a new version.')

records = []
for name in sorted(selected):
    path = checked_input(name)
    data = path.read_bytes()
    records.append((name, data, bool(path.stat().st_mode & 0o111)))
manifest = {'product': 'WordNest', 'version': match.group(1), 'build': build_match.group(1), 'files': [
    {'path': name, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}
    for name, data, _ in records]}
if check_only:
    print('Public source manifest and output safety: PASS (' + str(len(records)) + ' files; no archive written)')
    raise SystemExit(0)

output.mkdir(parents=True, exist_ok=True)
# Stable headers avoid leaking personal ownership and local timestamps into the archive.
with archive.open('xb') as destination:
    with gzip.GzipFile(filename='', mode='wb', fileobj=destination, mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w') as bundle:
            for name, data, executable in records:
                info = tarfile.TarInfo(base + '/' + name)
                info.size = len(data)
                info.mode = 0o755 if executable else 0o644
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ''
                bundle.addfile(info, io.BytesIO(data))
with manifest_path.open('x') as destination:
    destination.write(json.dumps(manifest, indent=2) + '\n')
with checksums.open('x') as destination:
    destination.write(''.join(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.name + '\n'
                              for path in (archive, manifest_path)))
print('Exported ' + str(len(records)) + ' public source files: ' + str(archive))
PY
