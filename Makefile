APP_NAME     = JenaImage
BUNDLE_ID    = com.jenalab.jenaimage
VERSION      = 1.9.1
BUILD_DIR    = .build
SOURCES      = $(shell find Sources -name '*.swift')
FRAMEWORKS   = -framework AppKit -framework UniformTypeIdentifiers -framework AVKit -framework AVFoundation -framework Quartz -framework QuickLookThumbnailing -framework Vision

APP_BUNDLE   = $(BUILD_DIR)/$(APP_NAME).app
BINARY       = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)

.PHONY: build run clean install pkg dmg test

build: $(BINARY)

$(BINARY): $(SOURCES) Info.plist $(wildcard Resources/$(APP_NAME).icns)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	swiftc $(FRAMEWORKS) -O $(SOURCES) -o $(BINARY)
	@cp Info.plist $(APP_BUNDLE)/Contents/
	@[ -f Resources/$(APP_NAME).icns ] && cp Resources/$(APP_NAME).icns $(APP_BUNDLE)/Contents/Resources/$(APP_NAME).icns || true
	@# 번들 전체 ad-hoc 서명. 링커가 붙인 실행 파일 서명만으로는 Info.plist·리소스가 봉인되지 않아
	@# 다른 Mac에서 Gatekeeper가 "손상됨"으로 거부한다(공증과 별개). 서명이 일관되면 "확인되지 않은 개발자" 흐름으로 열린다.
	@codesign --force --deep --sign - $(APP_BUNDLE)

run: build
	@open $(APP_BUNDLE)

clean:
	@rm -rf $(BUILD_DIR)

install: build
	@mkdir -p ~/Applications
	@cp -R $(APP_BUNDLE) ~/Applications/
	@echo "Installed to ~/Applications/$(APP_NAME).app"

pkg: build
	pkgbuild --root $(BUILD_DIR) --identifier $(BUNDLE_ID) --version $(VERSION) $(BUILD_DIR)/$(APP_NAME).pkg

dmg: build
	@rm -rf /tmp/$(APP_NAME)_dmg_staging
	@mkdir -p /tmp/$(APP_NAME)_dmg_staging
	@cp -R $(APP_BUNDLE) /tmp/$(APP_NAME)_dmg_staging/$(APP_NAME).app
	@xattr -cr /tmp/$(APP_NAME)_dmg_staging
	@chflags -R nohidden /tmp/$(APP_NAME)_dmg_staging
	@ln -s /Applications /tmp/$(APP_NAME)_dmg_staging/Applications
	@rm -f $(BUILD_DIR)/$(APP_NAME).dmg
	hdiutil create -volname $(APP_NAME) -srcfolder /tmp/$(APP_NAME)_dmg_staging -ov -format UDZO $(BUILD_DIR)/$(APP_NAME).dmg
	@rm -rf /tmp/$(APP_NAME)_dmg_staging
	@echo "Created $(BUILD_DIR)/$(APP_NAME).dmg"

TEST_SOURCES = Sources/services/ThumbnailScheduler.swift \
               Sources/models/BrowserLayoutMode.swift \
               Sources/browser/MasonryLayout.swift \
               Sources/models/ImageFile.swift \
               Sources/models/ImageFormat.swift \
               Sources/services/ImageAspectRatioReader.swift \
               Sources/models/ImageCategory.swift \
               Sources/services/CategoryStore.swift \
               Sources/services/ThumbnailCache.swift \
               Sources/services/ThumbnailProvider.swift \
               Sources/services/ThumbnailDiskStore.swift \
               $(wildcard Tests/*.swift)

test:
	@mkdir -p $(BUILD_DIR)
	swiftc -framework AppKit -framework ImageIO -framework QuickLookThumbnailing -framework UniformTypeIdentifiers $(TEST_SOURCES) -o $(BUILD_DIR)/tests
	@$(BUILD_DIR)/tests

# UI 연결 검증은 실제 사용자 캐시 대신 메모리 썸네일 공급자를 사용한다.
.PHONY: test-ui
test-ui:
	@mkdir -p $(BUILD_DIR)
	swiftc $(FRAMEWORKS) $(filter-out Sources/app/main.swift Sources/services/ThumbnailProvider+App.swift,$(SOURCES)) Tests/TestSupport.swift $(wildcard Tests/UI/*.swift) -o $(BUILD_DIR)/category-ui-tests
	@$(BUILD_DIR)/category-ui-tests
