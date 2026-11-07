#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
# Source uses English keys; multilingual text and stable Notes identifiers belong in data resources.
python3 - "$project_dir" <<'PY'
from pathlib import Path
import json
import re
import sys
root = Path(sys.argv[1])
failures = []
han = re.compile(r'[\u3400-\u9fff]')
for folder in ['Sources', 'Tests', 'scripts', 'config']:
    for path in sorted((root / folder).rglob('*')):
        if not path.is_file():
            continue
        if path.suffix == '.mdx' and path.parent == root / 'Tests/Fixtures':
            continue  # Binary, independently generated dictionary test data.
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if han.search(line):
                failures.append(f'{path.relative_to(root)}:{number}: move multilingual text into a data resource')
catalogs = {}
for language in ['en', 'zh-Hans']:
    catalog = {}
    for path in sorted((root / 'Assets/Localization').glob(language + '-*.json')):
        for key, value in json.loads(path.read_text()).items():
            if han.search(key):
                failures.append(f'{path.name}: interface keys must be English')
            if not isinstance(value, str) or not value:
                failures.append(f'{path.name}: empty or invalid translation for {key}')
                continue
            if language == 'en' and key != 'language.nativeChinese' and han.search(value):
                failures.append(f'{path.name}: English interface text contains untranslated content')
            if sorted(re.findall(r'\{\d+\}', key)) != sorted(re.findall(r'\{\d+\}', value)):
                failures.append(f'{path.name}: interpolation slots differ for {key}')
            if key in catalog and catalog[key] != value:
                failures.append(f'{path.name}: conflicting translation for {key}')
            catalog[key] = value
    if not catalog:
        failures.append(language + ' interface catalogs are missing')
    catalogs[language] = catalog
if catalogs['en'].keys() != catalogs['zh-Hans'].keys():
    failures.append('English and Chinese interface catalogs must contain the same keys')
for folder, prefix in [('Compatibility', 'legacy-notes'), ('Fixtures', 'sample-text')]:
    path = root / 'Assets' / folder / (prefix + '.json')
    entries = json.loads(path.read_text())
    for key, value in entries.items():
        if han.search(key) or not isinstance(value, str) or not value:
            failures.append(f'{path.name}: invalid English resource key or missing text')
if failures:
    raise SystemExit('\n'.join(failures))
print('English source and bilingual resource policy: PASS')
PY
