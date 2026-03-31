# FocusPilot Build & Install
# 适用于仅安装 Command Line Tools（无 Xcode IDE）的环境

APP_NAME     := FocusPilot
BUNDLE_ID    := com.focuspilot.FocusPilot
VERSION      := 2.0
BUILD_NUM    := 1
MIN_MACOS    := 14.0

# 代码签名 identity（自签名证书 > ad-hoc）
# 使用自签名证书时，TCC 按证书 identity 匹配权限，重新安装不会丢失辅助功能权限
# 运行 make setup-cert 创建证书（一次性操作）
SIGN_IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null | grep "FocusPilot Dev" | head -1 | sed 's/.*"\(.*\)"/\1/' || echo "")

BUILD_DIR    := /tmp/focuspilot-build
APP_BUNDLE   := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR  := /Applications
INSTALL_APP  := $(INSTALL_DIR)/$(APP_NAME).app

SDK          := $(shell xcrun --show-sdk-path)
SOURCES      := $(shell find FocusPilot -name "*.swift" | sort)

# VFS overlay（解决 Command Line Tools SwiftBridging module 重复定义 bug）
VFSOVERLAY   := $(BUILD_DIR)/vfsoverlay.yaml

.PHONY: all build install clean uninstall setup-cert clean-cert

all: build

# ── 构建 ──────────────────────────────────────────────
build: $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) $(APP_BUNDLE)/Contents/Info.plist $(APP_BUNDLE)/Contents/PkgInfo $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@echo "✓ 构建完成: $(APP_BUNDLE)"

$(VFSOVERLAY):
	@mkdir -p $(BUILD_DIR)
	@echo 'version: 0'                                         >  $@
	@echo 'roots:'                                              >> $@
	@echo '  - name: /Library/Developer/CommandLineTools/usr/include/swift' >> $@
	@echo '    type: directory'                                 >> $@
	@echo '    contents:'                                       >> $@
	@echo '      - name: module.modulemap'                      >> $@
	@echo '        type: file'                                  >> $@
	@echo '        external-contents: /dev/null'                >> $@

$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME): $(SOURCES) $(VFSOVERLAY)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	swiftc -o $@ \
		-swift-version 5 \
		-sdk $(SDK) \
		-target arm64-apple-macosx$(MIN_MACOS) \
		-Xfrontend -vfsoverlay -Xfrontend $(VFSOVERLAY) \
		-framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement \
		-O $(SOURCES)
	@echo "✓ 编译完成"

$(APP_BUNDLE)/Contents/Info.plist: FocusPilot/Resources/Info.plist
	@mkdir -p $(APP_BUNDLE)/Contents
	@sed \
		-e 's/$$(DEVELOPMENT_LANGUAGE)/zh_CN/g' \
		-e 's/$$(EXECUTABLE_NAME)/$(APP_NAME)/g' \
		-e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/$(BUNDLE_ID)/g' \
		-e 's/$$(PRODUCT_NAME)/FocusPilot/g' \
		FocusPilot/Resources/Info.plist > $@
	@# 追加运行时所需的 key（源 plist 中没有的）
	@/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $(MIN_MACOS)" $@ 2>/dev/null || true
	@# LSUIElement 已移除，App 显示在 Dock 中
	@/usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" $@ 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Add :NSAccessibilityUsageDescription string FocusPilot 需要辅助功能权限来管理窗口切换。" $@ 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" $@ 2>/dev/null || true
	@echo "✓ Info.plist 已生成（变量已解析）"

$(APP_BUNDLE)/Contents/Resources/AppIcon.icns: scripts/gen-icon.swift $(VFSOVERLAY)
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@echo "  生成应用图标..."
	@swiftc -swift-version 5 -sdk $(SDK) -target arm64-apple-macosx$(MIN_MACOS) \
		-Xfrontend -vfsoverlay -Xfrontend $(VFSOVERLAY) \
		-framework AppKit -O -o $(BUILD_DIR)/gen-icon scripts/gen-icon.swift
	@$(BUILD_DIR)/gen-icon $(BUILD_DIR)
	@cp $(BUILD_DIR)/AppIcon.icns $@
	@echo "✓ AppIcon.icns 已生成"

$(APP_BUNDLE)/Contents/PkgInfo:
	@mkdir -p $(APP_BUNDLE)/Contents
	@echo -n "APPL????" > $@

# ── 安装 ──────────────────────────────────────────────
install: build
	@# 关闭正在运行的旧进程（兼容新旧名称）
	@-pkill -x $(APP_NAME) 2>/dev/null; pkill -x FocusPilot 2>/dev/null; sleep 1
	@# 删除旧 App（确保 Spotlight 刷新）
	@rm -rf $(INSTALL_APP)
	@rm -rf $(INSTALL_DIR)/FocusPilot.app
	@# 复制新 App
	@cp -R $(APP_BUNDLE) $(INSTALL_APP)
	@# 签名：优先使用自签名证书（权限持久），否则降级为 ad-hoc（每次需重新授权）
ifneq ($(SIGN_IDENTITY),)
	@echo "🔑 使用证书签名: $(SIGN_IDENTITY)"
	@codesign --force --deep --sign "$(SIGN_IDENTITY)" $(INSTALL_APP)
else
	@echo "⚠️  未找到签名证书，使用 ad-hoc 签名（每次安装需重新授权辅助功能）"
	@echo "   运行 make setup-cert 创建证书可永久解决此问题"
	@codesign --force --deep --sign - $(INSTALL_APP)
	@# ad-hoc 签名需要重置 TCC 条目
	@-tccutil reset Accessibility $(BUNDLE_ID) 2>/dev/null
endif
	@# 触发 Spotlight 重新索引
	@touch $(INSTALL_APP)
	@mdimport $(INSTALL_APP)
	@echo "✓ 已安装到 $(INSTALL_APP)"
	@echo "✓ 正在启动..."
	@open $(INSTALL_APP)
	@echo ""
	@echo "✅ FocusPilot 已安装并启动"
ifneq ($(SIGN_IDENTITY),)
	@echo "🔑 已使用证书签名，辅助功能权限无需重新授权"
else
	@echo ""
	@echo "⚠️  重新安装后需要重新授权辅助功能权限："
	@echo "   系统设置 → 隐私与安全性 → 辅助功能"
	@echo "   找到 FocusPilot → 关闭 → 重新开启"
	@echo ""
	@echo "   正在打开系统设置..."
	@open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
endif

# ── 证书设置（一次性）─────────────────────────────────
setup-cert:
	@bash scripts/setup-cert.sh

# ── 撤销证书 ──────────────────────────────────────────
clean-cert:
	@echo "🗑  正在删除 FocusPilot Dev 签名证书..."
	@-security delete-identity -c "FocusPilot Dev" ~/Library/Keychains/login.keychain-db 2>/dev/null
	@echo "✓ 证书已删除（如有），下次 make install 将回退到 ad-hoc 签名"

# ── 清理 ──────────────────────────────────────────────
clean:
	rm -rf $(BUILD_DIR)
	@echo "✓ 已清理构建目录"

# ── 卸载 ──────────────────────────────────────────────
uninstall:
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@pkill -x FocusPilot 2>/dev/null || true
	@rm -rf $(INSTALL_APP)
	@rm -rf $(INSTALL_DIR)/FocusPilot.app
	@echo "✓ 已卸载 $(APP_NAME)"
