#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h:h}"
build_dir="$script_dir/build"
app_dir="$build_dir/DSH 大肥鱼.app"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
swiftc "$script_dir"/Sources/*.swift \
  -o "$app_dir/Contents/MacOS/WhaleGirlDesktop" \
  -framework AppKit \
  -framework QuartzCore \
  -framework Security \
  -O

cp "$script_dir/Info.plist" "$app_dir/Contents/Info.plist"
for asset in whale-girl whale-girl-closed; do
  cp "$project_dir/assets/$asset.png" "$app_dir/Contents/Resources/$asset.png"
done

codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
