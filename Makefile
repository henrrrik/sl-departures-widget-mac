# The logic is a SwiftPM package and the bundles are an Xcode project, so the
# two halves have two build systems. `make test` never touches Xcode.

PROJECT  := SLDepartures.xcodeproj
SCHEME   := SLDepartures
CONFIG   := Release
BUILD    := .build/xcode
APP      := $(BUILD)/Build/Products/$(CONFIG)/SL Departures.app
INSTALLED := /Applications/SL Departures.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
CURRENT_VERSION := $(shell sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
DMG      := .build/SL-Departures-$(CURRENT_VERSION).dmg

.PHONY: all gen build test install run stop clean icon dmg release

all: build

## Regenerate the Xcode project from project.yml (the source of truth).
gen:
	xcodegen generate

## Build the app and the embedded widget extension.
build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(BUILD) $(XCODEFLAGS) build

## Redraw the app icon from Design/app-icon-source.jpg. Only needed when the
## artwork changes — the rendered sizes are committed.
icon:
	swift Tools/make-app-icon.swift Design/app-icon-source.jpg \
		App/Assets.xcassets/AppIcon.appiconset

## Exercise the model. No Xcode, no bundle, no UI.
test:
	swift test

## Install into /Applications and register it, so the widget shows up in the
## widget gallery — an app the system has never launched offers no widgets.
install: build stop
	rm -rf "$(INSTALLED)"
	cp -R "$(APP)" "$(INSTALLED)"
	# A copy left at the old install location would stay registered under the
	# same bundle id and race this one for the widget gallery's tile.
	rm -rf "$(HOME)/Applications/SL Departures.app"
	-$(LSREGISTER) -u "$(HOME)/Applications/SL Departures.app"
	$(LSREGISTER) -f "$(INSTALLED)"
	# Xcode registers the build-products copy as it builds. Two registrations
	# of one bundle id leave the widget gallery listing whichever it saw first
	# — which is how a stale build ends up supplying the tile and its icon.
	-$(LSREGISTER) -u "$(APP)"
	open "$(INSTALLED)"

run: build stop
	open "$(APP)"

stop:
	-pkill -x "SL Departures" 2>/dev/null || true

## Package the built app as a drag-to-install disk image. The app is signed
## but not notarized, so the image carries a note on clearing the quarantine.
## Built universal, so it runs on Intel Macs too.
dmg:
	$(MAKE) build XCODEFLAGS="ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO"
	rm -rf .build/dmg "$(DMG)"
	mkdir -p .build/dmg
	cp -R "$(APP)" .build/dmg/
	ln -s /Applications .build/dmg/Applications
	cp Tools/dmg-readme.txt ".build/dmg/Read Me First.txt"
	hdiutil create -volname "SL Departures $(CURRENT_VERSION)" -srcfolder .build/dmg \
		-format UDZO -ov "$(DMG)"
	rm -rf .build/dmg
	@echo "Built $(DMG)"

## Cut a release: `make release VERSION=1.0.4`. Bumps both version numbers,
## commits, tags v$(VERSION), and builds the disk image. Pushing is left to you.
release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=x.y.z"; exit 1; }
	@git diff --quiet HEAD || { echo "working tree is dirty"; exit 1; }
	@! git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null || { echo "v$(VERSION) already exists"; exit 1; }
	sed -i '' 's/^\( *MARKETING_VERSION: \)".*"/\1"$(VERSION)"/' project.yml
	build=$$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' project.yml); \
		sed -i '' "s/^\( *CURRENT_PROJECT_VERSION: \)\".*\"/\1\"$$((build + 1))\"/" project.yml
	git commit -m "Bump version to $(VERSION)" project.yml
	git tag -a "v$(VERSION)" -m "SL Departures $(VERSION)"
	$(MAKE) dmg
	@echo "Tagged v$(VERSION). Push with: git push origin main v$(VERSION)"

clean:
	rm -rf $(BUILD) .build/debug .build/release
	rm -rf $(PROJECT)
