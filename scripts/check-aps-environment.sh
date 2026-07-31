#!/bin/bash
# check-aps-environment.sh — confirm a built app will use PRODUCTION push.
#
# Two things have to agree or notifications silently die:
#   • aps-environment  — baked into the app binary at signing; decides whether
#                        the device registers a sandbox or a production token
#   • APNS_ENV         — the Supabase secret; decides which APNs host we call
#
# A mismatch is worse than "push doesn't work": push-notify treats Apple's
# BadDeviceToken as "unregistered" and DELETES the row from device_tokens, so
# every affected user stops receiving notifications until they relaunch the app.
#
# Usage:
#   ./scripts/check-aps-environment.sh /path/to/HalfLight.ipa
#   ./scripts/check-aps-environment.sh /path/to/HalfLight.app
#   ./scripts/check-aps-environment.sh ~/Library/Developer/Xcode/Archives/.../HalfLight.xcarchive

set -euo pipefail

TARGET="${1:-}"
if [[ -z "$TARGET" || ! -e "$TARGET" ]]; then
    echo "usage: $0 <path to .ipa | .app | .xcarchive>" >&2
    exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

case "$TARGET" in
    *.ipa)
        unzip -qo "$TARGET" -d "$WORK"
        APP="$(find "$WORK/Payload" -maxdepth 1 -name '*.app' | head -1)"
        ;;
    *.xcarchive)
        APP="$(find "$TARGET/Products/Applications" -maxdepth 1 -name '*.app' | head -1)"
        ;;
    *.app)
        APP="$TARGET"
        ;;
    *)
        echo "unrecognised input: $TARGET" >&2; exit 2 ;;
esac

if [[ -z "${APP:-}" || ! -d "$APP" ]]; then
    echo "could not locate a .app inside $TARGET" >&2
    exit 2
fi

echo "app: $APP"
echo

ENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
APS="$(printf '%s' "$ENTS" | plutil -extract aps-environment raw -o - - 2>/dev/null || echo "")"
TASK="$(printf '%s' "$ENTS" | plutil -extract get-task-allow raw -o - - 2>/dev/null || echo "")"

PROFILE_APS=""
if [[ -f "$APP/embedded.mobileprovision" ]]; then
    PROFILE_APS="$(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null \
        | plutil -extract Entitlements.aps-environment raw -o - - 2>/dev/null || echo "")"
fi

echo "  aps-environment (binary):  ${APS:-<none>}"
echo "  aps-environment (profile): ${PROFILE_APS:-<none>}"
echo "  get-task-allow:            ${TASK:-<none>}"
echo

# get-task-allow is true only for development signing; an App Store or TestFlight
# build always has it false/absent. It's the quickest way to tell whether what
# you're holding is actually a distribution build.
if [[ "$TASK" == "true" ]]; then
    echo "NOTE: get-task-allow is true — this is a DEVELOPMENT-signed build."
    echo "      aps-environment: development is expected and correct here."
    echo "      Re-run against an App Store export to check the shipping value."
    exit 0
fi

if [[ "$APS" == "production" ]]; then
    echo "PASS: distribution build uses PRODUCTION push — matches APNS_ENV=production."
    exit 0
fi

echo "FAIL: distribution build has aps-environment=${APS:-<none>}, but the server"
echo "      is set to APNS_ENV=production. Devices would register sandbox tokens,"
echo "      Apple would answer BadDeviceToken, and push-notify would delete them."
exit 1
