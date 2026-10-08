#!/bin/bash
# Build Mousse and assemble a runnable, locally signed menu-bar .app bundle per architecture.
set -euo pipefail

cd "$(dirname "$0")"

# Respect the active Xcode selected by the user, including an installation on an external disk.
if [ -z "${DEVELOPER_DIR:-}" ]; then
    DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
fi
[ -d "$DEVELOPER_DIR" ] || { echo "Error: no valid Xcode developer directory" >&2; exit 1; }
export DEVELOPER_DIR

# Use the system driver entry point so DEVELOPER_DIR selects the requested Xcode toolchain.
SWIFT="/usr/bin/swift"
[ -x "$SWIFT" ] || { echo "Error: swift driver not found" >&2; exit 1; }

APP_NAME="Mousse"
BUNDLE_ID="com.mousse.app"
VERSION="0.30.0"
MIN_MACOS="14.0"
# "<arch>:<triple>" — one staged bundle and one archive per entry, so Apple silicon and Intel
# users each get a package that matches their hardware.
ARCHES=("arm64:arm64-apple-macosx${MIN_MACOS}" "x86_64:x86_64-apple-macosx${MIN_MACOS}")
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

sign_bundle() {
    # Sign with the stable local identity if present (run tools/setup-signing-cert.sh once).
    # A fixed cert keeps the designated requirement constant across rebuilds, so Accessibility
    # is granted ONCE and survives every rebuild. Fall back to ad-hoc if the cert isn't set up.
    if security find-certificate -c "Mousse Local Signing" \
        "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
        echo "==> signing $1 with stable identity"
        codesign --force --sign "Mousse Local Signing" --timestamp=none "$1" >/dev/null 2>&1
    else
        echo "==> ad-hoc signing $1 (run tools/setup-signing-cert.sh for a stable signature)"
        codesign --force --sign - --timestamp=none "$1" >/dev/null 2>&1
    fi
}

for entry in "${ARCHES[@]}"; do
    ARCH="${entry%%:*}"
    TRIPLE="${entry#*:}"
    OUT="build/${APP_NAME}-${ARCH}.app"

    echo "==> swift build -c release (${ARCH})"
    "$SWIFT" build -c release --sdk "$SDK_PATH" --triple "$TRIPLE"
    BIN_DIR="$("$SWIFT" build -c release --sdk "$SDK_PATH" --triple "$TRIPLE" --show-bin-path)"
    BIN="${BIN_DIR}/${APP_NAME}"

    echo "==> assembling ${OUT}"
    rm -rf "$OUT"
    mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
    cp "$BIN" "$OUT/Contents/MacOS/${APP_NAME}"
    [ -d "${BIN_DIR}/Mousse_Mousse.bundle" ] && cp -R "${BIN_DIR}/Mousse_Mousse.bundle" "$OUT/Contents/Resources/"
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
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
    <key>NSHumanReadableCopyright</key><string>Mousse</string>
</dict>
</plist>
PLIST

    # The binary is replaced after the bundle exists, so sign the finished bundle last.
    sign_bundle "$OUT"
done

echo "==> done:"
for entry in "${ARCHES[@]}"; do
    OUT="build/${APP_NAME}-${entry%%:*}.app"
    echo "    $(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
done
