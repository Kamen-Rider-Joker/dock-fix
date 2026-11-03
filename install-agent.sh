#!/bin/sh
# Starts DockUnstick at login via a per-user LaunchAgent, and (re)starts it now.
# Uninstall: ./install-agent.sh --uninstall
set -eu
cd "$(dirname "$0")"
LABEL=local.dockunstick
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
pkill -x DockUnstick 2>/dev/null || true

if [ "${1:-}" = "--uninstall" ]; then
    rm -f "$PLIST"
    echo "removed $PLIST"
    exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$PWD/DockUnstick.app/Contents/MacOS/DockUnstick</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
EOF
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "installed $PLIST"
