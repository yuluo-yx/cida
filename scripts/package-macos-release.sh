#!/bin/zsh
# Build ad hoc signed macOS packages without upstream publishing credentials.
# Releases target Apple Silicon only.
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
version=${CIDA_VERSION:?Set CIDA_VERSION to the release version}
architecture=arm64
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "CIDA_VERSION must be three numbers such as 1.6.0" >&2
  exit 64
fi

output_dir="$project_dir/build/releases"
mkdir -p "$output_dir"
staging_root=$(mktemp -d "$project_dir/build/.cida-package.XXXXXX")
# This directory contains only this invocation's generated packaging files.
trap '/bin/rm -r "$staging_root"' EXIT
app_path="$staging_root/Cida.app"
asset_name="Cida-$version-macos-$architecture"

swift build --package-path "$project_dir" --configuration release --arch "$architecture" \
  -Xswiftc -warnings-as-errors
bin_path=$(swift build --package-path "$project_dir" --configuration release \
  --arch "$architecture" --show-bin-path)
"$script_dir/assemble-app.sh" "$bin_path/Cida" "$app_path"
info="$app_path/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$version" "$info"
/usr/bin/plutil -replace CFBundleVersion -string "$(git -C "$project_dir" rev-list --count HEAD)" "$info"
# A fork must not install an upstream build through Sparkle's unrelated update channel.
/usr/bin/plutil -remove SUFeedURL "$info"
/usr/bin/plutil -remove SUPublicEDKey "$info"
/usr/bin/plutil -lint "$info"
/usr/bin/xattr -cr "$app_path"
"$script_dir/sign-app.sh" "$app_path" - --timestamp=none
/usr/bin/lipo -verify_arch "$architecture" "$app_path/Contents/MacOS/Cida"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_dir/$asset_name.zip"
image_root="$staging_root/image"
mkdir -p "$image_root"
/usr/bin/ditto "$app_path" "$image_root/Cida.app"
ln -s /Applications "$image_root/Applications"
/usr/bin/hdiutil create -volname Cida -srcfolder "$image_root" -ov -format UDZO \
  "$output_dir/$asset_name.dmg"
/usr/bin/hdiutil verify "$output_dir/$asset_name.dmg"

# Verify the distributed ZIP and its nested signatures, not only the source bundle.
mkdir -p "$staging_root/verification"
/usr/bin/ditto -x -k "$output_dir/$asset_name.zip" "$staging_root/verification"
/usr/bin/codesign --verify --deep --strict "$staging_root/verification/Cida.app"
echo "Packaged $asset_name.dmg and $asset_name.zip"
