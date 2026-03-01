# PinTop Build & Install
# 适用于仅安装 Command Line Tools（无 Xcode IDE）的环境

APP_NAME     := PinTop
BUNDLE_ID    := com.pintop.PinTop
VERSION      := 1.0
BUILD_NUM    := 1
MIN_MACOS    := 14.0

BUILD_DIR    := /tmp/pintop-build
APP_BUNDLE   := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR  := /Applications
INSTALL_APP  := $(INSTALL_DIR)/$(APP_NAME).app

SDK          := $(shell xcrun --show-sdk-path)
SOURCES      := $(shell find PinTop -name "*.swift" | sort)

# VFS overlay（解决 Command Line Tools SwiftBridging module 重复定义 bug）
VFSOVERLAY   := $(BUILD_DIR)/vfsoverlay.yaml

.PHONY: all build install clean uninstall

all: build

# ── 构建 ──────────────────────────────────────────────
build: $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) $(APP_BUNDLE)/Contents/Info.plist $(APP_BUNDLE)/Contents/PkgInfo
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

$(APP_BUNDLE)/Contents/Info.plist: PinTop/Resources/Info.plist
	@mkdir -p $(APP_BUNDLE)/Contents
	@sed \
		-e 's/$$(DEVELOPMENT_LANGUAGE)/zh_CN/g' \
		-e 's/$$(EXECUTABLE_NAME)/$(APP_NAME)/g' \
		-e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/$(BUNDLE_ID)/g' \
		-e 's/$$(PRODUCT_NAME)/$(APP_NAME)/g' \
		PinTop/Resources/Info.plist > $@
	@# 追加运行时所需的 key（源 plist 中没有的）
	@/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $(MIN_MACOS)" $@ 2>/dev/null || true
	@# LSUIElement 已移除，App 显示在 Dock 中
	@/usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" $@ 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Add :NSAccessibilityUsageDescription string PinTop 需要辅助功能权限来管理窗口置顶和排列。" $@ 2>/dev/null || true
	@echo "✓ Info.plist 已生成（变量已解析）"

$(APP_BUNDLE)/Contents/PkgInfo:
	@mkdir -p $(APP_BUNDLE)/Contents
	@echo -n "APPL????" > $@

# ── 安装 ──────────────────────────────────────────────
install: build
	@# 关闭正在运行的旧进程
	@-pkill -x $(APP_NAME) 2>/dev/null; sleep 1
	@# 删除旧 App（确保 Spotlight 刷新）
	@rm -rf $(INSTALL_APP)
	@# 复制新 App
	@cp -R $(APP_BUNDLE) $(INSTALL_APP)
	@# 签名（ad-hoc 签名会改变 CDHash，导致 TCC 权限失效）
	@codesign --force --deep --sign - $(INSTALL_APP)
	@# 重置辅助功能权限（清除旧 CDHash 对应的 TCC 条目）
	@-tccutil reset Accessibility $(BUNDLE_ID) 2>/dev/null
	@# 触发 Spotlight 重新索引
	@touch $(INSTALL_APP)
	@mdimport $(INSTALL_APP)
	@echo "✓ 已安装到 $(INSTALL_APP)"
	@echo "✓ 正在启动..."
	@open $(INSTALL_APP)
	@echo ""
	@echo "✅ PinTop 已安装并启动"
	@echo ""
	@echo "⚠️  重新安装后需要重新授权辅助功能权限："
	@echo "   系统设置 → 隐私与安全性 → 辅助功能"
	@echo "   找到 PinTop → 关闭 → 重新开启"
	@echo ""

# ── 清理 ──────────────────────────────────────────────
clean:
	rm -rf $(BUILD_DIR)
	@echo "✓ 已清理构建目录"

# ── 卸载 ──────────────────────────────────────────────
uninstall:
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@rm -rf $(INSTALL_APP)
	@echo "✓ 已卸载 $(APP_NAME)"
