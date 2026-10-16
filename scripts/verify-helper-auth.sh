#!/bin/bash
# Show that the privileged helper's caller requirement accepts only the
# properly signed OpenHosts app.
#
# The helper (OpenHostsHelper/main.swift) passes this requirement to
# NSXPCConnection.setCodeSigningRequirement (macOS 13+), which checks the
# connecting process's code signature. This script evaluates that same
# requirement with codesign. It does not install the privileged helper.
#
# Usage (on a Mac):
#   scripts/verify-helper-auth.sh
#   scripts/verify-helper-auth.sh /path/to/OpenHosts.app
#   OPENHOSTS_APP=/path/to/OpenHosts.app scripts/verify-helper-auth.sh
#
# With no path, a tiny OpenHosts.app is signed with a codesigning identity
# whose name contains team id TXVGDTDY84 (Developer ID Application is
# preferred, then any other identity for that team).
#
# The script also copies a differently signed app, renames the bundle to
# OpenHosts.app, and shows that this requirement rejects it. The old check
# (executable path contains "OpenHosts.app") would have accepted that bundle.
#
#   scripts/verify-helper-auth.sh --print-requirement
# prints the requirement string and exits, including on non-Mac hosts.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SWIFT_FILE="$ROOT/OpenHostsHelper/main.swift"

EXPECTED_BUNDLE_ID="com.debuginn.OpenHosts"
EXPECTED_TEAM_ID="TXVGDTDY84"
EXPECTED_REQ="anchor apple generic and identifier \"${EXPECTED_BUNDLE_ID}\" and certificate leaf[subject.OU] = \"${EXPECTED_TEAM_ID}\""

if [ ! -f "$SWIFT_FILE" ]; then
  echo "Missing helper source: $SWIFT_FILE" >&2
  exit 1
fi

REQ=$(python3 - "$SWIFT_FILE" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r'static let requirement\s*=\s*"((?:\\.|[^"\\])*)"', text)
if not match:
    sys.stderr.write("Could not parse CallerAuthorization.requirement\n")
    sys.exit(1)
print(match.group(1).replace(r'\"', '"').replace(r'\\', '\\'))
PY
)

if [ "$REQ" != "$EXPECTED_REQ" ]; then
  echo "Helper requirement does not match the expected caller requirement." >&2
  echo "  main.swift: $REQ" >&2
  echo "  expected:   $EXPECTED_REQ" >&2
  exit 1
fi

if [ "${1:-}" = "--print-requirement" ]; then
  printf '%s\n' "$REQ"
  exit 0
fi

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Run this script on a Mac. codesign is required to accept or reject bundles." >&2
  exit 1
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/openhosts-helper-auth.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

legacy_path_would_accept() {
  case "$1" in
    *OpenHosts.app*) return 0 ;;
    *) return 1 ;;
  esac
}

requirement_accepts() {
  local target="$1"
  # A leading "=" tells codesign the argument is requirement source, not a file path.
  codesign --verify --verbose=4 --test-requirement="=${REQ}" "$target"
}

show_signature() {
  local target="$1"
  echo "----- codesign -dv --verbose=4 $(basename "$target") -----"
  codesign -dv --verbose=4 "$target" 2>&1 || true
}

make_adhoc_foreign_app() {
  local dest="$1"
  mkdir -p "$dest/Contents/MacOS"
  cat > "$dest/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ForeignApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.ForeignApp</string>
    <key>CFBundleName</key>
    <string>ForeignApp</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
</dict>
</plist>
EOF
  if ! command -v clang >/dev/null 2>&1; then
    echo "clang is required to build the differently-signed fixture." >&2
    exit 1
  fi
  printf '%s\n' 'int main(void) { return 0; }' > "$TMP/foreign.c"
  clang -o "$dest/Contents/MacOS/ForeignApp" "$TMP/foreign.c"
  codesign --force --sign - --identifier "com.example.ForeignApp" "$dest"
}

prepare_renamed_foreign_app() {
  local dest="$1"
  local staging="$TMP/foreign-staging"
  local candidate name copied
  rm -rf "$staging"
  mkdir -p "$staging"
  copied=""
  for candidate in \
    "/System/Applications/TextEdit.app" \
    "/System/Applications/Calculator.app" \
    "/System/Applications/Preview.app" \
    "/System/Applications/Utilities/Terminal.app"
  do
    if [ ! -d "$candidate" ]; then
      continue
    fi
    name=$(basename "$candidate")
    echo "Copying ${candidate} to use as a differently-signed app."
    if ditto "$candidate" "$staging/$name" && codesign --verify "$staging/$name" >/dev/null 2>&1; then
      rm -rf "$dest"
      mv "$staging/$name" "$dest"
      copied="yes"
      break
    fi
    rm -rf "$staging/$name"
  done
  if [ -z "$copied" ]; then
    echo "No system app stayed valid after copy. Building an ad-hoc signed app and renaming it."
    make_adhoc_foreign_app "$staging/Foreign.app"
    rm -rf "$dest"
    mv "$staging/Foreign.app" "$dest"
  fi
  if ! codesign --verify --verbose=2 "$dest"; then
    echo "Renamed app is not validly signed, so a rejection would not prove the requirement check." >&2
    exit 1
  fi
}

find_team_identity() {
  local team="$1"
  local line identity dev_id any
  dev_id=""
  any=""
  while IFS= read -r line; do
    identity=$(printf '%s\n' "$line" | sed -n 's/.*"\([^"]*\)".*/\1/p')
    [ -n "$identity" ] || continue
    case "$identity" in
      *"($team)")
        case "$identity" in
          "Developer ID Application:"*)
            [ -z "$dev_id" ] && dev_id=$identity
            ;;
        esac
        [ -z "$any" ] && any=$identity
        ;;
    esac
  done <<EOF
$(security find-identity -v -p codesigning 2>/dev/null || true)
EOF
  if [ -n "$dev_id" ]; then
    printf '%s\n' "$dev_id"
  elif [ -n "$any" ]; then
    printf '%s\n' "$any"
  fi
}

make_properly_signed_app() {
  local dest="$1"
  local identity
  identity=$(find_team_identity "$EXPECTED_TEAM_ID")
  if [ -z "$identity" ]; then
    echo "No codesigning identity for team ${EXPECTED_TEAM_ID} was found." >&2
    echo "Pass a signed OpenHosts.app instead:" >&2
    echo "  scripts/verify-helper-auth.sh /path/to/OpenHosts.app" >&2
    exit 1
  fi
  if ! command -v clang >/dev/null 2>&1; then
    echo "clang is required to build the properly signed fixture, or pass an existing app." >&2
    exit 1
  fi
  echo "Signing a fixture OpenHosts.app with: ${identity}"
  mkdir -p "$dest/Contents/MacOS"
  cat > "$dest/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>OpenHosts</string>
    <key>CFBundleIdentifier</key>
    <string>${EXPECTED_BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>OpenHosts</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
</dict>
</plist>
EOF
  printf '%s\n' 'int main(void) { return 0; }' > "$TMP/good.c"
  clang -o "$dest/Contents/MacOS/OpenHosts" "$TMP/good.c"
  codesign --force --sign "$identity" --identifier "$EXPECTED_BUNDLE_ID" "$dest"
}

GOOD_APP="${1:-${OPENHOSTS_APP:-}}"
if [ -n "$GOOD_APP" ] && [ ! -d "$GOOD_APP" ]; then
  echo "Not an app bundle: $GOOD_APP" >&2
  exit 1
fi

echo "Caller requirement (team ${EXPECTED_TEAM_ID}, bundle id ${EXPECTED_BUNDLE_ID}):"
echo "  ${REQ}"
echo

FAKE="$TMP/renamed/OpenHosts.app"
mkdir -p "$TMP/renamed"
prepare_renamed_foreign_app "$FAKE"

echo
echo "===== Differently-signed app renamed to OpenHosts.app ====="
echo "Path: $FAKE"
show_signature "$FAKE"
if legacy_path_would_accept "$FAKE"; then
  echo "Old path check (path contains OpenHosts.app): ACCEPT (bypass)"
else
  echo "Fixture path does not contain OpenHosts.app; the bypass demo is invalid." >&2
  exit 1
fi

fake_failed=0
if requirement_accepts "$FAKE"; then
  echo "FAIL: differently-signed app renamed OpenHosts.app was accepted."
  fake_failed=1
else
  echo "PASS: differently-signed app renamed OpenHosts.app was rejected."
fi

echo
echo "===== Properly signed OpenHosts app ====="
if [ -z "$GOOD_APP" ]; then
  GOOD_APP="$TMP/good/OpenHosts.app"
  mkdir -p "$TMP/good"
  make_properly_signed_app "$GOOD_APP"
fi

echo "Path: $GOOD_APP"
show_signature "$GOOD_APP"
if legacy_path_would_accept "$GOOD_APP"; then
  echo "Old path check (path contains OpenHosts.app): ACCEPT"
else
  echo "Old path check (path contains OpenHosts.app): would not match this path"
fi

good_accepted=0
if requirement_accepts "$GOOD_APP"; then
  echo "PASS: properly signed app was accepted."
  good_accepted=1
else
  echo "FAIL: properly signed app was rejected."
  echo "It must be signed with identifier ${EXPECTED_BUNDLE_ID} and Team ID ${EXPECTED_TEAM_ID}."
fi

echo
if [ "$fake_failed" -eq 0 ] && [ "$good_accepted" -eq 1 ]; then
  echo "RESULT: differently-signed OpenHosts.app rejected; properly signed app accepted."
  exit 0
fi

echo "RESULT: helper caller check did not match the expected accept/reject behavior."
exit 1
