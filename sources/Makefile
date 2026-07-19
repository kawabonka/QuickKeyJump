# QuickFolderJump - Makefile
# 使用 swiftc 命令行编译，无需 Xcode 项目文件
# 作者: QuickFolderJump Team

# === 配置 ===

# 应用名称
APP_NAME := QuickFolderJump
BUNDLE_ID := com.quickfolderjump.app

# 目录（使用 .build 避免与 make 目标名冲突）
BUILD_DIR := .build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_BUNDLE)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources

# Swift 源文件（按依赖顺序排列）
SOURCES := \
	main.swift \
	RecentFolderManager.swift \
	KeyboardHandler.swift \
	QuickJumpView.swift \
	QuickJumpPanel.swift \
	DialogNavigator.swift \
	FinderWindowNavigator.swift \
	AppDelegate.swift

# 需要链接的系统框架
FRAMEWORKS := \
	-framework Cocoa \
	-framework Carbon \
	-framework ApplicationServices \
	-framework SwiftUI

# 编译器配置
SWIFTC := swiftc
# 优化级别：-O（优化）或 -Ounchecked（不检查边界，性能最高）
OPTIMIZE := -O
# SDK 路径（自动检测）
SDK_PATH := $(shell xcrun --show-sdk-path --sdk macosx15 2>/dev/null || xcrun --show-sdk-path --sdk macosx 2>/dev/null || echo "")
SDK_FLAGS := $(if $(SDK_PATH),-sdk $(SDK_PATH),)

# 完整编译参数
SWIFT_FLAGS := \
	-parse-as-library \
	$(OPTIMIZE) \
	$(SDK_FLAGS) \
	$(FRAMEWORKS) \
	-I $(BUILD_DIR) \
	-o $(BUILD_DIR)/$(APP_NAME)

# === 目标 ===

# 默认目标：构建应用
.PHONY: all build clean run install uninstall help

all: build

# 显示帮助信息
help:
	@echo "QuickFolderJump - 构建工具"
	@echo ""
	@echo "使用方法:"
	@echo "  make build    - 编译应用（默认）"
	@echo "  make clean    - 清理构建产物"
	@echo "  make run      - 编译并运行应用"
	@echo "  make install  - 安装到 /Applications"
	@echo "  make uninstall- 从 /Applications 移除"
	@echo "  make help     - 显示此帮助"
	@echo ""
	@echo "编译选项:"
	@echo "  优化级别: $(OPTIMIZE)"
	@echo "  SDK路径:  $(SDK_PATH)"

# 创建构建目录
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# 编译可执行文件（直接输出二进制，不打包成 .app）
build-binary: $(BUILD_DIR)
	@echo "=== 编译 QuickFolderJump ==="
	$(SWIFTC) $(SOURCES) $(SWIFT_FLAGS)
	@echo "=== 编译完成: $(BUILD_DIR)/$(APP_NAME) ==="

# 构建完整的 .app 应用包
build: clean $(BUILD_DIR)
	@echo "=== 构建 $(APP_NAME).app ==="
	@echo "1. 创建目录结构..."
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES_DIR)
	
	@echo "2. 编译 Swift 源码..."
	$(SWIFTC) $(SOURCES) $(SWIFT_FLAGS)
	
	@echo "3. 复制可执行文件到应用包..."
	@cp $(BUILD_DIR)/$(APP_NAME) $(MACOS_DIR)/
	@chmod +x $(MACOS_DIR)/$(APP_NAME)
	
	@echo "4. 复制 Info.plist..."
	@cp Info.plist $(CONTENTS_DIR)/
	
	@echo "5. 写入 PkgInfo..."
	@echo "APPL????" > $(CONTENTS_DIR)/PkgInfo
	
	@echo "=== 构建完成: $(APP_BUNDLE) ==="

# 清理构建产物
clean:
	@echo "=== 清理构建产物 ==="
	@rm -rf $(BUILD_DIR)
	@echo "=== 清理完成 ==="

# 编译并运行（用于开发调试）
run: build-binary
	@echo "=== 启动 QuickFolderJump ==="
	@$(BUILD_DIR)/$(APP_NAME)

# 安装到 /Applications
install: build
	@echo "=== 安装到 /Applications ==="
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "=== 安装完成: /Applications/$(APP_NAME).app ==="
	@echo "提示: 首次运行请在 系统设置 > 隐私与安全性 > 辅助功能 中授权"

# 从 /Applications 卸载
uninstall:
	@echo "=== 从 /Applications 卸载 ==="
	@rm -rf /Applications/$(APP_NAME).app
	@echo "=== 卸载完成 ==="

# 代码签名（开发测试用，使用 ad-hoc 签名）
sign: build
	@echo "=== 代码签名 ==="
	@codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "=== 签名完成 ==="
