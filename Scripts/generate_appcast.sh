#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/Build"
ZIP_PATH="${ZIP_PATH:-$BUILD_DIR/Mac Switch.zip}"
RELEASE_TAG="${RELEASE_TAG:?Set RELEASE_TAG to the GitHub release tag for this update.}"
APPCAST_DIR="${APPCAST_DIR:-$BUILD_DIR/Appcast}"
APPCAST_PATH="${APPCAST_PATH:-$APPCAST_DIR/appcast.xml}"
UPDATE_ASSET_NAME="${UPDATE_ASSET_NAME:-Mac.Switch.zip}"
APPCAST_EXISTING_URL="${APPCAST_EXISTING_URL:-}"
APPCAST_CHANNEL="${APPCAST_CHANNEL:-}"
APPCAST_MAXIMUM_VERSIONS="${APPCAST_MAXIMUM_VERSIONS:-0}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-com.maxyu.macswitch.sparkle}"
SPARKLE_BIN_DIR="${SPARKLE_BIN_DIR:-$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin}"
SPARKLE_VIA_LAUNCHCTL="${SPARKLE_VIA_LAUNCHCTL:-0}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-}"

run_sparkle_tool() {
    if [[ "$SPARKLE_VIA_LAUNCHCTL" == "1" ]]; then
        launchctl asuser "$(id -u)" "$@"
    else
        "$@"
    fi
}

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
EXISTING_APPCAST_PATH="$APPCAST_DIR/existing-appcast.xml"
GENERATED_APPCAST_DIR="$APPCAST_DIR/generated"
GENERATED_APPCAST_PATH="$GENERATED_APPCAST_DIR/appcast.xml"
if [[ -n "$APPCAST_EXISTING_URL" ]]; then
    if curl -fsSL \
        -H 'Cache-Control: no-cache' \
        -H 'Pragma: no-cache' \
        "$APPCAST_EXISTING_URL" \
        -o "$EXISTING_APPCAST_PATH"; then
        echo "Seeded appcast from: $APPCAST_EXISTING_URL"
    else
        rm -f "$EXISTING_APPCAST_PATH"
        echo "No existing appcast was available at: $APPCAST_EXISTING_URL"
    fi
fi
mkdir -p "$GENERATED_APPCAST_DIR"
cp "$ZIP_PATH" "$GENERATED_APPCAST_DIR/$UPDATE_ASSET_NAME"

GENERATE_ARGS=(
    --download-url-prefix "$DOWNLOAD_URL_PREFIX"
    --maximum-versions "$APPCAST_MAXIMUM_VERSIONS"
    -o "$GENERATED_APPCAST_PATH"
)

if [[ -n "$APPCAST_CHANNEL" ]]; then
    GENERATE_ARGS+=(--channel "$APPCAST_CHANNEL")
fi

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    echo "SPARKLE_PRIVATE_KEY environment signing is no longer supported for release appcasts." >&2
    echo "Store the Sparkle signing key in the release Mac Keychain and use --account $SPARKLE_ACCOUNT." >&2
    exit 1
fi

run_sparkle_tool "$SPARKLE_BIN_DIR/generate_appcast" \
    --account "$SPARKLE_ACCOUNT" \
    "${GENERATE_ARGS[@]}" \
    "$GENERATED_APPCAST_DIR"

expected_enclosure_url="${DOWNLOAD_URL_PREFIX}${UPDATE_ASSET_NAME}"
if [[ -s "$EXISTING_APPCAST_PATH" ]]; then
    "$ROOT_DIR/Scripts/appcast_item_tool.py" merge \
        --existing "$EXISTING_APPCAST_PATH" \
        --incoming "$GENERATED_APPCAST_PATH" \
        --output "$APPCAST_PATH" \
        --expected-url "$expected_enclosure_url" \
        --expected-channel "$APPCAST_CHANNEL"
else
    cp "$GENERATED_APPCAST_PATH" "$APPCAST_PATH"
    "$ROOT_DIR/Scripts/appcast_item_tool.py" verify \
        --appcast "$APPCAST_PATH" \
        --expected-url "$expected_enclosure_url" \
        --expected-channel "$APPCAST_CHANNEL"
fi

test -s "$APPCAST_PATH"
echo "Generated appcast: $APPCAST_PATH"
