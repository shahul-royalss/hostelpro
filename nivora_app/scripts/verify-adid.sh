#!/usr/bin/env bash
#
# Is there an advertising ID in what we are about to upload?
#
# WHY THIS IS A SCRIPT AND NOT A BELIEF. Play Console asks a yes/no question — "does your app use
# an advertising ID" — and Nivora answers No. That answer is about the MERGED manifest, not about
# our source: any dependency can declare `com.google.android.gms.permission.AD_ID` in its own
# manifest and have it merged into ours without a line of our code changing. Firebase Analytics
# does exactly that, which is one reason it is not installed here.
#
# android/app/src/main/AndroidManifest.xml removes it explicitly:
#
#     <uses-permission android:name="com.google.android.gms.permission.AD_ID" tools:node="remove"/>
#
# tools:node="remove" wins over anything merged in — but "wins" is a claim about a build, and this
# is how the claim gets checked against the artifact that is actually going to Google.
#
# Usage:  bash scripts/verify-adid.sh [path-to-apk-or-aab ...]
#         (defaults to everything in dist/)

set -euo pipefail

cd "$(dirname "$0")/.."
DIST="$(cd .. && pwd)/dist"

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
  shopt -s nullglob
  targets=("$DIST"/*.apk "$DIST"/*.aab)
  shopt -u nullglob
fi

if [ ${#targets[@]} -eq 0 ]; then
  echo "Nothing to check — build first with scripts/release.sh." >&2
  exit 1
fi

fail=0
for artifact in "${targets[@]}"; do
  [ -f "$artifact" ] || continue
  # The permission name appears verbatim in the string pool of a compiled manifest, in both the
  # APK's binary XML and the AAB's protobuf, so one byte-level search covers both formats without
  # needing aapt2 (which cannot read an AAB's manifest anyway).
  found="$(python3 - "$artifact" <<'PY'
import sys, zipfile
needle = b"com.google.android.gms.permission.AD_ID"
hits = []
with zipfile.ZipFile(sys.argv[1]) as z:
    for name in z.namelist():
        if name.endswith("AndroidManifest.xml") or name.endswith(".pb"):
            if needle in z.read(name):
                hits.append(name)
print("\n".join(hits))
PY
)"
  if [ -n "$found" ]; then
    printf '\033[31mAD_ID PRESENT\033[0m in %s:\n%s\n' "$(basename "$artifact")" "$found" >&2
    fail=1
  else
    printf 'clean: %s\n' "$(basename "$artifact")"
  fi
done

if [ "$fail" -ne 0 ]; then
  cat >&2 <<'EOF'

The Advertising ID declaration in Play Console says NO. This artifact disagrees with it.

Find which dependency merged it in:
  ./gradlew :app:processReleaseManifest  and read app/build/outputs/logs/manifest-merger-*.txt

Then either drop that dependency, or change the Console declaration to Yes and update
docs/data-safety.md — but do not ship an artifact that contradicts the form.
EOF
  exit 1
fi
