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
# Captured rather than piped, for the pipefail reason documented under "Verifying" below, and
# because the actual counts are worth printing: "316 passed" tells you something that a silent
# success does not.
analyze_out="$(flutter analyze 2>&1 || true)"
case "$analyze_out" in
  *"No issues found"*) printf '  analyzer clean\n' ;;
  *) printf '%s\n' "$analyze_out" | tail -20; die "analyzer is not clean" ;;
esac

test_out="$(flutter test 2>&1 || true)"
case "$test_out" in
  *"All tests passed"*) printf '  %s\n' "$(printf '%s' "$test_out" | tail -1 | sed 's/^[0-9:]* //')" ;;
  *) printf '%s\n' "$test_out" | tail -25; die "tests are not passing" ;;
esac

say "Preparing a build tree outside OneDrive"
# WHY BUILD ELSEWHERE, and why THIS way rather than the way I tried first.
#
# OneDrive holds handles on files inside nivora_app/build while it uploads them, and Gradle
# deletes and recreates those directories constantly. The lock is not transient enough to
# retry through: four consecutive attempts died on the same path.
#
# The first attempt at a fix pointed Gradle's output somewhere OneDrive does not watch. That
# broke Flutter's contract — the tool looks for its artifact at build/app/outputs/ by
# convention, did not find it, and reported whatever stale file was sitting there instead. A
# build that lies about what it built is worse than one that fails.
#
# So instead: copy the SOURCE to a plain directory outside the synced tree and build there.
# Flutter's layout is untouched, build/ is exactly where it expects, and OneDrive has nothing
# to do with any of it. The repository stays the source of truth; only the compile moves.
WORK="${NIVORA_WORK_DIR:-/c/nivora-work}"
if [[ "$APP_DIR" == *OneDrive* ]]; then
  printf '  repo is inside OneDrive — building in %s\n' "$WORK"
  # Derived directories are deliberately not copied: they are what OneDrive was fighting over,
  # and they regenerate. Done with tar rather than rsync, which Git Bash does not ship.
  rm -rf "$WORK"
  mkdir -p "$WORK"
  ( cd "$APP_DIR" && tar -cf - \
      --exclude='./build' --exclude='./.dart_tool' --exclude='./.gradle' \
      --exclude='./android/.gradle' --exclude='./ios/Pods' \
      --exclude='*.apk' --exclude='*.aab' . ) \
    | ( cd "$WORK" && tar -xf - ) \
    || die "could not copy the project to $WORK"
  cd "$WORK"
else
  printf '  repo is outside OneDrive — building in place\n'
fi

say "Building"
# A OneDrive lock is transient: it releases once the upload finishes. Clearing the directories
# that lose the race and retrying is the honest response — unlike relocating the output, which
# merely hides the problem behind a stale artifact.
build_with_retry() {
  local what="$1" attempt
  for attempt in 1 2 3 4; do
    # Clear ALL intermediates, not a hand-picked list. The first version of this named three
    # directories and the very next failure was in a fourth (flutter/release/native_assets/
    # jniLibs) — there is no stable set, because which directory loses the race depends on what
    # OneDrive happens to be uploading at that instant. Intermediates are derived by definition,
    # so deleting the lot costs build time and nothing else.
    rm -rf build/app/intermediates 2>/dev/null || true
    if flutter build "$what" --release; then
      return 0
    fi
    # Back off further each time: the lock lasts as long as the upload does, and a 5-second
    # retry into a large upload just fails again.
    printf '  attempt %s of 4 failed (likely a OneDrive sync lock) — waiting %ss\n' \
           "$attempt" "$((attempt * 15))"
    sleep "$((attempt * 15))"
  done
  die "$what failed four times. OneDrive is holding files in nivora_app/build.
     Fix it properly: exclude that folder from sync, or move the repo out of OneDrive.
     Pausing OneDrive for the duration of a build also works as a stopgap."
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

# A NOTE ON HOW THESE ARE WRITTEN, because the obvious form is broken here.
#
# This script runs under `set -o pipefail`, and the natural spelling
#
#     unzip -l "$APK" | grep -q "something"
#
# FAILS WHEN IT SUCCEEDS. `grep -q` exits the moment it matches, which closes the pipe; the
# producer — still writing a 65MB listing — dies of SIGPIPE; pipefail then reports the whole
# pipeline as failed. The check reports a problem precisely because there wasn't one. That
# cost a release run here before it was understood.
#
# So every check below captures its producer's output FIRST and searches the string after. No
# pipes into short-circuiting readers, and no false alarms.
badging="$("$BT/aapt2.exe" dump badging "$APK" 2>/dev/null || true)"
certs="$("$BT/apksigner.bat" verify --print-certs "$APK" 2>/dev/null || true)"
entries="$(unzip -l "$APK" 2>/dev/null || true)"

# 1. Signed with the real upload key, not Flutter's debug fallback. A debug-signed artifact is
#    rejected by Play, and the template silently falls back when signing is misconfigured.
case "$certs" in
  *"CN=HostelPro"*) ;;
  *) die "APK is not signed with the upload key (debug fallback?)" ;;
esac

# 2. Named Nivora. It shipped once as "mobile" — the Flutter PROJECT name, straight to the
#    launcher, because android:label was never changed.
case "$badging" in
  *"application-label:'Nivora'"*) ;;
  *) die "launcher label is not Nivora" ;;
esac

# 3. Real phones are ARM. A build missing arm64-v8a installs on nothing anyone owns.
case "$badging" in
  *"arm64-v8a"*) ;;
  *) die "arm64-v8a is missing" ;;
esac

# 4. The typeface must ship. google_fonts fetches at runtime by default, and an app that
#    downloads its own font renders as the system font on a first launch with no network.
case "$entries" in
  *"google_fonts/Inter-Regular.ttf"*) ;;
  *) die "Inter is not bundled — the app would download its font on first launch" ;;
esac

# 5. NO SECRETS ON THE DEVICE. An APK is a zip anyone can unpack. The service-role key bypasses
#    every RLS policy; the Razorpay secret authorises money movement. Neither may be in here.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
unzip -o -q "$APK" -d "$TMP" 'assets/flutter_assets/*' 2>/dev/null || true
if grep -rqE 'service_role|rzp_(live|test)_[A-Za-z0-9]{10,}:' "$TMP" 2>/dev/null; then
  die "a secret may be embedded in the bundle — inspect before shipping"
fi
if grep -rq "RAZORPAY_KEY_SECRET" lib/ 2>/dev/null; then
  die "Razorpay secret referenced in client source"
fi

# 6. Nothing may open a browser: the product requirement is that every flow stays in the app.
if grep -rnE "^[^/]*(launchUrl|launchUrlString|WebViewController|InAppWebView)" lib/ 2>/dev/null; then
  die "a browser/WebView escape is present in client code"
fi

printf '  signature, label, ABIs, bundled font, no secrets, no browser escape — all pass
'

say "Staging"
mkdir -p "$DIST"
cp "$APK" "$DIST/NIVORA-$VERSION.apk"
cp "$AAB" "$DIST/NIVORA-$VERSION.aab"
ls -la "$DIST"

printf '\n\033[32mRelease artifacts verified and staged in %s\033[0m\n' "$DIST"
printf 'Install the APK on a phone; upload the AAB to Play Console.\n'
