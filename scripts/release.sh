#!/bin/zsh
# 构建可分发的测试版：通用二进制（Apple 芯片 + Intel），开发证书签名（未公证），输出 dist/AI订阅管家-<版本>.zip
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${AISUB_TEAM_ID:-}" ]]; then
  CERT=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/' || true)
  [[ -n "$CERT" ]] && AISUB_TEAM_ID=$(security find-certificate -c "$CERT" -p | openssl x509 -noout -subject | sed -E 's/.*OU=([A-Z0-9]+).*/\1/')
fi
[[ -n "${AISUB_TEAM_ID:-}" ]] || { echo "没有找到 Apple Development 证书"; exit 1; }
export AISUB_TEAM_ID

xcodegen generate >/dev/null
xcodebuild -project AISubscriptions.xcodeproj -scheme AISubscriptions -configuration Release -derivedDataPath build.noindex \
  CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build | grep -E "error:|BUILD" || true

SRC="build.noindex/Build/Products/Release/AISubscriptions.app"
VERSION=$(defaults read "$PWD/$SRC/Contents/Info.plist" CFBundleShortVersionString)
codesign --verify --deep --strict "$SRC"
rm -rf dist && mkdir -p dist/pkg
ditto "$SRC" "dist/pkg/AI订阅管家.app"          # 改名不影响签名
(cd dist/pkg && ditto -c -k --sequesterRsrc --keepParent "AI订阅管家.app" "../AI订阅管家-$VERSION.zip")
rm -rf dist/pkg
echo "已生成 dist/AI订阅管家-$VERSION.zip"
