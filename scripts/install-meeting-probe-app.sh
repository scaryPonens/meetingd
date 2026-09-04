#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build --configuration release --product meeting-probe

APP_DIR="${MEETING_PROBE_APP_DIR:-$HOME/Applications/MeetingProbe.app}"
BIN_LINK="${MEETING_PROBE_BIN_LINK:-$HOME/.local/bin/meeting-probe}"
EXECUTABLE="$ROOT/.build/release/meeting-probe"

mkdir -p "$HOME/Applications" "$(dirname "$BIN_LINK")"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

install -m 755 "$EXECUTABLE" "$APP_DIR/Contents/MacOS/meeting-probe"
install -m 644 "$ROOT/packaging/MeetingProbe-Info.plist" "$APP_DIR/Contents/Info.plist"

chmod +x "$ROOT/scripts/ensure-codesign-identity.sh"
IDENTITY="-"
# Prefer a local codesigning identity when the operator has already created one.
if security find-identity -v -p codesigning 2>/dev/null | grep -F '"meetingd Development"' >/dev/null; then
  IDENTITY="meetingd Development"
fi

if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --sign - --identifier local.meetingd.MeetingProbe \
    "$APP_DIR/Contents/MacOS/meeting-probe"
  codesign --force --sign - --identifier local.meetingd.MeetingProbe \
    "$APP_DIR"
else
  codesign --force --options runtime --sign "$IDENTITY" \
    --identifier local.meetingd.MeetingProbe \
    "$APP_DIR/Contents/MacOS/meeting-probe"
  codesign --force --options runtime --sign "$IDENTITY" \
    --identifier local.meetingd.MeetingProbe \
    "$APP_DIR"
fi

# Clear Gatekeeper quarantine/provenance leftovers from local copies.
xattr -cr "$APP_DIR" 2>/dev/null || true

# Important: do NOT symlink to the Mach-O. Launching through a symlink outside the
# .app makes Bundle.main lose the bundle id, and Accessibility never registers MeetingProbe.
# Also remove any prior symlink first — `cat > symlink` would overwrite the Mach-O target.
PROBE_APP="$APP_DIR"
rm -f "$BIN_LINK"
cat > "$BIN_LINK" <<EOF
#!/bin/bash
# Launch via LaunchServices so TCC attributes Accessibility to MeetingProbe.
# Do not pass /dev/stdout to open(1): Ghostty TTYs fail with LS error -10810.
set -euo pipefail
OUT="\$(mktemp -t meeting-probe-out)"
ERR="\$(mktemp -t meeting-probe-err)"
status=0
open -n -W -a "$PROBE_APP" --stdout "\$OUT" --stderr "\$ERR" --args "\$@" || status=\$?
cat "\$OUT"
cat "\$ERR" >&2
rm -f "\$OUT" "\$ERR"
exit "\$status"
EOF
chmod 755 "$BIN_LINK"

# Register with Launch Services so System Settings can show a stable app name.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" >/dev/null 2>&1 || true

echo "Installed app: $APP_DIR"
echo "CLI wrapper:   $BIN_LINK -> open -W -a $APP_DIR"
echo "Signing:       $IDENTITY"
echo
echo "Grant Accessibility:"
echo "  1. \"$BIN_LINK\" --request-accessibility --once"
echo "  2. System Settings → Privacy & Security → Accessibility"
echo "  3. Click +, select: $APP_DIR"
echo "  4. Enable MeetingProbe, then rerun the probe"
