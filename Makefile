APP_NAME     = JenaImage
BUNDLE_ID    = com.jenalab.jenaimage
VERSION      = 1.1.0
BUILD_DIR    = .build
SOURCES      = $(shell find Sources -name '*.swift')
FRAMEWORKS   = -framework AppKit -framework UniformTypeIdentifiers -framework AVKit -framework AVFoundation

APP_BUNDLE   = $(BUILD_DIR)/$(APP_NAME).app
BINARY       = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)

.PHONY: build run clean install pkg dmg

build: $(BINARY)

$(BINARY): $(SOURCES)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	swiftc $(FRAMEWORKS) -O $(SOURCES) -o $(BINARY)
	@cp Info.plist $(APP_BUNDLE)/Contents/
	@[ -f Resources/$(APP_NAME).icns ] && cp Resources/$(APP_NAME).icns $(APP_BUNDLE)/Contents/Resources/$(APP_NAME).icns || true

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
