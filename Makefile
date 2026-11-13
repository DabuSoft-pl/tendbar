DERIVED := build
APP := $(DERIVED)/Build/Products/Debug/Tendbar.app
RELEASE_APP := $(DERIVED)/Build/Products/Release/Tendbar.app
INSTALL_DIR := /Applications

.PHONY: generate build test run install clean

generate:
	xcodegen generate --quiet

build: generate
	xcodebuild -project Tendbar.xcodeproj -scheme Tendbar -configuration Debug -derivedDataPath $(DERIVED) -quiet build

test:
	cd Packages/TendbarKit && swift test

run: build
	open $(APP)

install: generate
	xcodebuild -project Tendbar.xcodeproj -scheme Tendbar -configuration Release -derivedDataPath $(DERIVED) -quiet build
	pkill -x Tendbar || true
	rm -rf $(INSTALL_DIR)/Tendbar.app
	ditto $(RELEASE_APP) $(INSTALL_DIR)/Tendbar.app
	open $(INSTALL_DIR)/Tendbar.app

clean:
	rm -rf $(DERIVED) Tendbar.xcodeproj Packages/TendbarKit/.build
