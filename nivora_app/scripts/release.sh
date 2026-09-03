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
  # $1 is the flutter target (apk | appbundle); anything after it is passed through, which is
  # how the per-ABI build asks for --split-per-abi without a second copy of this function.
  local what="$1"; shift
  local extra=("$@") attempt out
  for attempt in 1 2 3; do
    rm -rf build/app/intermediates 2>/dev/null || true
    out="$(flutter build "$what" --release "${extra[@]}" 2>&1)" && { printf '%s
' "$out" | tail -2; return 0; }

    # DIAGNOSE BEFORE RETRYING. The first version of this loop assumed every failure was a
    # OneDrive lock and slept its way through four attempts of an error that was never going
    # to change. A retry is only the right response to a TRANSIENT failure; classifying first
    # costs one grep and saves four minutes of confident waiting.
    if printf '%s' "$out" | grep -qE "PKIX path|certificate_unknown|unable to find valid certification"; then
      # Norton (or any TLS-intercepting antivirus) is answering Gradle's dependency downloads
      # with its own certificate, which the JVM does not trust. Everything this project needs
      # is already in ~/.gradle from previous builds, so --offline both proves the diagnosis
      # and completes the build. gradlew is invoked directly because `flutter build` exposes
      # no offline flag; the artifacts land in the same place.
      printf '  TLS interception detected (PKIX failure) — retrying from the local cache with --offline
'
      printf '  Durable fix for this machine: import the interceptor root into the JVM truststore, e.g.
'
      printf '    keytool -importcert -alias norton-root -file <norton-root.pem> -cacerts -storepass changeit
'
      local task; task=$([ "$what" = apk ] && echo assembleRelease || echo bundleRelease)
      # `--split-per-abi` is a Flutter flag, not a Gradle task: it works by setting this
      # property. A direct gradlew call has to set it too, or the offline fallback silently
      # produces a universal APK and the split artifact the caller asked for never appears.
      local props=(); case " ${extra[*]} " in *" --split-per-abi "*) props=(-Psplit-per-abi=true);; esac
      # TWO lessons encoded here, both paid for:
      #  - JAVA_HOME must be Android Studio's JBR (JDK 21). `flutter build` selects it
      #    automatically, but a direct gradlew call inherits the system JDK — 26 on this
      #    machine — whose jlink breaks AGP's JdkImageTransform. Every "offline cache is
      #    broken" conclusion drawn before setting this was actually a wrong-JDK failure.
      #  - The output is captured in full and printed on failure. Three separate debugging
      #    rounds here were spent re-running builds because a `| tail -3` had already
      #    discarded the one line that named the real problem.
      local jbr="C:\Program Files\Android\Android Studio\jbr"
      local gout
      gout="$(cd android && JAVA_HOME="$jbr" ./gradlew "$task" "${props[@]}" --offline 2>&1)"         && { printf '%s
' "$gout" | tail -3; return 0; }
      printf '%s
' "$gout" | grep -B4 -A12 "What went wrong" | head -20
      die "$what failed offline too (full error above)"
    fi

    if printf '%s' "$out" | grep -qE "AccessDeniedException|Unable to delete director|cannot access the file"; then
      printf '  attempt %s of 3: sync lock — waiting %ss
' "$attempt" "$((attempt * 15))"
      sleep "$((attempt * 15))"
      continue
    fi

    # Neither known transient cause: retrying would just repeat it. Show the error and stop.
    printf '%s
' "$out" | grep -B2 -A8 "What went wrong" | head -14
    die "$what failed with an error retries cannot fix (see above)"
  done
  die "$what failed three times on sync locks. Exclude nivora_app/build from OneDrive sync, or pause OneDrive for the build."
}

build_with_retry apk
build_with_retry appbundle

# ── AND ONE APK PER CPU, WHICH IS THE ONE A PERSON SHOULD ACTUALLY INSTALL ──────────────────
#
# The universal APK above carries the native libraries for THREE architectures, and native
# libraries are 61 of its 64 MB: arm64-v8a 20.6, armeabi-v7a 18.4, x86_64 22.0. Every phone runs
# exactly one of those, so two thirds of the download is dead weight on any given handset — and
# x86_64 is an EMULATOR target that no phone on sale has ever used.
#
# Splitting produces one APK per architecture; the arm64 one is ~23 MB. Play never sees these —
# it takes the AAB and does the same split itself, which is why the store download was always
# going to be small. This is for the copy handed round as a file, which until now was the fat one.
#
# The universal APK is still built and still staged: an armeabi-v7a handset, or anyone who cannot
# tell which they have, needs a build that installs anywhere.
build_with_retry apk --split-per-abi

APK="build/app/outputs/flutter-apk/app-release.apk"
AAB="build/app/outputs/bundle/release/app-release.aab"
APK_ARM64="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
[ -f "$APK" ] || die "no APK at $APK"
[ -f "$AAB" ] || die "no AAB at $AAB"
[ -f "$APK_ARM64" ] || die "no arm64 APK at $APK_ARM64 — the split build did not produce one"

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
# EVERY ARTIFACT THAT LEAVES THIS SCRIPT IS CHECKED, not just the first one built. The per-ABI
# APK is now the one handed to people, and an unverified artifact going out under a trusted name
# is the exact failure the rest of this section exists to prevent. Same gates, run over each.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

verify_apk() {
  local apk="$1" label="$2" badging certs entries unpack
  badging="$("$BT/aapt2.exe" dump badging "$apk" 2>/dev/null || true)"
  certs="$("$BT/apksigner.bat" verify --print-certs "$apk" 2>/dev/null || true)"
  entries="$(unzip -l "$apk" 2>/dev/null || true)"

  # 1. Signed with the real upload key, not Flutter's debug fallback. A debug-signed artifact is
  #    rejected by Play, and the template silently falls back when signing is misconfigured.
  case "$certs" in
    *"CN=HostelPro"*) ;;
    *) die "$label is not signed with the upload key (debug fallback?)" ;;
  esac

  # 2. Named Nivora. It shipped once as "mobile" — the Flutter PROJECT name, straight to the
  #    launcher, because android:label was never changed.
  case "$badging" in
    *"application-label:'Nivora'"*) ;;
    *) die "$label: launcher label is not Nivora" ;;
  esac

  # 3. Real phones are ARM. A build missing arm64-v8a installs on nothing anyone owns — and for
  #    the split build this is also the check that it really is the arm64 one.
  case "$badging" in
    *"arm64-v8a"*) ;;
    *) die "$label: arm64-v8a is missing" ;;
  esac

  # 4. The typeface must ship. google_fonts fetches at runtime by default, and an app that
  #    downloads its own font renders as the system font on a first launch with no network.
  case "$entries" in
    *"google_fonts/Inter-Regular.ttf"*) ;;
    *) die "$label: Inter is not bundled — the app would download its font on first launch" ;;
  esac

  # 5. NO SECRETS ON THE DEVICE. An APK is a zip anyone can unpack. The service-role key bypasses
  #    every RLS policy; the Razorpay secret authorises money movement. Neither may be in here.
  #    Unpacked to its own directory so one APK's assets cannot be mistaken for another's.
  unpack="$TMP/$label"; mkdir -p "$unpack"
  unzip -o -q "$apk" -d "$unpack" 'assets/flutter_assets/*' 2>/dev/null || true
  if grep -rqE 'service_role|rzp_(live|test)_[A-Za-z0-9]{10,}:' "$unpack" 2>/dev/null; then
    die "$label: a secret may be embedded in the bundle — inspect before shipping"
  fi
  printf '  %s: signature, label, arm64, bundled font, no secrets — pass\n' "$label"
}

verify_apk "$APK"       "universal-apk"
verify_apk "$APK_ARM64" "arm64-apk"
if grep -rq "RAZORPAY_KEY_SECRET" lib/ 2>/dev/null; then
  die "Razorpay secret referenced in client source"
fi

# 6. Nothing may open a browser: the product requirement is that every flow stays in the app.
if grep -rnE "^[^/]*(launchUrl|launchUrlString|WebViewController|InAppWebView)" lib/ 2>/dev/null; then
  die "a browser/WebView escape is present in client code"
fi

printf '  source: no secret reference, no browser escape — pass\n'

say "Staging"
mkdir -p "$DIST"
# THE arm64 BUILD IS THE ONE TO HAND ROUND. It is the architecture of every phone sold in the
# last decade, and it is a third of the size. The universal build is kept beside it under a name
# that says what it is for, so "which file do I send someone" has an obvious answer and the
# fallback still exists for an old 32-bit handset.
cp "$APK_ARM64" "$DIST/NIVORA-$VERSION.apk"
cp "$APK"       "$DIST/NIVORA-$VERSION-universal.apk"
cp "$AAB"       "$DIST/NIVORA-$VERSION.aab"

# Play splits the AAB per device itself, so the store download matches the arm64 figure rather
# than the universal one. Printed because the difference is the whole point of the split.
printf '  installable APK (arm64):  %s\n' "$(du -h "$DIST/NIVORA-$VERSION.apk" | cut -f1)"
printf '  universal APK (any CPU):  %s\n' "$(du -h "$DIST/NIVORA-$VERSION-universal.apk" | cut -f1)"
printf '  AAB for Play Console:     %s\n' "$(du -h "$DIST/NIVORA-$VERSION.aab" | cut -f1)"
ls -la "$DIST"

printf '\n\033[32mRelease artifacts verified and staged in %s\033[0m\n' "$DIST"
printf 'Install the APK on a phone; upload the AAB to Play Console.\n'
