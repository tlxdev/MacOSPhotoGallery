# PhotoViewer - Native macOS Application
# Build with: make

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

CFLAGS = -Wall -Wextra -Werror -std=c17 -O2 -fmodules
OBJCFLAGS = -Wall -Wextra -std=gnu17 -O2 -fmodules -fobjc-arc
LDFLAGS = -framework Cocoa -framework Quartz -framework ImageIO -framework UniformTypeIdentifiers

C_SOURCES = src/core/photo_scanner.c src/core/photo_cache.c
OBJC_SOURCES = src/main.m \
               src/app/AppDelegate.m \
               src/app/MainWindowController.m \
               src/views/PhotoView.m \
               src/views/PhotoGridView.m \
               src/views/MetadataPanel.m \
               src/views/ToolbarView.m \
               src/models/PhotoItem.m \
               src/models/PhotoStore.m

C_OBJECTS = $(C_SOURCES:.c=.o)
OBJC_OBJECTS = $(OBJC_SOURCES:.m=.o)
ALL_OBJECTS = $(C_OBJECTS) $(OBJC_OBJECTS)

.PHONY: all clean run

all: $(APP_BUNDLE)

$(APP_BUNDLE): $(ALL_OBJECTS) Info.plist
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

install: $(APP_BUNDLE)
	cp -r $(APP_BUNDLE) /Applications/

