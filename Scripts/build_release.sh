#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Mac Switch"
EXECUTABLE_NAME="MacSwitch"
BUILD_DIR="$ROOT_DIR/Build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"
IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DEFAULT_NOTARY_PROFILE="${DEFAULT_NOTARY_PROFILE:-mac-switch-notary}"
KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-}"
KEYCHAIN_DB="${KEYCHAIN_DB:-$HOME/Library/Keychains/login.keychain-db}"
NOTARY_KEYCHAIN="${NOTARY_KEYCHAIN:-}"
SU_FEED_URL="${SU_FEED_URL:-}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
MAC_SWITCH_FEEDBACK_URL="${MAC_SWITCH_FEEDBACK_URL:-}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-com.maxyu.macswitch.sparkle}"
SPARKLE_BIN_DIR="${SPARKLE_BIN_DIR:-$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin}"
SPARKLE_VIA_LAUNCHCTL="${SPARKLE_VIA_LAUNCHCTL:-0}"
CODESIGN_VIA_LAUNCHCTL="${CODESIGN_VIA_LAUNCHCTL:-0}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"
if [[ "$SKIP_NOTARIZATION" == "1" ]]; then
    REQUIRE_NOTARIZATION=0
else
    REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-1}"
fi
RUN_UI_SMOKE="${RUN_UI_SMOKE:-0}"
ARCHS="${ARCHS:-arm64 x86_64}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"
NOTARY_ARGS=()
NOTARY_AUTH_LABEL=""
NOTARY_VIA_LAUNCHCTL="${NOTARY_VIA_LAUNCHCTL:-0}"

run_notarytool() {
    if [[ "$NOTARY_VIA_LAUNCHCTL" == "1" ]]; then
        launchctl asuser "$(id -u)" xcrun notarytool "$@"
    else
        xcrun notarytool "$@"
    fi
}

run_sparkle_tool() {
    if [[ "$SPARKLE_VIA_LAUNCHCTL" == "1" ]]; then
        launchctl asuser "$(id -u)" "$@"
    else
        "$@"
    fi
}

run_codesign() {
    if [[ "$CODESIGN_VIA_LAUNCHCTL" == "1" ]]; then
        launchctl asuser "$(id -u)" codesign "$@"
    else
        codesign "$@"
    fi
}

notary_profile_setup_hint() {
    local profile="$1"
    if [[ -n "$NOTARY_KEYCHAIN" ]]; then
        echo "xcrun notarytool store-credentials $profile --keychain \"$NOTARY_KEYCHAIN\""
    else
        echo "xcrun notarytool store-credentials $profile"
    fi
}

notary_profile_is_available() {
    local profile="$1"
    if [[ -n "$NOTARY_KEYCHAIN" ]]; then
        run_notarytool history --keychain-profile "$profile" --keychain "$NOTARY_KEYCHAIN" >/dev/null 2>&1
    else
        run_notarytool history --keychain-profile "$profile" >/dev/null 2>&1
    fi
}

cd "$ROOT_DIR"

if [[ ! -f "Resources/MacSwitchIcon.icns" ]]; then
    echo "Missing Resources/MacSwitchIcon.icns. Run: swift Scripts/generate_app_icon.swift" >&2
    exit 1
fi

if [[ "$SKIP_NOTARIZATION" != "1" ]]; then
    DIRECT_NOTARY_ENV_NAMES=()
    for name in NOTARY_APPLE_ID NOTARY_TEAM_ID NOTARY_PASSWORD; do
        if [[ -n "${!name:-}" ]]; then
            DIRECT_NOTARY_ENV_NAMES+=("$name")
        fi
    done
    if [[ "${#DIRECT_NOTARY_ENV_NAMES[@]}" -gt 0 ]]; then
        echo "Direct Apple ID notarization environment variables are no longer supported for release builds." >&2
        echo "Unset ${DIRECT_NOTARY_ENV_NAMES[*]} and use a notarytool Keychain profile instead." >&2
        echo "Create it with: $(notary_profile_setup_hint "${NOTARY_PROFILE:-$DEFAULT_NOTARY_PROFILE}")" >&2
        exit 1
    fi

    if [[ -z "$NOTARY_PROFILE" ]]; then
        NOTARY_PROFILE="$DEFAULT_NOTARY_PROFILE"
    fi

    if ! notary_profile_is_available "$NOTARY_PROFILE"; then
        echo "Notarization is required for release builds, but no valid notarytool credentials were found." >&2
        echo "Configured notary keychain profile '$NOTARY_PROFILE' is unavailable or invalid." >&2
        echo "Create it with: $(notary_profile_setup_hint "$NOTARY_PROFILE")" >&2
        echo "For local non-distribution builds only, rerun with SKIP_NOTARIZATION=1." >&2
        exit 1
    fi

    NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
    if [[ -n "$NOTARY_KEYCHAIN" ]]; then
        NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN")
    fi
    NOTARY_AUTH_LABEL="configured keychain profile"
fi

if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning | awk -F '"' '/"Developer ID Application:/ { print $2; exit }')"
fi

if [[ -z "$IDENTITY" ]]; then
    echo "No Developer ID Application signing identity was found." >&2
    echo "Install a Developer ID Application certificate or set SIGN_IDENTITY explicitly." >&2
    exit 1
fi

if ! security find-identity -v -p codesigning | grep -F "$IDENTITY" >/dev/null; then
    echo "Code signing identity '$IDENTITY' was not found." >&2
    echo "Set SIGN_IDENTITY to an installed Developer ID Application identity." >&2
    exit 1
fi

echo "Signing with: $IDENTITY"

if [[ -n "$KEYCHAIN_PASSWORD" && -f "$KEYCHAIN_DB" ]]; then
    echo "Unlocking keychain for codesign."
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_DB" || true
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_DB" || true
fi

read -r -a BUILD_ARCHS <<< "$ARCHS"
if [[ "${#BUILD_ARCHS[@]}" -eq 0 ]]; then
    echo "No build architectures requested." >&2
    exit 1
fi

for arch in "${BUILD_ARCHS[@]}"; do
    swift build -c release --arch "$arch"
done

rm -rf "$APP_PATH" "$ZIP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$FRAMEWORKS_DIR"
if [[ "${#BUILD_ARCHS[@]}" -eq 1 ]]; then
    cp ".build/${BUILD_ARCHS[0]}-apple-macosx/release/$EXECUTABLE_NAME" "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
else
    LIPO_INPUTS=()
    for arch in "${BUILD_ARCHS[@]}"; do
        LIPO_INPUTS+=(".build/$arch-apple-macosx/release/$EXECUTABLE_NAME")
    done
    lipo -create "${LIPO_INPUTS[@]}" -output "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
fi
for arch in "${BUILD_ARCHS[@]}"; do
    lipo "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" -verify_arch "$arch" >/dev/null
done

SPARKLE_SOURCE=".build/${BUILD_ARCHS[0]}-apple-macosx/release/Sparkle.framework"
SPARKLE_DEST="$FRAMEWORKS_DIR/Sparkle.framework"
if [[ ! -d "$SPARKLE_SOURCE" ]]; then
    echo "Missing Sparkle.framework at $SPARKLE_SOURCE. Run swift package resolve and rebuild." >&2
    exit 1
fi
ditto "$SPARKLE_SOURCE" "$SPARKLE_DEST"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" 2>/dev/null || true

cp "Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "Resources/MacSwitchIcon.icns" "$APP_PATH/Contents/Resources/MacSwitchIcon.icns"

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"

set_plist_string() {
    local key="$1"
    local value="$2"
    local plist="$APP_PATH/Contents/Info.plist"
    if /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" >/dev/null 2>&1; then
        return
    fi
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
}

UPDATE_FEED_FIELDS=0
if [[ -n "$SU_FEED_URL" && -z "$SPARKLE_PUBLIC_KEY" && -x "$SPARKLE_BIN_DIR/generate_keys" ]]; then
    SPARKLE_PUBLIC_KEY="$(run_sparkle_tool "$SPARKLE_BIN_DIR/generate_keys" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null || true)"
fi
[[ -n "$SU_FEED_URL" ]] && UPDATE_FEED_FIELDS=$((UPDATE_FEED_FIELDS + 1))
[[ -n "$SPARKLE_PUBLIC_KEY" ]] && UPDATE_FEED_FIELDS=$((UPDATE_FEED_FIELDS + 1))
if [[ "$UPDATE_FEED_FIELDS" -ne 0 && "$UPDATE_FEED_FIELDS" -ne 2 ]]; then
    echo "Sparkle updates require SU_FEED_URL and SPARKLE_PUBLIC_KEY together." >&2
    echo "On the release Mac, create or unlock the Sparkle key with: $SPARKLE_BIN_DIR/generate_keys --account $SPARKLE_ACCOUNT" >&2
    exit 1
fi
if [[ "$UPDATE_FEED_FIELDS" -eq 2 ]]; then
    set_plist_string "SUFeedURL" "$SU_FEED_URL"
    set_plist_string "SUPublicEDKey" "$SPARKLE_PUBLIC_KEY"
fi
if [[ -n "$MAC_SWITCH_FEEDBACK_URL" ]]; then
    set_plist_string "MacSwitchFeedbackURL" "$MAC_SWITCH_FEEDBACK_URL"
fi

for nested in \
    "$SPARKLE_DEST/Versions/Current/XPCServices/Downloader.xpc" \
    "$SPARKLE_DEST/Versions/Current/XPCServices/Installer.xpc" \
    "$SPARKLE_DEST/Versions/Current/Updater.app" \
    "$SPARKLE_DEST/Versions/Current/Autoupdate"; do
    if [[ -e "$nested" ]]; then
        run_codesign --force --options runtime --timestamp --sign "$IDENTITY" "$nested"
    fi
done
run_codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SPARKLE_DEST"

run_codesign --force --options runtime --timestamp \
    --entitlements "$ROOT_DIR/Resources/MacSwitch.entitlements" \
    --sign "$IDENTITY" "$APP_PATH"

run_codesign --verify --deep --strict --verbose=2 "$APP_PATH"
"$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" --self-test-safe
if [[ "$RUN_UI_SMOKE" == "1" ]]; then
    "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" --ui-smoke-test
    "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" --dashboard-smoke-test
fi
spctl --assess --type execute --verbose=4 "$APP_PATH" || true

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
VERIFY_DIR="$(mktemp -d)"
ditto -x -k "$ZIP_PATH" "$VERIFY_DIR"
test -x "$VERIFY_DIR/$APP_NAME.app/Contents/MacOS/$EXECUTABLE_NAME"
test -f "$VERIFY_DIR/$APP_NAME.app/Contents/Resources/MacSwitchIcon.icns"
test -d "$VERIFY_DIR/$APP_NAME.app/Contents/Frameworks/Sparkle.framework"
for arch in "${BUILD_ARCHS[@]}"; do
    lipo "$VERIFY_DIR/$APP_NAME.app/Contents/MacOS/$EXECUTABLE_NAME" -verify_arch "$arch" >/dev/null
done
rm -rf "$VERIFY_DIR"
echo "Built: $APP_PATH"
echo "Archive: $ZIP_PATH"

if [[ "${#NOTARY_ARGS[@]}" -gt 0 ]]; then
    echo "Submitting to Apple notary service with $NOTARY_AUTH_LABEL..."
    NOTARY_RESULT_PATH="$BUILD_DIR/notary-result.json"
    if ! run_notarytool submit "$ZIP_PATH" "${NOTARY_ARGS[@]}" --wait --output-format json > "$NOTARY_RESULT_PATH"; then
        cat "$NOTARY_RESULT_PATH" >&2 || true
        exit 1
    fi
    if ! grep -q '"status"[[:space:]]*:[[:space:]]*"Accepted"' "$NOTARY_RESULT_PATH"; then
        echo "Notarization was not accepted." >&2
        cat "$NOTARY_RESULT_PATH" >&2
        exit 1
    fi
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
    spctl --assess --type execute --verbose=4 "$APP_PATH"
    rm -f "$ZIP_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
    VERIFY_DIR="$(mktemp -d)"
    ditto -x -k "$ZIP_PATH" "$VERIFY_DIR"
    test -x "$VERIFY_DIR/$APP_NAME.app/Contents/MacOS/$EXECUTABLE_NAME"
    test -f "$VERIFY_DIR/$APP_NAME.app/Contents/Resources/MacSwitchIcon.icns"
    test -d "$VERIFY_DIR/$APP_NAME.app/Contents/Frameworks/Sparkle.framework"
    for arch in "${BUILD_ARCHS[@]}"; do
        lipo "$VERIFY_DIR/$APP_NAME.app/Contents/MacOS/$EXECUTABLE_NAME" -verify_arch "$arch" >/dev/null
    done
    rm -rf "$VERIFY_DIR"
    echo "Refreshed stapled archive: $ZIP_PATH"
    echo "Notarized and stapled: $APP_PATH"
else
    echo "Notary submission skipped because SKIP_NOTARIZATION=1. This build is for local testing only."
fi
