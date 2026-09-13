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
# ── THIS SCRIPT USED TO PASS ON NOTHING ──────────────────────────────────────────────────────
#
# It searched for the permission as UTF-8 bytes only. An AAB's protobuf manifest stores strings as
# UTF-8, but an APK's compiled binary XML stores them as UTF-16, so on every APK the search could
# never match and "clean" was printed whatever the manifest said. Found by an audit on 2026-09-13
# with a positive control: android.permission.CAMERA, which aapt2 lists as present, was invisible
# to the old search in both APKs. AD_ID was genuinely absent, but the old output was not evidence
# of that.
#
# So it now searches both encodings, and it refuses to say "clean" unless it can also see
# android.permission.INTERNET — which every build of this app declares — in the same file. A check
# that cannot read the manifest now fails loudly instead of passing.
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
  found="$(python3 - "$artifact" <<'PY'
import sys, zipfile

AD_ID = "com.google.android.gms.permission.AD_ID"
CONTROL = "android.permission.INTERNET"

def present(blob, text):
    # AAB protobuf manifests hold UTF-8; APK binary-XML manifests hold UTF-16. Check both.
    return text.encode("utf-8") in blob or text.encode("utf-16-le") in blob

hits, control_seen = [], False
with zipfile.ZipFile(sys.argv[1]) as z:
    for name in z.namelist():
        if name.endswith("AndroidManifest.xml") or name.endswith(".pb"):
            blob = z.read(name)
            if present(blob, CONTROL):
                control_seen = True
            if present(blob, AD_ID):
                hits.append(name)

if not control_seen:
    print("CONTROL_MISSING")
print("\n".join(hits))
PY
)"
  name="$(basename "$artifact")"
  if printf '%s' "$found" | grep -q "CONTROL_MISSING"; then
    printf '\033[31mCANNOT READ\033[0m %s: android.permission.INTERNET not found either, so this check proves nothing\n' "$name" >&2
    fail=1
  elif [ -n "$found" ]; then
    printf '\033[31mAD_ID PRESENT\033[0m in %s:\n%s\n' "$name" "$found" >&2
    fail=1
  else
    printf 'clean: %s (manifest readable: INTERNET found, AD_ID not found)\n' "$name"
  fi
done

if [ "$fail" -ne 0 ]; then
  cat >&2 <<'EOF'

Either the manifest could not be read, or the Advertising ID declaration in Play Console (which
says NO) is contradicted by this artifact.

If AD_ID is present, find which dependency merged it in:
  ./gradlew :app:processReleaseManifest  and read app/build/outputs/logs/manifest-merger-*.txt

Then either drop that dependency, or change the Console declaration to Yes and update
docs/data-safety.md — but do not ship an artifact that contradicts the form.
EOF
  exit 1
fi
