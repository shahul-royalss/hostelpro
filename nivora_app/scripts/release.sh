#!/usr/bin/env bash
#
# Build the release APK and AAB, verify them, and stage them in dist/.
#
# WHY THIS EXISTS — two failures this project actually had.
#
# 1. A BUILD THAT LIED ABOUT WHAT IT BUILT. This repo sits inside OneDrive, which holds file
#    handles while it uploads while Gradle deletes and recreates its output directories. They
#    race, and a build dies with AccessDeniedException on a different directory each run. The
#    obvious fix — point the Gradle output somewhere OneDrive does not watch — is worse than the
#    problem: `flutter build apk` looks for its artifact at build/app/outputs/flutter-apk/ by
#    convention, and if the real output moved, it reports whatever stale file already sits
#    there. Two consecutive builds printed the same size while the real artifact was elsewhere.
#    So the output stays where Flutter expects it, this script clears the directories that lose
#    the race, retries a lock, and then REFUSES ANY ARTIFACT OLDER THAN THIS RUN.
#
# 2. Six specific things that have each shipped broken here at least once. They are checked
#    below, and none of them is hypothetical.
#
# The durable fix for (1) is to exclude nivora_app/build from OneDrive sync, or move the repo
# out of OneDrive entirely. Both remove the race instead of working around it.
#
# Usage:  bash scripts/release.sh          (from nivora_app/)

set -euo pipefail

cd "$(dirname "$0")/.."
APP_DIR="$PWD"
DIST="$(cd .. && pwd)/dist"
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

say "Building"
# A OneDrive lock is transient: it releases once the upload finishes. Clearing the directories
# that lose the race and retrying is the honest response — unlike relocating the output, which
# merely hides the problem behind a stale artifact.
build_with_retry() {
  local what="$1" attempt
  for attempt in 1 2 3; do
    rm -rf build/app/intermediates/assets \
           build/app/intermediates/merged_native_libs \
           build/app/intermediates/native_symbol_tables 2>/dev/null || true
    if flutter build "$what" --release; then
      return 0
    fi
    printf '  attempt %s of 3 failed (likely a sync lock) — retrying\n' "$attempt"
    sleep 5
  done
  die "$what build failed three times — is OneDrive syncing this folder?"
}

build_with_retry apk
build_with_retry appbundle

APK="build/app/outputs/flutter-apk/app-release.apk"
AAB="build/app/outputs/bundle/release/app-release.aab"
[ -f "$APK" ] || die "no APK at $APK"
[ -f "$AAB" ] || die "no AAB at $AAB"

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
# Written as an `if` rather than `grep ... && die`: under `set -e` the AND-list form makes a
# CLEAN result (grep exits 1 because it found nothing) the script's exit status, so the good
# case would abort the release. A check that fails when it passes is worse than no check.
if grep -rq "RAZORPAY_KEY_SECRET" lib/ 2>/dev/null; then
  die "Razorpay secret referenced in client source"
fi

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
