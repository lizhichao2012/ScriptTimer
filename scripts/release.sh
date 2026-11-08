#!/bin/zsh
# 打包可分发的安装版本（通用二进制 arm64 + x86_64，ad-hoc 签名）
#   ./scripts/release.sh     产物：dist/ScriptTimer-<版本>.dmg 和 .zip
set -euo pipefail
cd "${0:A:h}/.."

command -v xcodegen >/dev/null || { echo "需要 xcodegen：brew install xcodegen"; exit 1; }
xcodegen generate --quiet

version=$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' project.yml)
[[ -n $version ]] || { echo "无法从 project.yml 读取 MARKETING_VERSION"; exit 1; }

rm -rf build/Build/Products/Release
xcodebuild -project ScriptTimer.xcodeproj -scheme ScriptTimer -configuration Release \
  -derivedDataPath build -destination "generic/platform=macOS" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build -quiet

app="build/Build/Products/Release/ScriptTimer.app"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
echo "架构：$(lipo -archs "$app/Contents/MacOS/ScriptTimer")"

mkdir -p dist
dmg="dist/ScriptTimer-$version.dmg"
zip="dist/ScriptTimer-$version.zip"
rm -f "$dmg" "$zip"

# DMG：App + 指向 /Applications 的快捷方式，打开后拖进去即可安装
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "ScriptTimer $version" -srcfolder "$staging" -ov -format UDZO "$dmg" -quiet

ditto -c -k --keepParent "$app" "$zip"

shasum -a 256 "$dmg" "$zip"
echo "完成：$dmg、$zip"
