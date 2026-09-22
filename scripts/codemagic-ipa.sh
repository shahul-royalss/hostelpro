#!/usr/bin/env bash
# Build the iOS app on Codemagic and download the .ipa to this machine.
#
#   bash scripts/codemagic-ipa.sh                 # start ios-unsigned on main, wait, download
#   bash scripts/codemagic-ipa.sh ios-adhoc       # another workflow from codemagic.yaml
#   bash scripts/codemagic-ipa.sh ios-unsigned my-branch
#   bash scripts/codemagic-ipa.sh --build <id>    # download from a build that already ran
#
# --build is a flag rather than only the CM_BUILD_ID variable because a variable set in PowerShell
# does not reach WSL unless it is also listed in WSLENV; a flag works the same from every shell.
#
# The .ipa lands in dist/ios/, which git ignores. An .ipa does not run on Windows: it goes onto an
# iPhone. docs/ios-codemagic.md, "No paid Apple account", covers installing it.
#
# RUNS UNDER GIT BASH AND UNDER WSL. Typing `bash` in PowerShell starts WSL, not Git Bash: Windows
# puts its own bash.exe in System32, ahead of Git's on the PATH. The two differ in exactly the ways
# that matter here, so both are handled:
#   - home directory: Git Bash's $HOME is the Windows profile; WSL's is /home/<linux user>, and the
#     Linux user name need not match the Windows one. Under WSL the Windows profile is asked for
#     through interop and checked as well.
#   - JSON: WSL Ubuntu has no node. Python 3 exists in both, so it does the parsing.
#
# THE API TOKEN NEVER APPEARS IN A COMMAND LINE OR IN OUTPUT. It is read from the environment
# variable CM_API_TOKEN if set, otherwise from a file named .codemagic-token in your home
# directory (on Windows, C:\Users\<you>\.codemagic-token), which you create yourself and which
# lives outside this repository. It reaches curl on standard input through `curl -K -`, so it is
# not in any process's argument list either. Do not add `set -x` to this script: it would print it.
#
# API shapes are from Codemagic's own OpenAPI schema (https://codemagic.io/api/v3/schema/openapi.json)
# and its REST docs, read on 2026-09-22:
#   start a build   POST https://api.codemagic.io/builds   {appId, workflowId, branch} -> buildId
#   build status    GET  https://codemagic.io/api/v3/builds/{id} -> data.status, data.artifacts[]
#   list apps       GET  https://codemagic.io/api/v3/user/apps   -> data[].id, data[].name
# Each artifact carries a short_lived_download_url, so nothing long-lived is ever created.

set -euo pipefail

BUILD_ARG=""
if [ "${1:-}" = "--build" ]; then
  BUILD_ARG="${2:-}"
  if [ -z "$BUILD_ARG" ]; then echo "Usage: bash scripts/codemagic-ipa.sh --build <build id>"; exit 1; fi
  shift 2
fi

WORKFLOW="${1:-ios-unsigned}"
BRANCH="${2:-main}"
APP_NAME="${CM_APP_NAME:-hostelpro}"
OUT_DIR="dist/ios"
POLL_SECONDS=30
MAX_WAIT_MINUTES=75

cd "$(dirname "$0")/.."

is_wsl() { [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; }

# --- a Python 3 for the JSON ----------------------------------------------------------------------
# Tested by running it, not just found on the PATH: in Git Bash on Windows, `python3` is often the
# Microsoft Store placeholder, which exists, does nothing useful, and exits non-zero.
PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 &&
     "$c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
    PY="$c"; break
  fi
done
if [ -z "$PY" ]; then
  echo "Python 3 is needed and was not found (tried python3 and python)."
  is_wsl && echo "In WSL: sudo apt install python3" || echo "Install it from python.org, or run this from WSL."
  exit 1
fi

# json CODE [ARG...]: runs CODE with the parsed stdin as `j`; ARGs arrive as sys.argv[1], [2], ...
# so values are passed as data, never spliced into the source.
#   - read as bytes and decoded as UTF-8: Windows Python's default stdin encoding is not UTF-8;
#   - PYTHONIOENCODING=utf-8 for the same reason on the way out;
#   - tr -d '\r': Windows Python writes CRLF, and a CR left on an id or a URL breaks it. pipefail
#     keeps Python's own exit status.
json() {
  local code="$1"; shift
  PYTHONIOENCODING=utf-8 "$PY" -c "import json, sys
j = json.loads(sys.stdin.buffer.read().decode('utf-8'))
$code" "$@" | tr -d '\r'
}

# --- the token, without ever echoing it ------------------------------------------------------------
token_from() {
  # First line only, with surrounding whitespace and a Windows CR stripped: Notepad adds both.
  head -n 1 "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}
TOKEN="${CM_API_TOKEN:-}"
SEARCHED=("$HOME/.codemagic-token")
if is_wsl; then
  WINPROFILE="$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r' || true)"
  if [ -n "$WINPROFILE" ] && [ "$WINPROFILE" != "%USERPROFILE%" ]; then
    SEARCHED+=("$(wslpath -u "$WINPROFILE")/.codemagic-token")
  fi
fi
if [ -z "$TOKEN" ]; then
  for f in "${SEARCHED[@]}"; do
    if [ -f "$f" ]; then TOKEN="$(token_from "$f")"; [ -n "$TOKEN" ] && break; fi
  done
fi
if [ -z "$TOKEN" ]; then
  echo "No Codemagic API token found. Looked for:"
  printf '  %s\n' "${SEARCHED[@]}"
  echo "Create one of those files containing only the token, then run this again."
  echo "Where to get it: Codemagic -> Teams -> Personal Account -> Integrations -> Codemagic API."
  exit 1
fi

# curl with the auth header supplied on stdin, so the token is never an argument.
cm() {
  printf 'header = "x-auth-token: %s"\n' "$TOKEN" | curl -sS --fail-with-body -K - "$@"
}

# --- which app ------------------------------------------------------------------------------------
APP_ID="${CM_APP_ID:-}"
if [ -z "$APP_ID" ]; then
  APPS="$(cm "https://codemagic.io/api/v3/user/apps?page_size=100")" || { echo "Could not list apps. Is the token right?"; exit 1; }
  APP_ID="$(printf '%s' "$APPS" | json "
want = sys.argv[1]
apps = j.get('data') or []
m = [a for a in apps if not a.get('archived') and want.lower() in (a.get('name') or '').lower()]
if len(m) == 1:
    print(m[0]['id'])
else:
    if m:
        sys.stderr.write('More than one app matches \"%s\": %s. Set CM_APP_ID.\n'
                         % (want, ', '.join('%s (%s)' % (a.get('name'), a.get('id')) for a in m)))
    else:
        sys.stderr.write('No app named like \"%s\". Apps on this account: %s. Add the repository in '
                         'Codemagic, or set CM_APP_NAME or CM_APP_ID.\n'
                         % (want, ', '.join(a.get('name') or '' for a in apps) or 'none'))
    sys.exit(3)" "$APP_NAME")" || exit 1
fi
echo "App: $APP_ID"

# --- start a build, or use the one given -----------------------------------------------------------
BUILD_ID="${BUILD_ARG:-${CM_BUILD_ID:-}}"
if [ -z "$BUILD_ID" ]; then
  BODY="$(PYTHONIOENCODING=utf-8 "$PY" -c 'import json, sys; print(json.dumps({"appId": sys.argv[1], "workflowId": sys.argv[2], "branch": sys.argv[3]}))' "$APP_ID" "$WORKFLOW" "$BRANCH" | tr -d '\r')"
  START="$(cm -X POST -H "Content-Type: application/json" -d "$BODY" "https://api.codemagic.io/builds")" || {
    echo "Codemagic refused to start the build:"; printf '%s\n' "$START"; exit 1; }
  BUILD_ID="$(printf '%s' "$START" | json "print(j['buildId'])")"
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
  STATUS="$(printf '%s' "$INFO" | json "print(j['data']['status'])")"
  [ "$STATUS" != "$LAST" ] && { echo "$(date +%H:%M:%S)  $STATUS"; LAST="$STATUS"; }
  case "$STATUS" in
    finished) break ;;
    failed|canceled|timeout|skipped)
      echo "Build ended as '$STATUS'. The log is at the link above; the first failing step names the cause."
      exit 2 ;;
  esac
  if [ "$(date +%s)" -gt "$DEADLINE" ]; then
    echo "Still '$STATUS' after $MAX_WAIT_MINUTES minutes. It may still finish: run again with: bash scripts/codemagic-ipa.sh --build $BUILD_ID"
    exit 4
  fi
  sleep "$POLL_SECONDS"
done

# --- download every .ipa ---------------------------------------------------------------------------
mkdir -p "$OUT_DIR"
# One line per ipa: name<TAB>size<TAB>url. The URL is used below and never printed.
LIST="$(printf '%s' "$INFO" | json "
for a in (j['data'].get('artifacts') or []):
    if a.get('type') == 'ipa':
        print('\t'.join([a['name'], str(a.get('size_in_bytes') or ''), a['short_lived_download_url']]))")"
if [ -z "$LIST" ]; then
  echo "The build finished but produced no .ipa. Check the workflow's artifacts section in codemagic.yaml."
  exit 5
fi

# A fresh short-lived URL for one artifact, by name. Asked for again before each retry, because the
# URL is short-lived by design and may have expired while a slow first attempt ran.
fresh_url() {
  cm "https://codemagic.io/api/v3/builds/$BUILD_ID" | json "
for a in (j['data'].get('artifacts') or []):
    if a.get('name') == sys.argv[1]:
        print(a['short_lived_download_url'])" "$1"
}

while IFS=$'\t' read -r NAME SIZE URL; do
  DEST="$OUT_DIR/$NAME"
  PART="$DEST.part"
  echo "Downloading $NAME ($SIZE bytes) ..."
  # WRITTEN TO .part AND MOVED INTO PLACE ONLY WHEN COMPLETE. A connection that drops mid-transfer
  # must never leave a truncated file where a good .ipa was: under WSL that drop really happens
  # (seen as "curl: (56) Send failure: Broken pipe" on a download that succeeds when repeated).
  #
  # Two layers of retry. curl's own --retry-all-errors covers a blip within one URL's lifetime; the
  # outer loop fetches a new short-lived URL, since the old one may have expired. The URL is
  # pre-authorised by Codemagic, so no token goes with it, and it is never printed.
  OK=""
  for attempt in 1 2 3; do
    [ "$attempt" -gt 1 ] && { echo "  Retrying with a fresh link (attempt $attempt of 3) ..."; URL="$(fresh_url "$NAME" || true)"; }
    rm -f "$PART"
    # curl's own error line is kept: it names the failure ("(56) Send failure"), not the URL.
    if [ -n "$URL" ] && curl -sS --fail -L --retry 3 --retry-all-errors --retry-delay 3 -o "$PART" "$URL"; then
      GOT=$(wc -c < "$PART" | tr -d ' ')
      if [ -z "$SIZE" ] || [ "$GOT" = "$SIZE" ]; then OK=1; break; fi
      echo "  Got $GOT bytes, expected $SIZE."
    else
      echo "  The download was interrupted."
    fi
  done
  if [ -z "$OK" ]; then
    rm -f "$PART"
    echo "  Could not download $NAME after 3 attempts. Nothing was overwritten."
    echo "  Try again later with: bash scripts/codemagic-ipa.sh --build $BUILD_ID"
    exit 6
  fi
  mv -f "$PART" "$DEST"
  echo "  Saved $DEST"
  echo "  $GOT bytes, SHA-256 $(sha256sum "$DEST" | cut -d' ' -f1)"
done <<< "$LIST"

echo
echo "Done. To put it on an iPhone, see docs/ios-codemagic.md, section \"No paid Apple account\"."
