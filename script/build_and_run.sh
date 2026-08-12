#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Mousse"
BUILD_TRIPLE="arm64-apple-macosx26.0"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
MODE="${1:-run}"

case "$MODE" in
    run|--debug|--logs|--telemetry|--verify) ;;
    *)
        echo "Usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac

if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
elif [ -d "/Applications/Xcode-beta.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

if [ -n "${DEVELOPER_DIR:-}" ] && [ -x "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" ]; then
    SWIFT="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
else
    SWIFT="$(command -v swift)" || { echo "Error: swift not found" >&2; exit 1; }
fi

stop_existing_app() {
    local pid command
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
        case "$command" in
            */Mousse.app/Contents/MacOS/Mousse*)
                echo "==> stopping existing Mousse process $pid"
                kill "$pid"
                ;;
        esac
    done < <(pgrep -x "$APP_NAME" 2>/dev/null || true)

    for _ in {1..20}; do
        pgrep -x "$APP_NAME" >/dev/null 2>&1 || return 0
        sleep 0.1
    done
}

stage_app() {
    local bin_dir source_binary resource_bundle plist

    echo "==> building Debug configuration"
    "$SWIFT" build -c debug --triple "$BUILD_TRIPLE"
    bin_dir="$("$SWIFT" build -c debug --triple "$BUILD_TRIPLE" --show-bin-path)"
    source_binary="$bin_dir/$APP_NAME"
    resource_bundle="$bin_dir/Mousse_Mousse.bundle"

    [ -x "$source_binary" ] || { echo "Error: missing executable: $source_binary" >&2; exit 1; }
    [ -d "$resource_bundle" ] || { echo "Error: missing resource bundle: $resource_bundle" >&2; exit 1; }

    echo "==> staging $APP_BUNDLE"
    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
    cp "$source_binary" "$APP_BINARY"
    cp -R "$resource_bundle" "$APP_BUNDLE/Contents/Resources/"
    if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
        cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    fi

    plist="$APP_BUNDLE/Contents/Info.plist"
    plutil -create xml1 "$plist"
    plutil -insert CFBundleExecutable -string "$APP_NAME" "$plist"
    plutil -insert CFBundleIdentifier -string "com.mousse.app" "$plist"
    plutil -insert CFBundleName -string "$APP_NAME" "$plist"
    plutil -insert CFBundleDisplayName -string "$APP_NAME" "$plist"
    plutil -insert CFBundlePackageType -string "APPL" "$plist"
    plutil -insert CFBundleShortVersionString -string "0.9.2" "$plist"
    plutil -insert CFBundleVersion -string "0.9.2" "$plist"
    plutil -insert CFBundleIconFile -string "AppIcon" "$plist"
    plutil -insert LSMinimumSystemVersion -string "26.0" "$plist"
    plutil -insert LSUIElement -bool true "$plist"
    plutil -insert NSPrincipalClass -string "NSApplication" "$plist"

    if security find-certificate -c "Mousse Local Signing" \
        "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
        echo "==> signing with stable local identity"
        codesign --force --sign "Mousse Local Signing" --timestamp=none "$APP_BUNDLE"
    else
        echo "==> signing ad-hoc"
        codesign --force --sign - --timestamp=none "$APP_BUNDLE"
    fi
}

launch_app() {
    stop_existing_app
    echo "==> launching $APP_BUNDLE"
    /usr/bin/open -n "$APP_BUNDLE"
}

wait_for_pid() {
    local pid=""
    for _ in {1..50}; do
        pid="$(pgrep -x "$APP_NAME" | head -n 1 || true)"
        if [ -n "$pid" ]; then
            echo "$pid"
            return 0
        fi
        sleep 0.1
    done
    return 1
}

print_build_identity() {
    local pid="$1" uuid hash command
    uuid="$(dwarfdump --uuid "$APP_BINARY" | awk '{print $2; exit}')"
    hash="$(shasum -a 256 "$APP_BINARY" | awk '{print $1}')"
    command="$(ps -p "$pid" -o command=)"
    echo "==> pid=$pid"
    echo "==> executable=$command"
    echo "==> uuid=$uuid"
    echo "==> sha256=$hash"
}

cd "$ROOT_DIR"
stage_app
launch_app
pid="$(wait_for_pid)" || { echo "Error: Mousse did not start" >&2; exit 1; }
print_build_identity "$pid"

case "$MODE" in
    --verify)
        echo "==> verified running process $pid"
        ;;
    --debug)
        echo "==> attaching LLDB to process $pid"
        exec lldb -p "$pid"
        ;;
    --logs|--telemetry)
        exec /usr/bin/log stream --level debug --style compact --predicate "processIdentifier == $pid"
        ;;
esac
