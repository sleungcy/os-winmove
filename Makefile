BINARY = winmove
SRC    = winmove.swift
PREFIX = /usr/local/bin
PLIST  = $(HOME)/Library/LaunchAgents/com.sam.winmove.plist

build:
	swiftc -O -o $(BINARY) $(SRC)

run: build
	./$(BINARY)

debug: build
	./$(BINARY) -debug

install: build
	sudo cp $(BINARY) $(PREFIX)/$(BINARY)

load: install
	@mkdir -p $(HOME)/Library/LaunchAgents
	@python3 -c "open('$(PLIST)', 'w').write('''<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n    <key>Label</key>\n    <string>com.sam.winmove</string>\n    <key>ProgramArguments</key>\n    <array>\n        <string>$(PREFIX)/$(BINARY)</string>\n        <string>--threshold</string>\n        <string>40</string>\n    </array>\n    <key>RunAtLoad</key>\n    <true/>\n    <key>KeepAlive</key>\n    <true/>\n    <key>StandardOutPath</key>\n    <string>/tmp/winmove.log</string>\n    <key>StandardErrorPath</key>\n    <string>/tmp/winmove.log</string>\n</dict>\n</plist>\n''')"
	launchctl bootstrap gui/$(shell id -u) $(PLIST)
	@echo "winmove loaded as login agent"

unload:
	-launchctl bootout gui/$(shell id -u)/com.sam.winmove
	-rm -f $(PLIST)
	@echo "winmove unloaded"

status:
	launchctl list | grep winmove || echo "not running"

.PHONY: build run debug install load unload status
