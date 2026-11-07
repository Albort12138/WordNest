#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../config/product.env
source "$project_dir/config/product.env"
build_dir="${SUBTITLE_LOOKUP_BUILD_DIR:-$project_dir/work/build}"
app_dir="${SUBTITLE_LOOKUP_APP_DIR:-$project_dir/work/build/WordNest.app}"
build_mode="${WORDNEST_BUILD_MODE:-development}"
case "${1:-}" in
  --development) build_mode=development ;;
  --preview) build_mode=preview ;;
  --release) build_mode=release ;;
  '') ;;
  *) printf 'Usage: bash scripts/build.sh [--development|--preview|--release]\n' >&2; exit 2 ;;
esac
case "$build_mode" in development|preview|release) ;; *) printf 'Invalid build mode.\n' >&2; exit 2 ;; esac
# Isolate fixture launches from the installed product's permissions and LaunchServices identity.
if [[ "$build_mode" == development ]]; then WORDNEST_BUNDLE_ID="$WORDNEST_BUNDLE_ID.development"; fi
signing_identity="${SUBTITLE_LOOKUP_SIGNING_IDENTITY:--}"
if [[ "$build_mode" == release && "$signing_identity" != 'Developer ID Application: '* ]]; then
  printf 'Release builds require SUBTITLE_LOOKUP_SIGNING_IDENTITY="Developer ID Application: ...".\n' >&2
  exit 2
fi
# Refuse arbitrary output paths and every existing app not created by this product build.
# Old authorized preview packages have no marker and are never overwritten.
app_dir="$(python3 - "$project_dir" "$app_dir" "$WORDNEST_BUNDLE_ID" <<'PY'
from pathlib import Path
import plistlib
import sys
project, raw, expected = sys.argv[1:]
raw_path = Path(raw).absolute()
if raw_path.is_symlink():
    raise SystemExit('Refusing a symlink as app output.')
app = raw_path.resolve()
work = (Path(project) / 'work').resolve()
if work not in app.parents or app.name != 'WordNest.app':
    raise SystemExit('App output must be a WordNest.app inside this checkout/work/.')
if app.exists():
    marker = app / 'Contents/Resources/wordnest-managed-build.txt'
    info_path = app / 'Contents/Info.plist'
    if not app.is_dir() or not marker.is_file() or not info_path.is_file():
        raise SystemExit('Refusing to overwrite an existing unmanaged/frozen app: ' + str(app))
    info = plistlib.loads(info_path.read_bytes())
    if marker.read_text().strip() != expected or info.get('CFBundleIdentifier') != expected:
        raise SystemExit('Refusing to overwrite an app with another product identity.')
print(app)
PY
)"
mkdir -p "$build_dir/module-cache" "$(dirname "$app_dir")"
staging_dir="$(mktemp -d "$build_dir/app-staging.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
staging_app="$staging_dir/WordNest.app"
mkdir -p "$staging_app/Contents/MacOS" "$staging_app/Contents/Resources"
compiler_flags=()
if [[ "$build_mode" == development ]]; then compiler_flags=(-D WORDNEST_DEVELOPMENT); fi
sources=(TextResources InterfaceLanguage ProductRuntime LanguageSupport LookupCore TextRecognizer SystemDictionary MDXReader RIPEMD128 DictionaryProvider DictionarySettings WordSpeaker LookupCardBody Vocabulary CollectionSource SourceCapture SourceAnalysis AppleNotes AlphabetBook AlphabetNotes NotesSettings VocabularyBrowser SetupCoordinator SetupWindow App)
source_paths=()
for name in "${sources[@]}"; do source_paths+=("$project_dir/Sources/$name.swift"); done
# Empty arrays need conditional expansion under the macOS Bash 3.2 nounset behavior.
xcrun swiftc -swift-version 5 -O -target "$WORDNEST_ARCH-apple-macosx$WORDNEST_MINIMUM_MACOS" \
  -module-cache-path "$build_dir/module-cache" ${compiler_flags[@]+"${compiler_flags[@]}"} \
  "${source_paths[@]}" \
  -framework AppKit -framework Carbon -framework ScreenCaptureKit -framework Vision -framework CoreServices -framework AVFoundation -framework NaturalLanguage -lz \
  -o "$staging_app/Contents/MacOS/$WORDNEST_EXECUTABLE"
SUBTITLE_LOOKUP_BUILD_DIR="$build_dir" bash "$project_dir/scripts/build-icons.sh" "$staging_app/Contents/Resources"
for resource_folder in Localization Compatibility Fixtures; do
  mkdir -p "$staging_app/Contents/Resources/$resource_folder"
  cp "$project_dir/Assets/$resource_folder/"*.json "$staging_app/Contents/Resources/$resource_folder/"
done
# Installed apps retain their license even when users only drag the app out of a DMG.
for document in LICENSE NOTICE PRIVACY.md THIRD-PARTY-NOTICES.md; do
  cp "$project_dir/$document" "$staging_app/Contents/Resources/$document"
done
python3 - "$staging_app" "$WORDNEST_EXECUTABLE" "$WORDNEST_BUNDLE_ID" "$WORDNEST_VERSION" "$WORDNEST_BUILD_NUMBER" "$WORDNEST_MINIMUM_MACOS" "$build_mode" <<'PY'
from pathlib import Path
import plistlib
import sys
app, executable, identifier, version, build, minimum, mode = sys.argv[1:]
info = {
    'CFBundleExecutable': executable,
    'CFBundleIdentifier': identifier,
    'CFBundleName': 'WordNest',
    'CFBundleDisplayName': 'WordNest',
    'NSHumanReadableCopyright': 'Copyright © 2026 Albort. Code: MIT; artwork: separate license.',
    'CFBundleIconFile': 'WordNest',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': version,
    'CFBundleVersion': build,
    'LSMinimumSystemVersion': minimum,
    'LSUIElement': True,
    'NSHighResolutionCapable': True,
    'WordNestBuildMode': mode,
    'NSScreenCaptureUsageDescription': 'WordNest captures a screen frame only when you invoke lookup, to recognize text locally. It does not save or upload the image.',
    'NSAppleEventsUsageDescription': 'WordNest reads and writes your chosen vocabulary folder in Notes and reads the current Safari page title and URL when you invoke lookup.',
}
contents = Path(app) / 'Contents'
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
(contents / 'Resources/wordnest-managed-build.txt').write_text(identifier + '\n')
PY
if [[ "$build_mode" == release ]]; then
  codesign --force --sign "$signing_identity" --options runtime --timestamp \
    --entitlements "$project_dir/config/WordNest.entitlements" "$staging_app"
else
  codesign --force --sign "$signing_identity" "$staging_app"
  printf 'Local %s build: not a notarized release; signing changes may require new macOS permissions.\n' "$build_mode"
fi
codesign --verify --deep --strict "$staging_app"
# Validation above permits replacing only this builder's own managed product output.
if [[ -e "$app_dir" ]]; then rm -rf "$app_dir"; fi
mv "$staging_app" "$app_dir"
printf 'Built: %s\nMode: %s\nVersion: %s (%s)\n' "$app_dir" "$build_mode" "$WORDNEST_VERSION" "$WORDNEST_BUILD_NUMBER"
