#!/usr/bin/env bash
# 构建 SelectTranslate.app
#
#   ./build.sh            编译并打包到 dist/SelectTranslate.app
#   ./build.sh install    打包后安装到 /Applications（不可写时用 ~/Applications）并启动
#   ./build.sh run        打包后直接从 dist 启动
#
# 环境变量：
#   CONFIG=debug          调试构建（默认 release）
#   SIGN_IDENTITY="名称"  用钥匙串里指定的证书签名；设为 - 时使用 ad-hoc 签名。
#                         不设置时：运行过 scripts/setup_signing.sh 就用本机签名证书
#                         （重新编译后辅助功能授权仍然有效），否则使用 ad-hoc 签名。
#   SELECTTRANSLATE_SCRATCH_PATH  SwiftPM 构建目录（默认 .build）
#   SELECTTRANSLATE_OUTPUT_DIR    App 输出目录（默认 dist）
# 使用 xcrun 选择的工具链，遵循 DEVELOPER_DIR / TOOLCHAINS；不修改全局配置。
set -euo pipefail

APP_NAME="SelectTranslate"
CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
LOCAL_SIGNING_KEYCHAIN="$HOME/Library/Keychains/selecttranslate-signing.keychain-db"
LOCAL_SIGNING_IDENTITY="SelectTranslate Local Signing"
ACTION="${1:-}"

fail() {
  echo "错误：$*" >&2
  exit 1
}

[[ $# -le 1 ]] || fail "只接受一个参数：install 或 run；不带参数时只打包。"
case "$ACTION" in
  ""|install|run) ;;
  *) fail "未知参数：${ACTION}（可用：install、run）" ;;
esac
case "$CONFIG" in
  debug|release) ;;
  *) fail "CONFIG 必须是 debug 或 release。" ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")"
SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(/usr/bin/xcrun --sdk macosx --show-sdk-version)"
IFS=. read -r SDK_MAJOR SDK_MINOR _ <<< "$SDK_VERSION"
[[ "$SDK_MAJOR" =~ ^[0-9]+$ && "${SDK_MINOR:-}" =~ ^[0-9]+$ ]] \
  || fail "无法识别 macOS SDK 版本：$SDK_VERSION"
(( SDK_MAJOR > 26 || (SDK_MAJOR == 26 && SDK_MINOR >= 4) )) \
  || fail "构建需要 macOS 26.4 或更高版本的 SDK，当前为 ${SDK_VERSION}。"

BUILD_ARGS=(-c "$CONFIG" --sdk "$SDK_PATH")
if [[ -n "${SELECTTRANSLATE_SCRATCH_PATH:-}" ]]; then
  BUILD_ARGS+=(--scratch-path "$SELECTTRANSLATE_SCRATCH_PATH")
fi
OUTPUT_DIR="${SELECTTRANSLATE_OUTPUT_DIR:-dist}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
APP="$OUTPUT_DIR/$APP_NAME.app"

# 只检查目标 App 的可执行文件路径，保留其他位置的同名应用。
assert_app_not_running() {
  local target="$1" canonical_target processes pid executable
  canonical_target="$target"
  if [[ -e "$target" ]]; then
    [[ -d "$target" ]] || fail "目标不是 App 目录：$target"
    canonical_target="$(cd "$target" && pwd -P)"
  fi
  processes="$(/bin/ps -ww -axo pid=,comm=)"
  while read -r pid executable; do
    if [[ "$executable" == "$target/Contents/MacOS/$APP_NAME" \
       || "$executable" == "$canonical_target/Contents/MacOS/$APP_NAME" ]]; then
      fail "目标 App 仍在运行（PID ${pid}）：${target}。请先正常退出，再重试。"
    fi
  done <<< "$processes"
}

assert_app_not_running "$APP"
if [[ "$ACTION" == install ]]; then
  DEST="/Applications"
  [[ -w "$DEST" ]] || DEST="$HOME/Applications"
  mkdir -p "$DEST"
  DEST="$(cd "$DEST" && pwd -P)"
  INSTALLED_APP="$DEST/$APP_NAME.app"
  [[ "$INSTALLED_APP" != "$APP" ]] || fail "输出目录不能与安装目录相同。"
  assert_app_not_running "$INSTALLED_APP"
fi

echo "▸ 编译（${CONFIG}，macOS SDK ${SDK_VERSION}）"
/usr/bin/xcrun --sdk macosx swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(/usr/bin/xcrun --sdk macosx swift build "${BUILD_ARGS[@]}" --show-bin-path)"

if [[ ! -f Resources/AppIcon.icns ]]; then
  echo "▸ 生成图标"
  /usr/bin/xcrun --sdk macosx swift -sdk "$SDK_PATH" scripts/make_icon.swift Resources/AppIcon.icns
fi

echo "▸ 打包 $APP"
assert_app_not_running "$APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "$SIGN_IDENTITY" ]]; then
  SIGN_ARGS=(--sign "$SIGN_IDENTITY")
  SIGN_LABEL="${SIGN_IDENTITY/#-/ad-hoc}"
elif [[ -f "$LOCAL_SIGNING_KEYCHAIN" ]]; then
  # 本机签名钥匙串没有密码；重启后处于锁定状态，签名前先解锁
  /usr/bin/security unlock-keychain -p "" "$LOCAL_SIGNING_KEYCHAIN"
  SIGN_ARGS=(--sign "$LOCAL_SIGNING_IDENTITY" --keychain "$LOCAL_SIGNING_KEYCHAIN")
  SIGN_LABEL="$LOCAL_SIGNING_IDENTITY"
else
  SIGN_ARGS=(--sign -)
  SIGN_LABEL="ad-hoc"
fi
echo "▸ 签名（${SIGN_LABEL}）"
/usr/bin/codesign --force "${SIGN_ARGS[@]}" "$APP"
/usr/bin/codesign --verify --strict "$APP"
if [[ "$SIGN_LABEL" == ad-hoc ]]; then
  echo "  提示：ad-hoc 签名每次编译都会变化，更新后需要重新授予辅助功能权限。"
  echo "  运行一次 scripts/setup_signing.sh 后，重新编译不再需要重新授权。"
fi

case "$ACTION" in
  install)
    assert_app_not_running "$INSTALLED_APP"
    rm -rf "$INSTALLED_APP"
    cp -R "$APP" "$DEST/"
    echo "▸ 已安装到 $INSTALLED_APP"
    open "$INSTALLED_APP"
    ;;
  run)
    assert_app_not_running "$APP"
    open "$APP"
    ;;
  "")
    echo "▸ 完成：$APP"
    ;;
esac
