#!/bin/zsh
# 构建 Release 版 ScriptTimer 并安装到 /Applications
#   ./scripts/build.sh            构建并安装
#   ./scripts/build.sh --no-install   只构建，产物在 build/Build/Products/Release/
set -euo pipefail
cd "${0:A:h}/.."

command -v xcodegen >/dev/null || { echo "需要 xcodegen：brew install xcodegen"; exit 1; }
xcodegen generate --quiet

xcodebuild -project ScriptTimer.xcodeproj -scheme ScriptTimer -configuration Release \
  -derivedDataPath build build -quiet

app="build/Build/Products/Release/ScriptTimer.app"
codesign --force --deep --sign - "$app"
echo "构建完成：$app"

if [[ ${1:-} != --no-install ]]; then
  osascript -e 'quit app "ScriptTimer"' 2>/dev/null || true
  sleep 1
  rm -rf /Applications/ScriptTimer.app
  cp -R "$app" /Applications/
  echo "已安装到 /Applications/ScriptTimer.app"
  open /Applications/ScriptTimer.app
fi
