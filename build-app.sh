#!/bin/bash
# Build Mousse and assemble a runnable, locally signed menu-bar .app bundle.
set -euo pipefail

cd "$(dirname "$0")"

# Respect the active Xcode selected by the user, including an installation on an external disk.
if [ -z "${DEVELOPER_DIR:-}" ]; then
    DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
fi
[ -d "$DEVELOPER_DIR" ] || { echo "Error: no valid Xcode developer directory" >&2; exit 1; }
export DEVELOPER_DIR

# Try to find swift executable
if [ -f "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" ]; then
    SWIFT="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
else
    SWIFT="$(which swift)" || { echo "Error: swift not found in PATH or Xcode"; exit 1; }
fi

APP_NAME="Mousse"
BUNDLE_ID="com.mousse.app"
VERSION="0.16.0"
BUILD_TRIPLE="arm64-apple-macosx26.0"
OUT="build/${APP_NAME}.app"

echo "==> swift build -c release"
"$SWIFT" build -c release --triple "$BUILD_TRIPLE"
BIN="$("$SWIFT" build -c release --triple "$BUILD_TRIPLE" --show-bin-path)/${APP_NAME}"

echo "==> assembling ${OUT}"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/${APP_NAME}"
[ -d "$(dirname "$BIN")/Mousse_Mousse.bundle" ] && cp -R "$(dirname "$BIN")/Mousse_Mousse.bundle" "$OUT/Contents/Resources/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHumanReadableCopyright</key><string>Mousse</string>
</dict>
</plist>
PLIST

# Sign with the stable local identity if present (run tools/setup-signing-cert.sh once).
# A fixed cert keeps the designated requirement constant across rebuilds, so Accessibility
# is granted ONCE and survives every rebuild. Fall back to ad-hoc if the cert isn't set up.
if security find-certificate -c "Mousse Local Signing" \
    "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
    echo "==> signing with stable identity"
    codesign --force --sign "Mousse Local Signing" --timestamp=none "$OUT" >/dev/null 2>&1
else
    echo "==> ad-hoc signing (run tools/setup-signing-cert.sh for a stable signature)"
    codesign --force --sign - --timestamp=none "$OUT" >/dev/null 2>&1
fi

echo "==> done: $(cd "$(dirname "$OUT")" && pwd)/${APP_NAME}.app"
