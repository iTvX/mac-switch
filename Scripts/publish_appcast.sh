#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST_PATH="${APPCAST_PATH:-$ROOT_DIR/Build/Appcast/appcast.xml}"
APPCAST_RELEASE_TAG="${APPCAST_RELEASE_TAG:-appcast}"
APPCAST_RELEASE_TITLE="${APPCAST_RELEASE_TITLE:-Mac Switch Appcast}"
APPCAST_RELEASE_NOTES="${APPCAST_RELEASE_NOTES:-Stable Sparkle appcast feed for official Mac Switch releases.}"
APPCAST_PUBLIC_URL="${APPCAST_PUBLIC_URL:-}"
APPCAST_VERIFY_ATTEMPTS="${APPCAST_VERIFY_ATTEMPTS:-24}"
APPCAST_VERIFY_DELAY_SECONDS="${APPCAST_VERIFY_DELAY_SECONDS:-5}"

if [[ ! -f "$APPCAST_PATH" ]]; then
    echo "Appcast file is missing at $APPCAST_PATH." >&2
    exit 1
fi

if [[ -z "$APPCAST_PUBLIC_URL" ]]; then
    if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
        echo "Set APPCAST_PUBLIC_URL or run in GitHub Actions with GITHUB_REPOSITORY available." >&2
        exit 1
    fi
    APPCAST_PUBLIC_URL="https://github.com/$GITHUB_REPOSITORY/releases/download/$APPCAST_RELEASE_TAG/$(basename "$APPCAST_PATH")"
fi

expected_appcast_version="$(sed -n 's|.*<sparkle:version>\([^<][^<]*\)</sparkle:version>.*|\1|p' "$APPCAST_PATH" | head -n 1)"
expected_enclosure_url="$(sed -n 's|.*<enclosure url="\([^"]*\)".*|\1|p' "$APPCAST_PATH" | head -n 1)"

if [[ -z "$expected_appcast_version" || -z "$expected_enclosure_url" ]]; then
    echo "Appcast is missing sparkle:version or enclosure URL." >&2
    exit 1
fi

if ! gh release view "$APPCAST_RELEASE_TAG" >/dev/null 2>&1; then
    if ! git rev-parse -q --verify "refs/tags/$APPCAST_RELEASE_TAG" >/dev/null; then
        git tag "$APPCAST_RELEASE_TAG" "${GITHUB_SHA:-HEAD}"
        git push origin "$APPCAST_RELEASE_TAG"
    fi
    gh release create "$APPCAST_RELEASE_TAG" "$APPCAST_PATH" \
        --title "$APPCAST_RELEASE_TITLE" \
        --notes "$APPCAST_RELEASE_NOTES" \
        --prerelease
else
    gh release upload "$APPCAST_RELEASE_TAG" "$APPCAST_PATH" --clobber
fi

echo "Published appcast release asset: $APPCAST_RELEASE_TAG/appcast.xml"

for attempt in $(seq 1 "$APPCAST_VERIFY_ATTEMPTS"); do
    remote_appcast="$(curl -fsSL \
        -H 'Cache-Control: no-cache' \
        -H 'Pragma: no-cache' \
        "$APPCAST_PUBLIC_URL" || true)"

    if grep -Fq "<sparkle:version>$expected_appcast_version</sparkle:version>" <<< "$remote_appcast" &&
        grep -Fq "$expected_enclosure_url" <<< "$remote_appcast"; then
        echo "Verified public appcast feed: $APPCAST_PUBLIC_URL"
        exit 0
    fi

    if [[ "$attempt" -lt "$APPCAST_VERIFY_ATTEMPTS" ]]; then
        echo "Public appcast is not current yet; retrying in ${APPCAST_VERIFY_DELAY_SECONDS}s ($attempt/$APPCAST_VERIFY_ATTEMPTS)."
        sleep "$APPCAST_VERIFY_DELAY_SECONDS"
    fi
done

echo "Public appcast did not match generated appcast at $APPCAST_PUBLIC_URL." >&2
echo "Expected sparkle:version $expected_appcast_version and enclosure $expected_enclosure_url." >&2
exit 1
