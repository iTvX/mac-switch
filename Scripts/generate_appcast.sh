#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/Build"
ZIP_PATH="${ZIP_PATH:-$BUILD_DIR/Mac Switch.zip}"
RELEASE_TAG="${RELEASE_TAG:?Set RELEASE_TAG to the GitHub release tag for this update.}"
APPCAST_DIR="${APPCAST_DIR:-$BUILD_DIR/Appcast}"
APPCAST_PATH="${APPCAST_PATH:-$APPCAST_DIR/appcast.xml}"
UPDATE_ASSET_NAME="${UPDATE_ASSET_NAME:-Mac.Switch.zip}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-com.maxyu.macswitch.sparkle}"
SPARKLE_BIN_DIR="${SPARKLE_BIN_DIR:-$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-}"

if [[ ! -f "$ZIP_PATH" ]]; then
    echo "Release archive is missing at $ZIP_PATH." >&2
    exit 1
fi

if [[ ! -x "$SPARKLE_BIN_DIR/generate_appcast" ]]; then
    echo "Sparkle generate_appcast tool is missing. Run: swift package resolve" >&2
    exit 1
fi

if [[ -z "$DOWNLOAD_URL_PREFIX" ]]; then
    if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
        echo "Set DOWNLOAD_URL_PREFIX or run in GitHub Actions with GITHUB_REPOSITORY available." >&2
        exit 1
    fi
    DOWNLOAD_URL_PREFIX="https://github.com/$GITHUB_REPOSITORY/releases/download/$RELEASE_TAG/"
fi

rm -rf "$APPCAST_DIR"
mkdir -p "$APPCAST_DIR"
cp "$ZIP_PATH" "$APPCAST_DIR/$UPDATE_ASSET_NAME"

GENERATE_ARGS=(
    --download-url-prefix "$DOWNLOAD_URL_PREFIX"
    --maximum-versions 1
    -o "$APPCAST_PATH"
)

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN_DIR/generate_appcast" \
        --ed-key-file - \
        "${GENERATE_ARGS[@]}" \
        "$APPCAST_DIR"
else
    "$SPARKLE_BIN_DIR/generate_appcast" \
        --account "$SPARKLE_ACCOUNT" \
        "${GENERATE_ARGS[@]}" \
        "$APPCAST_DIR"
fi

test -s "$APPCAST_PATH"
echo "Generated appcast: $APPCAST_PATH"
