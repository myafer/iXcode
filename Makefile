APP_NAME := iXcode
BUILD_DIR := build
TEST_BUILD_DIR := build-tests
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
XCODEPROJ := $(APP_NAME).xcodeproj

.PHONY: app project test clean install run

SOURCES := $(wildcard Sources/*.swift) $(wildcard Sources/Core/*.swift)
TEST_SOURCES := $(wildcard Tests/*.swift)

## 默认目标：Xcode 工程构建（产物固定输出到 build/iXcode.app，CI 依赖这个路径）
app: $(APP_BUNDLE)

$(APP_BUNDLE): $(XCODEPROJ) $(SOURCES) Resources/Info.plist Resources/AppIcon.icns
	xcodebuild -project $(XCODEPROJ) -scheme $(APP_NAME) \
		-configuration Release -derivedDataPath $(BUILD_DIR) build
	rm -rf $(APP_BUNDLE)
	cp -R $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app $(APP_BUNDLE)
	codesign --force -s - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

## 单元测试（纯逻辑 bundle，不启动 App；CI 用这个）
test: $(XCODEPROJ) $(SOURCES) $(TEST_SOURCES)
	xcodebuild test -project $(XCODEPROJ) -scheme $(APP_NAME) \
		-destination 'platform=macOS' -derivedDataPath $(TEST_BUILD_DIR)

## 增删源文件 / 改 project.yml 后重新生成 xcodeproj
project:
	xcodegen generate

## 安装到 ~/Applications 并启动
install: app
	pkill -f "$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" 2>/dev/null || true
	rm -rf ~/Applications/$(APP_NAME).app
	cp -R $(APP_BUNDLE) ~/Applications/
	open ~/Applications/$(APP_NAME).app

clean:
	rm -rf $(BUILD_DIR) $(TEST_BUILD_DIR)
