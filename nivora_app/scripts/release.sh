#!/usr/bin/env bash
#
# Build the release APK and AAB, verify them, and stage them in dist/.
#
# WHY THIS EXISTS — a near-miss worth preventing permanently.
#
# This repo lives inside OneDrive. OneDrive holds file handles while it uploads; Gradle deletes
# and recreates its output directories constantly; the two race and the build dies with
# AccessDeniedException on a different directory each run. android/build.gradle.kts therefore
# honours NIVORA_BUILD_DIR to move the output out of the synced tree.
#
# The trap: `flutter build apk` STILL PRINTS "Built build\app\outputs\flutter-apk\app-release.apk"
# — the conventional path — while the real artifact lands under $NIVORA_BUILD_DIR. If a stale
# file happens to exist at the conventional path, that message is actively misleading, and it is
# very easy to ship a build from the wrong day. That happened once here: a 65MB APK from the
# previous afternoon sat next to a fresh 67MB one, and the older file was the one about to be
# delivered.
#
# So: this script never trusts the printed path. It locates the artifact, refuses anything not
# produced by THIS run, and checks the things that have actually been wrong before.
#
# Usage:  ./scripts/release.sh          (from nivora_app/)

set -euo pipefail

cd "$(dirname "$0")/.."
APP_DIR="$PWD"
DIST="$(cd .. && pwd)/dist"
: "${NIVORA_BUILD_DIR:=C:/nivora-build}"
export NIVORA_BUILD_DIR
export PATH="/c/Users/shahu/flutter/bin:$PATH"
: "${ANDROID_HOME:=/c/Users/shahu/AppData/Local/Android/Sdk}"
export ANDROID_HOME ANDROID_SDK_ROOT="$ANDROID_HOME"

BT="$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)"
VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/version: *//' | cut -d+ -f1)"
STARTED=$(date +%s)

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[31mFAILED: %s\033[0m\n' "$*" >&2; exit 1; }

say "Gates"
flutter analyze | tail -1 | grep -q "No issues found" || die "analyzer is not clean"
flutter test 2>&1 | tail -1 | grep -q "All tests passed" || die "tests are not passing"

say "Building (output -> $NIVORA_BUILD_DIR)"
# OneDrive re-grabs each directory as Gradle creates it, so clear the two that lose the race
# most often rather than doing a full clean, which costs several minutes.
rm -rf "$NIVORA_BUILD_DIR/app/intermediates/assets" \
       "$NIVORA_BUILD_DIR/app/intermediates/merged_native_libs" 2>/dev/null || true
flutter build apk --release
flutter build appbundle --release

# Find the artifacts wherever they actually are, newest first — never where the log claims.
APK="$(find "$NIVORA_BUILD_DIR" build -name 'app-release.apk' -print0 2>/dev/null \
        | xargs -0 ls -t 2>/dev/null | head -1)"
AAB="$(find "$NIVORA_BUILD_DIR" build -name 'app-release.aab' -print0 2>/dev/null \
        | xargs -0 ls -t 2>/dev/null | head -1)"
[ -n "$APK" ] || die "no APK found"
[ -n "$AAB" ] || die "no AAB found"

say "Freshness"
for f in "$APK" "$AAB"; do
  # A file older than this run is a leftover, and shipping one is the exact mistake this
  # script exists to prevent.
  [ "$(stat -c %Y "$f")" -ge "$STARTED" ] || die "$f predates this build — stale artifact"
  printf '  fresh: %s (%s)\n' "$f" "$(du -h "$f" | cut -f1)"
done

say "Verifying the things that have been wrong before"

# 1. Signed with the real upload key, not Flutter's debug fallback. A debug-signed artifact is
#    rejected by Play, and the template silently falls back when signing is misconfigured.
"$BT/apksigner.bat" verify --print-certs "$APK" 2>/dev/null | grep -q "CN=HostelPro" \
  || die "APK is not signed with the upload key (debug fallback?)"

# 2. Named Nivora. It shipped once as "mobile" — the Flutter PROJECT name, straight to the
#    launcher, because android:label was never changed.
"$BT/aapt2.exe" dump badging "$APK" 2>/dev/null | grep -q "application-label:'Nivora'" \
  || die "launcher label is not Nivora"

# 3. Real phones are ARM. A build missing arm64-v8a installs on nothing anyone owns.
"$BT/aapt2.exe" dump badging "$APK" 2>/dev/null | grep -q "arm64-v8a" \
  || die "arm64-v8a is missing"

# 4. The typeface must ship. google_fonts fetches at runtime by default, and an app that
#    downloads its own font renders as the system font on a first launch with no network.
unzip -l "$APK" | grep -q "google_fonts/Inter-Regular.ttf" \
  || die "Inter is not bundled — the app would download its font on first launch"

# 5. NO SECRETS ON THE DEVICE. An APK is a zip anyone can unpack. The service-role key bypasses
#    every RLS policy; the Razorpay secret authorises money movement. Neither may be in here.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
unzip -o -q "$APK" -d "$TMP" 'assets/flutter_assets/*' 2>/dev/null || true
if grep -rqE 'service_role|rzp_(live|test)_[A-Za-z0-9]{10,}:' "$TMP" 2>/dev/null; then
  die "a secret may be embedded in the bundle — inspect before shipping"
fi
grep -rq "RAZORPAY_KEY_SECRET" lib/ 2>/dev/null && die "Razorpay secret referenced in client source"

# 6. Nothing may open a browser: the product requirement is that every flow stays in the app.
if grep -rnE "^[^/]*\b(launchUrl|launchUrlString|WebViewController|InAppWebView)\b" lib/ 2>/dev/null; then
  die "a browser/WebView escape is present in client code"
fi

say "Staging"
mkdir -p "$DIST"
cp "$APK" "$DIST/NIVORA-$VERSION.apk"
cp "$AAB" "$DIST/NIVORA-$VERSION.aab"
ls -la "$DIST"

printf '\n\033[32mRelease artifacts verified and staged in %s\033[0m\n' "$DIST"
printf 'Install the APK on a phone; upload the AAB to Play Console.\n'
