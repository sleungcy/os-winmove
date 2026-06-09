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
	cp $(BINARY) $(PREFIX)/$(BINARY)

load: install
	@mkdir -p $(HOME)/Library/LaunchAgents
	@cat > $(PLIST) <<'EOF'
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
	    <key>Label</key>
	    <string>com.sam.winmove</string>
	    <key>ProgramArguments</key>
	    <array>
	        <string>$(PREFIX)/$(BINARY)</string>
	    </array>
	    <key>RunAtLoad</key>
	    <true/>
	    <key>KeepAlive</key>
	    <true/>
	    <key>StandardOutPath</key>
	    <string>/tmp/winmove.log</string>
	    <key>StandardErrorPath</key>
	    <string>/tmp/winmove.log</string>
	</dict>
	</plist>
	EOF
	launchctl load $(PLIST)
	@echo "winmove loaded as login agent"

unload:
	-launchctl unload $(PLIST)
	-rm -f $(PLIST)
	@echo "winmove unloaded"

status:
	launchctl list | grep winmove || echo "not running"

.PHONY: build run debug install load unload status
