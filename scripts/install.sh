#!/bin/zsh
# 构建并安装到 /Applications，让系统换上新版小组件。
# 小组件由系统进程 chronod 托管并缓存：版本号不变、旧进程还在、或 build 目录也登记了一份时，桌面会继续显示旧版。
set -euo pipefail
cd "$(dirname "$0")/.."
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
BUILD_APP="build.noindex/Build/Products/Debug/AISubscriptions.app"
DEST="/Applications/AI订阅管家.app"
VERSION=$(date +%Y%m%d%H%M)

# 签名团队：优先用环境变量，否则从钥匙串里第一张 Apple Development 证书读取（证书的 OU 字段就是团队 ID）
if [[ -z "${AISUB_TEAM_ID:-}" ]]; then
  CERT=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/' || true)
  [[ -n "$CERT" ]] && AISUB_TEAM_ID=$(security find-certificate -c "$CERT" -p | openssl x509 -noout -subject | sed -E 's/.*OU=([A-Z0-9]+).*/\1/')
fi
if [[ -z "${AISUB_TEAM_ID:-}" ]]; then
  echo "没有找到 Apple Development 证书。请在 Xcode → 设置 → 账户里登录 Apple ID（免费账号即可）并创建证书，"
  echo "或手动指定：AISUB_TEAM_ID=你的团队ID ./scripts/install.sh"
  exit 1
fi
export AISUB_TEAM_ID
echo "签名团队：$AISUB_TEAM_ID"

xcodegen generate >/dev/null
xcodebuild -project AISubscriptions.xcodeproj -scheme AISubscriptions -configuration Debug -derivedDataPath build.noindex \
  CURRENT_PROJECT_VERSION="$VERSION" build | grep -E "error:|BUILD" || true
[[ -d "$BUILD_APP" ]] || { echo "构建失败"; exit 1; }

pkill -x AISubscriptions || true
pkill -f AISubscriptionsWidget.appex || true
"$LSREG" -u "$PWD/$BUILD_APP" 2>/dev/null || true   # 只保留 /Applications 这一份登记（编译目录以 .noindex 结尾，聚焦搜索也不会收录）
rm -rf "$DEST"
ditto "$BUILD_APP" "$DEST"
"$LSREG" -f "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/AISubscriptionsWidget.appex" || true
killall chronod 2>/dev/null || true                 # 让系统重新读取小组件（会自动重启）
open "$DEST"
echo "已安装版本 $VERSION"
pluginkit -m -v -i local.dawang.aisubscriptions.widget
