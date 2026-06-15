#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Mac Switch"
EXECUTABLE_NAME="MacSwitch"
APP_PATH="${APP_PATH:-$ROOT_DIR/Build/$APP_NAME.app}"
ZIP_PATH="${ZIP_PATH:-$ROOT_DIR/Build/$APP_NAME.zip}"
DEFAULT_NOTARY_PROFILE="${DEFAULT_NOTARY_PROFILE:-mac-switch-notary}"
NOTARY_PROFILE="${NOTARY_PROFILE:-$DEFAULT_NOTARY_PROFILE}"
NOTARY_APPLE_ID="${NOTARY_APPLE_ID:-}"
NOTARY_TEAM_ID="${NOTARY_TEAM_ID:-}"
NOTARY_PASSWORD="${NOTARY_PASSWORD:-}"
KEYCHAIN_DB="${KEYCHAIN_DB:-$HOME/Library/Keychains/login.keychain-db}"
NOTARY_KEYCHAIN="${NOTARY_KEYCHAIN:-}"
NOTARY_VIA_LAUNCHCTL="${NOTARY_VIA_LAUNCHCTL:-0}"

failures=0

run_notarytool() {
    if [[ "$NOTARY_VIA_LAUNCHCTL" == "1" ]]; then
        launchctl asuser "$(id -u)" xcrun notarytool "$@"
    else
        xcrun notarytool "$@"
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

fail() {
    echo "FAIL $1" >&2
    failures=$((failures + 1))
}

pass() {
    echo "PASS $1"
}

echo "Checking release readiness for: $APP_PATH"

if [[ ! -d "$APP_PATH" ]]; then
    fail "App bundle is missing. Run ./Scripts/build_release.sh first."
    exit 1
fi

if [[ ! -x "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" ]]; then
    fail "App executable is missing or not executable."
else
    pass "App executable exists"
fi

if codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null 2>&1; then
    pass "Developer ID code signature is valid"
else
    fail "Code signature verification failed."
fi

if spctl --assess --type execute --verbose=4 "$APP_PATH" >/dev/null 2>&1; then
    pass "Gatekeeper accepts the app"
else
    fail "Gatekeeper rejects the app. Notarize and staple it before shipping."
fi

if xcrun stapler validate "$APP_PATH" >/dev/null 2>&1; then
    pass "Notarization staple is valid"
else
    fail "No valid notarization staple found on the app."
fi

DIRECT_NOTARY_FIELDS=0
[[ -n "$NOTARY_APPLE_ID" ]] && DIRECT_NOTARY_FIELDS=$((DIRECT_NOTARY_FIELDS + 1))
[[ -n "$NOTARY_TEAM_ID" ]] && DIRECT_NOTARY_FIELDS=$((DIRECT_NOTARY_FIELDS + 1))
[[ -n "$NOTARY_PASSWORD" ]] && DIRECT_NOTARY_FIELDS=$((DIRECT_NOTARY_FIELDS + 1))

if [[ "$DIRECT_NOTARY_FIELDS" -eq 3 ]]; then
    if run_notarytool history --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" >/dev/null 2>&1; then
        pass "Direct notary credentials are available"
    else
        fail "Direct notary credentials are invalid or unavailable."
    fi
elif [[ "$DIRECT_NOTARY_FIELDS" -ne 0 ]]; then
    fail "Direct notary credentials require NOTARY_APPLE_ID, NOTARY_TEAM_ID, and NOTARY_PASSWORD together."
elif notary_profile_is_available "$NOTARY_PROFILE"; then
    pass "Configured notary keychain profile is available"
else
    fail "Configured notary keychain profile is unavailable. Create it with: $(notary_profile_setup_hint "$NOTARY_PROFILE")"
fi

if [[ -f "$ZIP_PATH" ]]; then
    VERIFY_DIR="$(mktemp -d)"
    if ditto -x -k "$ZIP_PATH" "$VERIFY_DIR" >/dev/null 2>&1 \
        && [[ -x "$VERIFY_DIR/$APP_NAME.app/Contents/MacOS/$EXECUTABLE_NAME" ]]; then
        pass "Release archive extracts with executable app"
    else
        fail "Release archive is missing the executable app."
    fi
    rm -rf "$VERIFY_DIR"
else
    fail "Release archive is missing at $ZIP_PATH."
fi

if [[ "$failures" -gt 0 ]]; then
    echo "Release readiness failed with $failures issue(s)." >&2
    exit 1
fi

echo "Release readiness checks passed."
