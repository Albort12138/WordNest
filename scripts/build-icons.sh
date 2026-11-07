#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${SUBTITLE_LOOKUP_BUILD_DIR:-$project_dir/work/build}"
resources_dir="${1:?usage: build-icons.sh APP_RESOURCES_DIRECTORY}"
source_image="$project_dir/Assets/Branding/WordNest.png"
iconset_dir="$build_dir/WordNest.iconset"
mkdir -p "$iconset_dir" "$resources_dir"

# Resize and package the checked-in artwork; edit the original PNG to change the design.
# Native ICNS needs paired standard/Retina representations, not a renamed PNG.
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$source_image" --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" "$source_image" --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$resources_dir/WordNest.icns"
# Package the 20-point menu-bar image at 2x pixel resolution for Retina.
sips -z 40 40 "$source_image" --out "$resources_dir/WordNest-menu.png" >/dev/null
# Reuse the original transparent mascot in the first-run experience without runtime downloads.
cp "$source_image" "$resources_dir/WordNest-mascot.png"
# Keep the separate artwork terms with every generated app resource set.
cp "$project_dir/Assets/Branding/LICENSE" "$resources_dir/WordNest-artwork-LICENSE.txt"
