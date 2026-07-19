APP_NAME := QuickKeyJump
BUNDLE_ID := com.quickkeyjump.app

BUILD_DIR := Build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_BUNDLE)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources

SWIFT_SOURCES := $(shell echo *.swift KeyboardShortcuts/*.swift)

FRAMEWORKS := \
	-framework Cocoa \
	-framework Carbon \
	-framework ApplicationServices \
	-framework SwiftUI \
	-framework Combine

SWIFTC := xcrun swiftc
OPTIMIZE := -O
SDK_PATH := $(shell xcrun --show-sdk-path --sdk macosx15 2>/dev/null || xcrun --show-sdk-path --sdk macosx 2>/dev/null || echo "")
SDK_FLAGS := $(if $(SDK_PATH),-sdk $(SDK_PATH),)

SWIFT_FLAGS := \
	-parse-as-library -swift-version 5 \
	$(OPTIMIZE) \
	$(SDK_FLAGS) \
	$(FRAMEWORKS) \
	-module-cache-path /tmp/swift-module-cache \
	-o $(BUILD_DIR)/$(APP_NAME)

.PHONY: all build clean run install uninstall help

all: build

help:
	@echo "QuickKeyJump - 构建工具"
	@echo "  make build / clean / run / install / uninstall"

build: clean $(BUILD_DIR)
	@echo "=== 构建 $(APP_NAME).app ==="
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)
	@echo "编译 Swift 源码..."
	$(SWIFTC) $(SWIFT_SOURCES) $(SWIFT_FLAGS)
	@cp $(BUILD_DIR)/$(APP_NAME) $(MACOS_DIR)/
	@chmod +x $(MACOS_DIR)/$(APP_NAME)
	@cp Info.plist $(CONTENTS_DIR)/
	@cp AppIcon.icns $(RESOURCES_DIR)/
	@echo "APPL????" > $(CONTENTS_DIR)/PkgInfo
	@echo "=== 构建完成: $(APP_BUNDLE) ==="

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

build-binary: $(BUILD_DIR)
	$(SWIFTC) $(SWIFT_SOURCES) $(SWIFT_FLAGS)

clean:
	@rm -rf $(BUILD_DIR)

run: build-binary
	@$(BUILD_DIR)/$(APP_NAME)

install: build
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) /Applications/

uninstall:
	@rm -rf /Applications/$(APP_NAME).app

sign: build
	@codesign --force --deep --sign - $(APP_BUNDLE)
