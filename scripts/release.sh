#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../config/product.env
source "$project_dir/config/product.env"
package_mode=release
case "${1:-}" in
  --unsigned-preview) package_mode=unsigned-preview ;;
  '') ;;
  *) printf 'Usage: bash scripts/release.sh [--unsigned-preview]\n' >&2; exit 2 ;;
esac
signing_identity="${SUBTITLE_LOOKUP_SIGNING_IDENTITY:--}"
notary_profile="${WORDNEST_NOTARY_PROFILE:-}"
if [[ "$package_mode" == release ]]; then
  if [[ "$signing_identity" != 'Developer ID Application: '* || -z "$notary_profile" ]]; then
    printf 'Production packaging requires a Developer ID Application identity and WORDNEST_NOTARY_PROFILE.\nNo unsigned fallback is permitted.\n' >&2
    exit 2
  fi
fi
# Release provenance must describe the exact source, including unpublished local edits.
bash "$project_dir/scripts/export-source.sh" --check-only
revision=uncommitted
source_state=exported
if [[ "$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null || true)" == "$project_dir" ]]; then
  revision="$(git -C "$project_dir" rev-parse --verify HEAD 2>/dev/null || printf uncommitted)"
  if [[ "$revision" == uncommitted || -n "$(git -C "$project_dir" status --porcelain --untracked-files=normal)" ]]; then
    source_state=dirty
  else
    source_state=clean
  fi
fi
if [[ "$package_mode" == release && "$source_state" != clean ]]; then
  printf 'Official release packaging requires a clean committed source checkout. Current state: %s\n' "$source_state" >&2
  exit 2
fi
source_digest() {
  python3 - "$project_dir" <<'PYDIGEST'
from pathlib import Path
import hashlib
import sys
root = Path(sys.argv[1])
paths = [line for line in (root / 'config/source-files.txt').read_text().splitlines() if line and not line.startswith('#')]
digest = hashlib.sha256()
for name in sorted(paths):
    digest.update(name.encode() + b'\0' + hashlib.sha256((root / name).read_bytes()).digest())
print(digest.hexdigest())
PYDIGEST
}
source_sha256="$(source_digest)"
for name in LICENSE NOTICE PRIVACY.md THIRD-PARTY-NOTICES.md Assets/Branding/LICENSE; do
  if [[ ! -f "$project_dir/$name" ]]; then printf 'Missing required distribution document: %s\n' "$name" >&2; exit 2; fi
done
output_dir="${WORDNEST_RELEASE_DIR:-$project_dir/work/releases}"
output_dir="$(python3 - "$project_dir" "$output_dir" <<'PY'
from pathlib import Path
import sys
project, raw = sys.argv[1:]
path = Path(raw).absolute()
if path.is_symlink():
    raise SystemExit('Refusing a symlink release directory.')
path = path.resolve()
work = (Path(project) / 'work').resolve()
if path != work and work not in path.parents:
    raise SystemExit('Release output must be inside this checkout/work/.')
print(path)
PY
)"
suffix=''
if [[ "$package_mode" == unsigned-preview ]]; then suffix=-unsigned-preview; fi
base="WordNest-$WORDNEST_VERSION-build$WORDNEST_BUILD_NUMBER-macos-$WORDNEST_ARCH$suffix"
for name in "$base.dmg" "$base.zip" "$base-SHA256SUMS.txt" "$base-build-info.txt"; do
  if [[ -e "$output_dir/$name" ]]; then printf 'Refusing to overwrite package: %s\n' "$output_dir/$name" >&2; exit 2; fi
done
mkdir -p "$project_dir/work/release-staging" "$output_dir"
staging_dir="$(mktemp -d "$project_dir/work/release-staging/package.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
payload="$staging_dir/payload"
mkdir -p "$payload"
staging_app="$payload/WordNest.app"
if [[ "$package_mode" == release ]]; then build_mode=release; else build_mode=preview; signing_identity=-; fi
WORDNEST_BUILD_MODE="$build_mode" SUBTITLE_LOOKUP_SIGNING_IDENTITY="$signing_identity" \
  SUBTITLE_LOOKUP_BUILD_DIR="$staging_dir/build" SUBTITLE_LOOKUP_APP_DIR="$staging_app" \
  bash "$project_dir/scripts/build.sh"
for document in LICENSE NOTICE PRIVACY.md THIRD-PARTY-NOTICES.md; do
  cp "$project_dir/$document" "$payload/$document"
done
cp "$project_dir/Assets/Branding/LICENSE" "$payload/WordNest-artwork-LICENSE.txt"
ln -s /Applications "$payload/Applications"
if [[ "$package_mode" == unsigned-preview ]]; then
  printf 'LOCAL UNSIGNED PREVIEW\nThis package is ad-hoc signed, not Apple-notarized, and is not an official release.\nDo not disable macOS security protections.\n' > "$payload/UNSIGNED-PREVIEW.txt"
fi
notarize() {
  local artifact="$1"
  local report="$2"
  xcrun notarytool submit "$artifact" --keychain-profile "$notary_profile" --wait --output-format json > "$report"
  python3 - "$report" <<'PY'
import json
import sys
with open(sys.argv[1]) as report:
    result = json.load(report)
if result.get('status') != 'Accepted':
    raise SystemExit('Apple notarization did not return Accepted. Inspect the private notary log.')
print('Apple notarization: Accepted')
PY
}
if [[ "$package_mode" == release ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$staging_app" "$staging_dir/notarize-app.zip"
  notarize "$staging_dir/notarize-app.zip" "$staging_dir/app-notarization.json"
  xcrun stapler staple "$staging_app"
  xcrun stapler validate "$staging_app"
  codesign --verify --deep --strict "$staging_app"
  spctl --assess --type execute --verbose=2 "$staging_app"
fi
# ZIP contains the same stapled app as the DMG, plus license/privacy documents.
ditto -c -k --sequesterRsrc "$payload" "$staging_dir/$base.zip"
hdiutil create -volname WordNest -srcfolder "$payload" -format UDZO "$staging_dir/$base.dmg" >/dev/null
hdiutil verify "$staging_dir/$base.dmg" >/dev/null
if [[ "$package_mode" == release ]]; then
  codesign --force --sign "$signing_identity" --timestamp "$staging_dir/$base.dmg"
  notarize "$staging_dir/$base.dmg" "$staging_dir/dmg-notarization.json"
  xcrun stapler staple "$staging_dir/$base.dmg"
  xcrun stapler validate "$staging_dir/$base.dmg"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$staging_dir/$base.dmg"
fi
(
  cd "$staging_dir"
  shasum -a 256 "$base.dmg" "$base.zip" > "$base-SHA256SUMS.txt"
)
if [[ "$(source_digest)" != "$source_sha256" ]]; then
  printf 'Public source changed during packaging; no artifacts were published. Rebuild the candidate.\n' >&2
  exit 2
fi
printf 'product=WordNest\nversion=%s\nbuild=%s\narchitecture=%s\nbundle_id=%s\npackage_mode=%s\nsource_revision=%s\nsource_state=%s\nsource_sha256=%s\n' \
  "$WORDNEST_VERSION" "$WORDNEST_BUILD_NUMBER" "$WORDNEST_ARCH" "$WORDNEST_BUNDLE_ID" "$package_mode" "$revision" "$source_state" "$source_sha256" > "$staging_dir/$base-build-info.txt"
for name in "$base.dmg" "$base.zip" "$base-SHA256SUMS.txt" "$base-build-info.txt"; do
  mv "$staging_dir/$name" "$output_dir/$name"
done
printf 'Packaged: %s\nMode: %s\n' "$output_dir/$base.dmg" "$package_mode"
