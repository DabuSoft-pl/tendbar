DERIVED := build
APP := $(DERIVED)/Build/Products/Debug/Tendbar.app

.PHONY: generate build test run clean

generate:
	xcodegen generate --quiet

build: generate
	xcodebuild -project Tendbar.xcodeproj -scheme Tendbar -configuration Debug -derivedDataPath $(DERIVED) -quiet build

test:
	cd Packages/TendbarKit && swift test

run: build
	open $(APP)

clean:
	rm -rf $(DERIVED) Tendbar.xcodeproj Packages/TendbarKit/.build
