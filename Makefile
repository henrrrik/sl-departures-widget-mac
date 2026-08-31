# The logic is a SwiftPM package and the bundles are an Xcode project, so the
# two halves have two build systems. `make test` never touches Xcode.

PROJECT  := SLDepartures.xcodeproj
SCHEME   := SLDepartures
CONFIG   := Release
BUILD    := .build/xcode
APP      := $(BUILD)/Build/Products/$(CONFIG)/SL Departures.app
INSTALLED := $(HOME)/Applications/SL Departures.app

.PHONY: all gen build test install run stop clean

all: build

## Regenerate the Xcode project from project.yml (the source of truth).
gen:
	xcodegen generate

## Build the app and the embedded widget extension.
build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(BUILD) build

## Redraw the app icon from Design/app-icon-source.jpg. Only needed when the
## artwork changes — the rendered sizes are committed.
icon:
	swift Tools/make-app-icon.swift Design/app-icon-source.jpg \
		App/Assets.xcassets/AppIcon.appiconset

## Exercise the model. No Xcode, no bundle, no UI.
test:
	swift test

## Install into ~/Applications and register it, so the widget shows up in the
## widget gallery — an app the system has never launched offers no widgets.
install: build stop
	rm -rf "$(INSTALLED)"
	mkdir -p "$(HOME)/Applications"
	cp -R "$(APP)" "$(INSTALLED)"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
		-f "$(INSTALLED)"
	open "$(INSTALLED)"

run: build stop
	open "$(APP)"

stop:
	-pkill -x "SL Departures" 2>/dev/null || true

clean:
	rm -rf $(BUILD) .build/debug .build/release
	rm -rf $(PROJECT)
