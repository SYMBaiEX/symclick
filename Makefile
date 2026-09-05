APP_NAME := SymClick
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_BUNDLE)/Contents
BINARY := $(CONTENTS_DIR)/MacOS/$(APP_NAME)
PLIST := $(CONTENTS_DIR)/Info.plist
CXX := xcrun clang++
ARCHS ?= -arch arm64 -arch x86_64

CXXFLAGS := -std=c++20 -O3 -flto -fobjc-arc -Wall -Wextra -Wpedantic \
	-Wno-deprecated-declarations -mmacosx-version-min=12.0 $(ARCHS)
FRAMEWORKS := -framework AppKit -framework ApplicationServices -framework Carbon

.PHONY: all run test install clean

all: $(BINARY)

$(BINARY): src/main.mm Info.plist
	mkdir -p $(CONTENTS_DIR)/MacOS $(CONTENTS_DIR)/Resources
	cp Info.plist $(PLIST)
	$(CXX) $(CXXFLAGS) src/main.mm -o $(BINARY) $(FRAMEWORKS)
	codesign --force --sign - $(APP_BUNDLE)

run: all
	open $(APP_BUNDLE)

test: all
	$(BINARY) --self-test

install: all
	rm -rf /Applications/$(APP_NAME).app
	ditto $(APP_BUNDLE) /Applications/$(APP_NAME).app

clean:
	rm -rf $(BUILD_DIR)
