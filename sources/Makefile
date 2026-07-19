# QuickKeyJump - Makefile
# 使用 swiftc 命令行编译

APP_NAME := QuickKeyJump
BUNDLE_ID := com.quickkeyjump.app

BUILD_DIR := .build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_BUNDLE)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources

SOURCES := \
	main.swift \
	SettingsManager.swift \
	RecentFolderManager.swift \
	KeyboardHandler.swift \
	QuickJumpView.swift \
	QuickJumpPanel.swift \
	ShortcutRecorderPanel.swift \
	SettingsView.swift \
	DialogNavigator.swift \
	FinderWindowNavigator.swift \
	LaunchManager.swift \
	WindowManager.swift \
	WindowManagementPanel.swift \
	AppDelegate.swift

FRAMEWORKS := \
	-framework Cocoa \
	-framework Carbon \
	-framework ApplicationServices \
	-framework SwiftUI

SWIFTC := xcrun swiftc
OPTIMIZE := -O
SDK_PATH := $(shell xcrun --show-sdk-path --sdk macosx15 2>/dev/null || xcrun --show-sdk-path --sdk macosx 2>/dev/null || echo "")
SDK_FLAGS := $(if $(SDK_PATH),-sdk $(SDK_PATH),)

SWIFT_FLAGS := \
	-parse-as-library \
	$(OPTIMIZE) \
	$(SDK_FLAGS) \
	$(FRAMEWORKS) \
	-module-cache-path /tmp/swift-module-cache \
	-o $(BUILD_DIR)/$(APP_NAME)

.PHONY: all build clean run install uninstall help

all: build

help:
	@echo "QuickKeyJump - 构建工具"
	@echo ""
	@echo "make build    - 编译应用"
	@echo "make clean    - 清理构建产物"
	@echo "make run      - 编译并运行"
	@echo "make install  - 安装到 /Applications"
	@echo "make uninstall- 从 /Applications 移除"

build: clean $(BUILD_DIR)
	@echo "=== 构建 $(APP_NAME).app ==="
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)
	@echo "编译 Swift 源码..."
	$(SWIFTC) $(SOURCES) $(SWIFT_FLAGS)
	@echo "复制资源文件..."
	@cp $(BUILD_DIR)/$(APP_NAME) $(MACOS_DIR)/
	@chmod +x $(MACOS_DIR)/$(APP_NAME)
	@cp Info.plist $(CONTENTS_DIR)/
	@cp AppIcon.icns $(RESOURCES_DIR)/
	@echo "APPL????" > $(CONTENTS_DIR)/PkgInfo
	@echo "=== 构建完成: $(APP_BUNDLE) ==="

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

build-binary: $(BUILD_DIR)
	@echo "=== 编译 $(APP_NAME) ==="
	$(SWIFTC) $(SOURCES) $(SWIFT_FLAGS)
	@echo "=== 完成: $(BUILD_DIR)/$(APP_NAME) ==="

clean:
	@rm -rf $(BUILD_DIR)

run: build-binary
	@echo "=== 启动 $(APP_NAME) ==="
	@$(BUILD_DIR)/$(APP_NAME)

install: build
	@echo "=== 安装到 /Applications ==="
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "=== 完成: /Applications/$(APP_NAME).app ==="

uninstall:
	@rm -rf /Applications/$(APP_NAME).app

sign: build
	@codesign --force --deep --sign - $(APP_BUNDLE)
