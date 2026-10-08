#!/bin/bash
# Package Mousse releases: build one bundle per architecture, zip each, and compute sha256.
# Publishing to GitHub is opt-in (--publish) so this never makes an outward-facing change by
# accident. Usage:
#   tools/package-release.sh            # build + zip + sha256 per architecture (local only)
#   tools/package-release.sh --publish  # also create the GitHub release and upload every zip
set -euo pipefail

cd "$(dirname "$0")/.."

PUBLISH=0
[ "${1:-}" = "--publish" ] && PUBLISH=1

APP_NAME="Mousse"
# Single source of truth for the version: read it straight out of build-app.sh.
VERSION="$(awk -F'"' '/^VERSION=/ {print $2; exit}' build-app.sh)"
[ -n "$VERSION" ] || { echo "error: could not read VERSION from build-app.sh" >&2; exit 1; }
TAG="v${VERSION}"

echo "==> building ${APP_NAME} ${VERSION}"
./build-app.sh

# One archive per staged bundle: Mousse-<version>-arm64.zip, Mousse-<version>-x86_64.zip.
# Inside every archive the bundle is named Mousse.app, so unzipping needs no renaming step.
ZIPS=()
for APP in "build/${APP_NAME}"-*.app; do
    [ -d "$APP" ] || continue
    ARCH="$(basename "$APP" | sed "s/^${APP_NAME}-//; s/\.app$//")"
    ZIP="build/${APP_NAME}-${VERSION}-${ARCH}.zip"
    STAGE="build/.stage-${ARCH}"
    echo "==> zipping ${APP} -> ${ZIP}"
    rm -f "$ZIP"
    rm -rf "$STAGE"
    mkdir -p "$STAGE"
    cp -R "$APP" "${STAGE}/${APP_NAME}.app"
    # Keep the bundle structure and embedded signature files, but omit external-disk metadata that
    # otherwise appears as `._*` AppleDouble entries in the public archive.
    ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "${STAGE}/${APP_NAME}.app" "$ZIP"
    rm -rf "$STAGE"
    SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
    echo "==> ${ARCH} sha256: ${SHA}"
    ZIPS+=("$ZIP")
done

[ "${#ZIPS[@]}" -gt 0 ] || { echo "error: build-app.sh produced no bundles" >&2; exit 1; }

( cd build && shasum -a 256 "${ZIPS[@]#build/}" > SHA256SUMS )
echo "==> wrote build/SHA256SUMS"

if [ "$PUBLISH" -eq 1 ]; then
    command -v gh >/dev/null || { echo "error: gh CLI not found" >&2; exit 1; }
    echo "==> creating GitHub release ${TAG} and uploading ${#ZIPS[@]} archive(s)"
    gh release create "$TAG" "${ZIPS[@]}" --title "$TAG" --generate-notes 2>/dev/null \
        || gh release upload "$TAG" "${ZIPS[@]}" --clobber
    echo "==> published: $(gh release view "$TAG" --json url -q .url)"
else
    echo ""
    echo "==> done (local). Publish with: tools/package-release.sh --publish"
fi
