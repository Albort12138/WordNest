#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../config/product.env
source "$project_dir/config/product.env"
# Standalone tests resolve bundled sample resources relative to the checkout.
cd "$project_dir"
build_dir="${SUBTITLE_LOOKUP_BUILD_DIR:-$project_dir/work/build}"
mkdir -p "$build_dir/module-cache"
sources=(TextResources InterfaceLanguage ProductRuntime LanguageSupport LookupCore TextRecognizer SystemDictionary MDXReader RIPEMD128 DictionaryProvider DictionarySettings WordSpeaker Vocabulary CollectionSource SourceCapture SourceAnalysis AppleNotes AlphabetBook AlphabetNotes NotesSettings SetupCoordinator SetupWindow)
source_paths=()
for name in "${sources[@]}"; do source_paths+=("$project_dir/Sources/$name.swift"); done
xcrun swiftc -swift-version 5 -O -target "$WORDNEST_ARCH-apple-macosx$WORDNEST_MINIMUM_MACOS" \
  -module-cache-path "$build_dir/module-cache" "${source_paths[@]}" \
  "$project_dir/Tests/NotesTests.swift" \
  "$project_dir/Tests/SourceTests.swift" \
  "$project_dir/Tests/AlphabetTests.swift" \
  "$project_dir/Tests/LanguageTests.swift" \
  "$project_dir/Tests/SetupTests.swift" \
  "$project_dir/Tests/InterfaceLanguageTests.swift" \
  "$project_dir/Tests/ProductTests.swift" \
  "$project_dir/Tests/DictionaryTests.swift" \
  "$project_dir/Tests/main.swift" \
  -framework AppKit -framework Carbon -framework CoreText -framework Vision -framework CoreServices -framework AVFoundation -framework NaturalLanguage -lz \
  -o "$build_dir/lookup-tests"
FIXTURE_OUTPUT="$build_dir/fixture.png" "$build_dir/lookup-tests" "$@"
