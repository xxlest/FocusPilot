#!/bin/bash
# 创建本地自签名代码签名证书（一次性操作）
#
# 目的：替代 ad-hoc 签名，避免每次 make install 后辅助功能权限失效
# 原理：ad-hoc 签名的 CDHash 每次编译都变，TCC 权限按 CDHash 绑定所以失效
#       自签名证书的 identity 固定，TCC 通过 code requirement 匹配，权限持久有效
#
# ── 安全影响评估 ──
# 1. 在 login keychain 添加 1 个证书 + 1 个私钥（仅此而已，不修改其他密钥）
# 2. 将证书设为用户域代码签名信任（-d -p codeSign，不影响 SSL/邮件等）
# 3. 不修改系统 keychain、不需要 SIP 操作、不影响其他应用
# 4. 撤销方式：make clean-cert
#
# ── 交互说明 ──
# 脚本会弹出 2 次 macOS 授权对话框（需要输入密码），这是一次性操作：
#   - 第 1 次：导入证书到 keychain
#   - 第 2 次：设置证书信任（security add-trusted-cert）
# 之后 make install 签名时可能再弹 1 次 keychain 访问授权，选择"始终允许"即可

set -e

CERT_NAME="FocusPilot Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TMPDIR_CERT=$(mktemp -d)
trap "rm -rf $TMPDIR_CERT" EXIT

# 检查是否已存在且有效
if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "✅ 证书 \"$CERT_NAME\" 已存在且有效"
    security find-identity -v -p codesigning "$KEYCHAIN" | grep "$CERT_NAME"
    exit 0
fi

# 检查是否存在但未信任
if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "⚠️  证书 \"$CERT_NAME\" 已存在但未被信任，跳到信任步骤..."
else
    echo "🔑 正在创建自签名代码签名证书: $CERT_NAME"
    echo ""

    # 1. 生成私钥
    openssl genrsa -out "$TMPDIR_CERT/dev.key" 2048 2>/dev/null

    # 2. 创建自签名证书（有效期 10 年，含 Code Signing 扩展）
    openssl req -new -x509 \
        -key "$TMPDIR_CERT/dev.key" \
        -out "$TMPDIR_CERT/dev.crt" \
        -days 3650 \
        -subj "/CN=$CERT_NAME" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=codeSigning" \
        2>/dev/null

    # 3. 打包为 PKCS12（Keychain 导入需要此格式）
    #    -legacy: OpenSSL 3.x 默认新算法，macOS security 不兼容，需降级
    openssl pkcs12 -export \
        -out "$TMPDIR_CERT/dev.p12" \
        -inkey "$TMPDIR_CERT/dev.key" \
        -in "$TMPDIR_CERT/dev.crt" \
        -passout pass:temp \
        -legacy \
        2>/dev/null

    # 4. 导入到 login keychain
    security import "$TMPDIR_CERT/dev.p12" \
        -k "$KEYCHAIN" \
        -P temp \
        -T /usr/bin/codesign \
        -T /usr/bin/security \
        > /dev/null 2>&1

    echo "✓ 证书已导入到 login keychain"
fi

# 5. 设置证书信任（用于代码签名）
#    -d = 用户域（不影响系统域）
#    -p codeSign = 仅限代码签名（不影响 SSL、邮件等信任策略）
#    这一步会弹出 macOS 授权对话框，需要输入用户密码
echo ""
echo "📋 接下来需要在弹出的对话框中输入密码，将证书设为可信..."
echo "   （这是一次性操作，之后 make install 不再需要手动授权辅助功能）"
echo ""

# 提取证书用于设置信任
security find-certificate -c "$CERT_NAME" -p "$KEYCHAIN" > "$TMPDIR_CERT/trust.pem"

if security add-trusted-cert -d -r trustRoot -p codeSign "$TMPDIR_CERT/trust.pem"; then
    echo ""
    echo "✅ 证书创建并信任成功！"
    security find-identity -v -p codesigning "$KEYCHAIN" | grep "$CERT_NAME"
    echo ""
    echo "📌 效果："
    echo "   - make install 将自动使用此证书签名"
    echo "   - 首次安装仍需手动授权一次辅助功能权限"
    echo "   - 之后重新安装不再需要重新授权（权限持久有效）"
    echo ""
    echo "🗑  如需撤销：make clean-cert"
else
    echo ""
    echo "❌ 证书信任设置被取消"
    echo "   请重新运行 make setup-cert 并在弹出对话框中输入密码"
    echo "   或者在 Keychain Access 中手动信任 \"$CERT_NAME\" 证书"
    exit 1
fi
