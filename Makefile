.PHONY: install uninstall build

BUILD_DIR ?= $(HOME)/.cache/DisplaySwitcher/build

install:
	./install.sh

uninstall:
	./uninstall.sh

build:
	python3 tools/generate_project.py
	xcodebuild -project DisplaySwitcher.xcodeproj -scheme DisplaySwitcher -configuration Release -derivedDataPath $(BUILD_DIR) build