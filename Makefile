# MDViewer — build, test and package.
#   make            build Debug
#   make test       run the unit tests
#   make release    Release build → dist/MDViewer.app + dist/MDViewer-<version>.zip
#   make install    copy the Release build to /Applications
#   make clean

PROJECT   := mdview.xcodeproj
SCHEME    := mdview
DERIVED   := build
DIST      := dist
VERSION   := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' mdview/Info.plist 2>/dev/null || echo 0.0)
APP       := $(DIST)/MDViewer.app
ZIP       := $(DIST)/MDViewer-$(VERSION).zip
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' -derivedDataPath $(DERIVED)

.PHONY: all project build test release install clean

all: build

# Regenerate the Xcode project from project.yml (needs `brew install xcodegen`).
project:
	xcodegen generate

$(PROJECT):
	xcodegen generate

build: $(PROJECT)
	$(XCODEBUILD) -configuration Debug build | grep -E 'error|warning: .*mdview|BUILD' || true

test: $(PROJECT)
	$(XCODEBUILD) -configuration Debug test 2>&1 | grep -E 'error: |Executed [0-9]+ tests|TEST' | tail -3

release: $(PROJECT)
	rm -rf "$(APP)" "$(ZIP)"
	mkdir -p $(DIST)
	$(XCODEBUILD) -configuration Release build | grep -E 'error|BUILD'
	cp -R "$(DERIVED)/Build/Products/Release/MDViewer.app" "$(APP)"
	codesign --verify --deep --strict "$(APP)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP)" "$(ZIP)"
	@echo "→ $(APP)"
	@echo "→ $(ZIP) ($$(du -h "$(ZIP)" | cut -f1))"

install: release
	rm -rf /Applications/MDViewer.app
	cp -R "$(APP)" /Applications/MDViewer.app
	xattr -dr com.apple.quarantine /Applications/MDViewer.app 2>/dev/null || true
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/MDViewer.app
	@echo "Installed /Applications/MDViewer.app (Quick Look extension registered)"

clean:
	rm -rf $(DERIVED) $(DIST)
