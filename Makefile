APP_NAME := SymClick
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_BUNDLE)/Contents
BINARY := $(CONTENTS_DIR)/MacOS/$(APP_NAME)
PLIST := $(CONTENTS_DIR)/Info.plist
DIST_DIR := $(BUILD_DIR)/dist
ARCHIVE := $(DIST_DIR)/$(APP_NAME)-v$(VERSION)-macOS-universal.zip
CXX := xcrun clang++
ARCHS ?= -arch arm64 -arch x86_64
SIGN_IDENTITY ?= -

CXXFLAGS := -std=c++20 -O3 -flto -fobjc-arc -Wall -Wextra -Wpedantic \
	-Wno-deprecated-declarations -mmacosx-version-min=12.0 $(ARCHS)
FRAMEWORKS := -framework AppKit -framework ApplicationServices -framework Carbon
CODESIGN_FLAGS := --force --sign "$(SIGN_IDENTITY)"
ifneq ($(SIGN_IDENTITY),-)
CODESIGN_FLAGS += --timestamp --options runtime
endif

.PHONY: all run test diagnostics smoke agent-check verify package install clean

all: $(BINARY)

$(BINARY): src/main.mm Info.plist
	mkdir -p $(CONTENTS_DIR)/MacOS $(CONTENTS_DIR)/Resources
	cp Info.plist $(PLIST)
	$(CXX) $(CXXFLAGS) src/main.mm -o $(BINARY) $(FRAMEWORKS)
	codesign $(CODESIGN_FLAGS) $(APP_BUNDLE)

run: all
	open $(APP_BUNDLE)

test: all
	$(BINARY) --self-test

diagnostics: all
	$(BINARY) --diagnose

smoke: all
	$(BINARY) --smoke-test

agent-check: all
	python3 tests/agent_contract.py $(BINARY)

verify: test agent-check
	plutil -lint $(PLIST)
	lipo -verify_arch arm64 $(BINARY)
	lipo -verify_arch x86_64 $(BINARY)
	codesign --verify --deep --strict --verbose=2 $(APP_BUNDLE)

package: all
	mkdir -p $(DIST_DIR)
	codesign $(CODESIGN_FLAGS) $(APP_BUNDLE)
	rm -f $(ARCHIVE) $(ARCHIVE).sha256
	ditto -c -k --sequesterRsrc --keepParent $(APP_BUNDLE) $(ARCHIVE)
	cd $(DIST_DIR) && shasum -a 256 $(notdir $(ARCHIVE)) > $(notdir $(ARCHIVE)).sha256
	unzip -tq $(ARCHIVE)

install: all
	rm -rf /Applications/$(APP_NAME).app
	ditto $(APP_BUNDLE) /Applications/$(APP_NAME).app

clean:
	rm -rf $(BUILD_DIR)
