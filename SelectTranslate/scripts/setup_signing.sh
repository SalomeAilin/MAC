#!/usr/bin/env bash
# 为 SelectTranslate 创建本机专用的代码签名证书（只需运行一次）
#
# ad-hoc 签名每次编译都会变化，macOS 会把新版本当成另一个 App，需要重新授予辅助功能权限。
# 改用固定证书签名后，系统按「证书 + Bundle ID」识别 App，重新编译不再需要重新授权。
#
# 证书是自签名的，只用于在本机签名：存放在单独的钥匙串文件里，不加入钥匙串搜索列表，
# 不改动登录钥匙串和系统信任设置。本机的其他程序也能使用这个证书，
# 开发者电脑上的签名证书都是如此。删除证书：
#   security delete-keychain ~/Library/Keychains/selecttranslate-signing.keychain-db
set -euo pipefail

KEYCHAIN="$HOME/Library/Keychains/selecttranslate-signing.keychain-db"
IDENTITY="SelectTranslate Local Signing"

has_identity() {
  [[ -f "$KEYCHAIN" ]] && /usr/bin/security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$IDENTITY\""
}

if has_identity; then
  echo "签名证书已存在：$IDENTITY（$KEYCHAIN）"
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/selecttranslate-signing.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "▸ 生成自签名代码签名证书（有效期 10 年）"
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -subj "/CN=$IDENTITY" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
P12_PASSWORD="$(/usr/bin/uuidgen)"
/usr/bin/openssl pkcs12 -export -name "$IDENTITY" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" -passout "pass:$P12_PASSWORD"

# 钥匙串不设密码、不自动锁定：密码只能写在本机脚本里，起不到保护作用
echo "▸ 存入单独的钥匙串：$KEYCHAIN"
[[ -f "$KEYCHAIN" ]] || /usr/bin/security create-keychain -p "" "$KEYCHAIN"
/usr/bin/security set-keychain-settings "$KEYCHAIN"
/usr/bin/security unlock-keychain -p "" "$KEYCHAIN"
/usr/bin/security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null
# 允许 codesign 直接使用私钥，签名时不弹出钥匙串授权窗口
/usr/bin/security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null

has_identity || { echo "错误：证书没有成功导入 $KEYCHAIN" >&2; exit 1; }
echo "▸ 完成：之后 ./build.sh 会自动用「$IDENTITY」签名。"
echo "  从 ad-hoc 签名切换过来后，需要最后再授权一次辅助功能权限；之后重新编译不再需要。"
