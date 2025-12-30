# PhotoViewer - Native macOS Application
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

CC = clang
OBJC = clang

# Compiler flags
CFLAGS = -Wall -Wextra -Werror -std=c17 -O2 -fmodules
OBJCFLAGS = -Wall -Wextra -std=gnu17 -O2 -fmodules -fobjc-arc
LDFLAGS = -framework Cocoa -framework Quartz -framework ImageIO -framework UniformTypeIdentifiers -framework CoreServices

# Source files
C_SOURCES = src/core/photo_scanner.c
OBJC_SOURCES = src/main.m \
               src/app/AppDelegate.m \
               src/app/MainWindowController.m \
               src/app/RecentsManager.m \
               src/views/PhotoView.m \
               src/views/PhotoGridView.m \
               src/views/ThumbnailCache.m \
               src/views/MetadataPanel.m \
               src/views/ToolbarView.m \
               src/models/PhotoItem.m \
               src/models/PhotoStore.m \
               src/utils/Theme.m \
               src/utils/DateFormatters.m

C_OBJECTS = $(C_SOURCES:.c=.o)
OBJC_OBJECTS = $(OBJC_SOURCES:.m=.o)
ALL_OBJECTS = $(C_OBJECTS) $(OBJC_OBJECTS)

# Code signing identity (set via environment or command line)
# Example: make sign IDENTITY="Developer ID Application: Your Name (TEAMID)"
IDENTITY ?= -
ENTITLEMENTS = PhotoViewer.entitlements

.PHONY: all clean run sign notarize install debug release

all: $(APP_BUNDLE)

# Debug build with symbols
debug: CFLAGS += -g -O0 -DDEBUG
debug: OBJCFLAGS += -g -O0 -DDEBUG
debug: $(APP_BUNDLE)

# Release build with optimizations
release: CFLAGS += -O3 -DNDEBUG
release: OBJCFLAGS += -O3 -DNDEBUG
release: $(APP_BUNDLE)

$(APP_BUNDLE): $(ALL_OBJECTS) Info.plist $(ENTITLEMENTS)
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES_DIR)
	$(CC) $(ALL_OBJECTS) $(LDFLAGS) -o $(MACOS_DIR)/$(APP_NAME)
	@cp Info.plist $(CONTENTS_DIR)/
	@cp -r resources/* $(RESOURCES_DIR)/ 2>/dev/null || true
	@echo "Built $(APP_BUNDLE)"

%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.m
	@mkdir -p $(dir $@)
	$(OBJC) $(OBJCFLAGS) -c $< -o $@

clean:
	rm -rf $(BUILD_DIR)
	find src -name "*.o" -delete

run: $(APP_BUNDLE)
	open $(APP_BUNDLE)

# Code signing with hardened runtime (required for notarization)
sign: $(APP_BUNDLE)
	@echo "Signing $(APP_BUNDLE) with identity: $(IDENTITY)"
	codesign --force --deep --sign "$(IDENTITY)" \
		--entitlements $(ENTITLEMENTS) \
		--options runtime \
		--timestamp \
		$(APP_BUNDLE)
	@echo "Verifying signature..."
	codesign --verify --verbose=2 $(APP_BUNDLE)
	@echo "Checking hardened runtime..."
	codesign -d --entitlements :- $(APP_BUNDLE)

# Ad-hoc signing for local testing (no notarization)
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

# Submit for notarization (requires Apple Developer account)
# Set APPLE_ID, TEAM_ID, and APP_PASSWORD environment variables
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

# Staple after notarization (if done separately)
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
