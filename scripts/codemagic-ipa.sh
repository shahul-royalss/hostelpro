#!/usr/bin/env bash
# Build the iOS app on Codemagic and download the .ipa to this machine.
#
#   bash scripts/codemagic-ipa.sh                 # start ios-unsigned on main, wait, download
#   bash scripts/codemagic-ipa.sh ios-adhoc       # another workflow from codemagic.yaml
#   bash scripts/codemagic-ipa.sh ios-unsigned my-branch
#   CM_BUILD_ID=<id> bash scripts/codemagic-ipa.sh   # download from a build that already ran
#
# The .ipa lands in dist/ios/, which git ignores. An .ipa does not run on Windows: it goes onto an
# iPhone. docs/ios-codemagic.md, "No paid Apple account", covers installing it.
#
# THE API TOKEN NEVER APPEARS IN A COMMAND LINE OR IN OUTPUT. It is read from the environment
# variable CM_API_TOKEN if set, otherwise from the file ~/.codemagic-token (on Windows,
# C:\Users\<you>\.codemagic-token), which you create yourself and which lives outside this
# repository. It reaches curl on standard input through `curl -K -`, so it is not in any process's
# argument list either. Do not add `set -x` to this script: it would print the header.
#
# API shapes are from Codemagic's own OpenAPI schema (https://codemagic.io/api/v3/schema/openapi.json)
# and its REST docs, read on 2026-09-22:
#   start a build   POST https://api.codemagic.io/builds   {appId, workflowId, branch} -> buildId
#   build status    GET  https://codemagic.io/api/v3/builds/{id} -> data.status, data.artifacts[]
#   list apps       GET  https://codemagic.io/api/v3/user/apps   -> data[].id, data[].name
# Each artifact carries a short_lived_download_url, so nothing long-lived is ever created.

set -euo pipefail

WORKFLOW="${1:-ios-unsigned}"
BRANCH="${2:-main}"
APP_NAME="${CM_APP_NAME:-hostelpro}"
OUT_DIR="dist/ios"
POLL_SECONDS=30
MAX_WAIT_MINUTES=75

cd "$(dirname "$0")/.."

# --- the token, without ever echoing it ---------------------------------------------------------
TOKEN="${CM_API_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f "$HOME/.codemagic-token" ]; then
  # First line only, with surrounding whitespace and a Windows CR stripped: Notepad adds both.
  TOKEN="$(head -n 1 "$HOME/.codemagic-token" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
fi
if [ -z "$TOKEN" ]; then
  echo "No Codemagic API token found."
  echo "Create the file $HOME/.codemagic-token containing only the token, then run this again."
  echo "Where to get it: Codemagic -> Teams -> Personal Account -> Integrations -> Codemagic API."
  exit 1
fi

# curl with the auth header supplied on stdin, so the token is never an argument.
cm() {
  printf 'header = "x-auth-token: %s"\n' "$TOKEN" | curl -sS --fail-with-body -K - "$@"
}

# JSON field extraction with node, which this machine already has for the website. Extra arguments
# reach the snippet as process.argv[1], [2], ... so values are passed as data, never spliced into
# the JavaScript source.
json() { local code="$1"; shift; node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const j=JSON.parse(s);${code}})" "$@"; }

# --- which app ------------------------------------------------------------------------------------
APP_ID="${CM_APP_ID:-}"
if [ -z "$APP_ID" ]; then
  APPS="$(cm "https://codemagic.io/api/v3/user/apps?page_size=100")" || { echo "Could not list apps. Is the token right?"; exit 1; }
  APP_ID="$(printf '%s' "$APPS" | json "
    const want=process.argv[1];
    const m=(j.data||[]).filter(a=>!a.archived && (a.name||'').toLowerCase().includes(want.toLowerCase()));
    if(m.length===1){console.log(m[0].id)}
    else{console.error(m.length
      ? 'More than one app matches \"'+want+'\": '+m.map(a=>a.name+' ('+a.id+')').join(', ')+'. Set CM_APP_ID.'
      : 'No app named like \"'+want+'\". Apps on this account: '+((j.data||[]).map(a=>a.name).join(', ')||'none')+'. Add the repository in Codemagic, or set CM_APP_NAME or CM_APP_ID.');
      process.exit(3)}" "$APP_NAME")" || exit 1
fi
echo "App: $APP_ID"

# --- start a build, or use the one given -----------------------------------------------------------
BUILD_ID="${CM_BUILD_ID:-}"
if [ -z "$BUILD_ID" ]; then
  BODY="$(node -e "console.log(JSON.stringify({appId:process.argv[1],workflowId:process.argv[2],branch:process.argv[3]}))" "$APP_ID" "$WORKFLOW" "$BRANCH")"
  START="$(cm -X POST -H "Content-Type: application/json" -d "$BODY" "https://api.codemagic.io/builds")" || {
    echo "Codemagic refused to start the build:"; printf '%s\n' "$START"; exit 1; }
  BUILD_ID="$(printf '%s' "$START" | json "console.log(j.buildId)")"
  echo "Started $WORKFLOW on $BRANCH: build $BUILD_ID"
else
  echo "Using existing build $BUILD_ID"
fi
echo "Watch it live: https://codemagic.io/app/$APP_ID/build/$BUILD_ID"

# --- wait for it ----------------------------------------------------------------------------------
# Terminal states per the schema's data.status enum. Anything else means it is still going.
LAST=""
DEADLINE=$(( $(date +%s) + MAX_WAIT_MINUTES * 60 ))
while :; do
  INFO="$(cm "https://codemagic.io/api/v3/builds/$BUILD_ID")" || { echo "Status check failed; retrying."; sleep "$POLL_SECONDS"; continue; }
  STATUS="$(printf '%s' "$INFO" | json "console.log(j.data.status)")"
  [ "$STATUS" != "$LAST" ] && { echo "$(date +%H:%M:%S)  $STATUS"; LAST="$STATUS"; }
  case "$STATUS" in
    finished) break ;;
    failed|canceled|timeout|skipped)
      echo "Build ended as '$STATUS'. The log is at the link above; the first failing step names the cause."
      exit 2 ;;
  esac
  if [ "$(date +%s)" -gt "$DEADLINE" ]; then
    echo "Still '$STATUS' after $MAX_WAIT_MINUTES minutes. It may still finish: run again with CM_BUILD_ID=$BUILD_ID."
    exit 4
  fi
  sleep "$POLL_SECONDS"
done

# --- download every .ipa ---------------------------------------------------------------------------
mkdir -p "$OUT_DIR"
# One line per ipa: name<TAB>size<TAB>url. The URL is used below and never printed.
LIST="$(printf '%s' "$INFO" | json "
  (j.data.artifacts||[]).filter(a=>a.type==='ipa').forEach(a=>console.log([a.name,a.size_in_bytes,a.short_lived_download_url].join('\t')))")"
if [ -z "$LIST" ]; then
  echo "The build finished but produced no .ipa. Check the workflow's artifacts section in codemagic.yaml."
  exit 5
fi

while IFS=$'\t' read -r NAME SIZE URL; do
  DEST="$OUT_DIR/$NAME"
  echo "Downloading $NAME ($SIZE bytes) ..."
  # The short-lived URL is pre-authorised by Codemagic, so no token goes with it.
  curl -sS --fail -L -o "$DEST" "$URL"
  GOT=$(wc -c < "$DEST" | tr -d ' ')
  if [ -n "$SIZE" ] && [ "$GOT" != "$SIZE" ]; then
    echo "  Size mismatch: expected $SIZE, got $GOT. Delete $DEST and run again with CM_BUILD_ID=$BUILD_ID."
    exit 6
  fi
  echo "  Saved $DEST"
  echo "  $GOT bytes, SHA-256 $(sha256sum "$DEST" | cut -d' ' -f1)"
done <<< "$LIST"

echo
echo "Done. To put it on an iPhone, see docs/ios-codemagic.md, section \"No paid Apple account\"."
