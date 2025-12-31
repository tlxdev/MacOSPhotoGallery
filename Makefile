# PhotoViewer - Native macOS Application (Swift + C)
# Build with: make
# Sign with: make sign IDENTITY="Developer ID Application: Your Name"
# Notarize: make notarize

APP_NAME = PhotoViewer
BUNDLE_ID = com.photoviewer.app
VERSION = 1.0.0

BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources
TEST_BUILD_DIR = $(BUILD_DIR)/tests

# Compilers
CC = clang
SWIFTC = swiftc

# C flags
CFLAGS = -Wall -Wextra -Werror -std=c17 -O2 -mmacosx-version-min=14.0

# Swift flags
SWIFT_FLAGS = -O -whole-module-optimization \
              -import-objc-header src/swift/PhotoViewer-Bridging-Header.h \
              -target arm64-apple-macos14.0 \
              -sdk $(shell xcrun --show-sdk-path)

# Frameworks
FRAMEWORKS = -framework Cocoa -framework Quartz -framework ImageIO \
             -framework UniformTypeIdentifiers -framework CoreServices \
             -framework SwiftUI

# C source files
C_SOURCES = src/core/photo_scanner.c

# Swift source files
SWIFT_SOURCES = src/swift/PhotoViewerApp.swift \
                src/swift/Core/Logger.swift \
                src/swift/Core/LRUCache.swift \
                src/swift/Core/DateFormatters.swift \
                src/swift/Core/ImageCache.swift \
                src/swift/Models/PhotoItem.swift \
                src/swift/Models/PhotoStore.swift \
                src/swift/Views/ContentView.swift \
                src/swift/Views/WelcomeView.swift \
                src/swift/Views/PhotoDisplayView.swift \
                src/swift/Views/PhotoGridView.swift \
                src/swift/Views/MetadataPanel.swift

# Test source files
TEST_SOURCES = tests/LRUCacheTests.swift \
               tests/DateFormattersTests.swift \
               tests/PhotoItemTests.swift \
               tests/TestRunner.swift

C_OBJECTS = $(C_SOURCES:.c=.o)

# Code signing identity
IDENTITY ?= -
ENTITLEMENTS = PhotoViewer.entitlements

.PHONY: all clean run sign notarize install debug release test

all: $(APP_BUNDLE)

# Debug build
debug: CFLAGS += -g -O0 -DDEBUG
debug: SWIFT_FLAGS = -g -Onone -import-objc-header src/swift/PhotoViewer-Bridging-Header.h \
                     -target arm64-apple-macos14.0 -sdk $(shell xcrun --show-sdk-path)
debug: $(APP_BUNDLE)

# Release build
release: CFLAGS += -O3 -DNDEBUG
release: $(APP_BUNDLE)

# Build app bundle
$(APP_BUNDLE): $(C_OBJECTS) $(SWIFT_SOURCES) Info.plist $(ENTITLEMENTS)
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES_DIR)
	@echo "Compiling Swift sources..."
	$(SWIFTC) $(SWIFT_FLAGS) $(C_OBJECTS) $(SWIFT_SOURCES) \
		$(FRAMEWORKS) \
		-o $(MACOS_DIR)/$(APP_NAME)
	@cp Info.plist $(CONTENTS_DIR)/
	@cp -r resources/* $(RESOURCES_DIR)/ 2>/dev/null || true
	@echo "Built $(APP_BUNDLE)"

# Compile C sources
%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf $(BUILD_DIR)
	find src -name "*.o" -delete

run: $(APP_BUNDLE)
	open $(APP_BUNDLE)

# Run tests
test: $(C_OBJECTS)
	@mkdir -p $(TEST_BUILD_DIR)
	@echo "Building tests..."
	$(SWIFTC) -g -Onone \
		-import-objc-header src/swift/PhotoViewer-Bridging-Header.h \
		-target arm64-apple-macos14.0 \
		-sdk $(shell xcrun --show-sdk-path) \
		$(C_OBJECTS) \
		src/swift/Core/Logger.swift \
		src/swift/Core/LRUCache.swift \
		src/swift/Core/DateFormatters.swift \
		src/swift/Core/ImageCache.swift \
		src/swift/Models/PhotoItem.swift \
		$(TEST_SOURCES) \
		$(FRAMEWORKS) \
		-o $(TEST_BUILD_DIR)/TestRunner
	@echo "Running tests..."
	@$(TEST_BUILD_DIR)/TestRunner

# Code signing with hardened runtime
sign: $(APP_BUNDLE)
	@echo "Signing $(APP_BUNDLE) with identity: $(IDENTITY)"
	codesign --force --deep --sign "$(IDENTITY)" \
		--entitlements $(ENTITLEMENTS) \
		--options runtime \
		--timestamp \
		$(APP_BUNDLE)
	@echo "Verifying signature..."
	codesign --verify --verbose=2 $(APP_BUNDLE)

# Ad-hoc signing for local testing
sign-adhoc: $(APP_BUNDLE)
	@echo "Ad-hoc signing $(APP_BUNDLE)..."
	codesign --force --deep --sign - \
		--entitlements $(ENTITLEMENTS) \
		--options runtime \
		$(APP_BUNDLE)
	@echo "Signed for local testing only"

# Create DMG for distribution
dmg: sign
	@echo "Creating DMG..."
	@rm -f $(BUILD_DIR)/$(APP_NAME).dmg
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder $(APP_BUNDLE) \
		-ov -format UDZO \
		$(BUILD_DIR)/$(APP_NAME).dmg
	codesign --sign "$(IDENTITY)" $(BUILD_DIR)/$(APP_NAME).dmg
	@echo "Created $(BUILD_DIR)/$(APP_NAME).dmg"

# Submit for notarization
notarize: dmg
	@echo "Submitting for notarization..."
	xcrun notarytool submit $(BUILD_DIR)/$(APP_NAME).dmg \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(TEAM_ID)" \
		--password "$(APP_PASSWORD)" \
		--wait
	@echo "Stapling notarization ticket..."
	xcrun stapler staple $(BUILD_DIR)/$(APP_NAME).dmg
	@echo "Notarization complete!"

# Staple after notarization
staple:
	xcrun stapler staple $(BUILD_DIR)/$(APP_NAME).dmg
	xcrun stapler staple $(APP_BUNDLE)

install: $(APP_BUNDLE)
	cp -r $(APP_BUNDLE) /Applications/

# Verify entitlements and signature
verify:
	@echo "=== Code Signature ==="
	codesign -dv --verbose=4 $(APP_BUNDLE)
	@echo ""
	@echo "=== Entitlements ==="
	codesign -d --entitlements :- $(APP_BUNDLE)
	@echo ""
	@echo "=== Gatekeeper Check ==="
	spctl -a -vv $(APP_BUNDLE)
