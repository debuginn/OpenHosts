#!/bin/bash
# Xcode Cloud post-clone hook for the Mac App Store archive.
#
# The committed Xcode project is the build input. This script does not install
# Homebrew or xcodegen. GitHub Actions still builds the Developer ID app.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="OpenHosts.xcodeproj/xcshareddata/xcschemes/OpenHostsAppStore.xcscheme"
RESOLVED="OpenHosts.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
PROJECT="OpenHosts.xcodeproj/project.pbxproj"
SPEC="project.yml"

for path in "$SCHEME" "$RESOLVED" "$PROJECT" "$SPEC"; do
  if [ ! -f "$path" ]; then
    echo "ci_post_clone: missing $path" >&2
    exit 1
  fi
done

python3 - "$SCHEME" "$RESOLVED" "$PROJECT" "$SPEC" <<'PY'
import json
import sys
import xml.etree.ElementTree as ET

scheme, resolved, project, spec = sys.argv[1:5]

archive = ET.parse(scheme).getroot().find("ArchiveAction")
if archive is None or archive.get("buildConfiguration") != "Release":
    sys.exit("OpenHostsAppStore scheme Archive action must use Release")
print("OpenHostsAppStore Archive configuration: Release")

data = json.load(open(resolved, encoding="utf-8"))
sparkle = next((pin for pin in data.get("pins", []) if pin.get("identity") == "sparkle"), None)
if sparkle is None:
    sys.exit("Package.resolved does not pin Sparkle")
state = sparkle.get("state") or {}
version = state.get("version") or ""
revision = state.get("revision") or ""
parts = version.split(".")
if len(parts) < 2 or not all(part.isdigit() for part in parts[:2]):
    sys.exit(f"Sparkle pin {version!r} is not a numeric version")
major, minor = int(parts[0]), int(parts[1])
# project.yml: from 2.6.0, which is up to the next major version.
if major != 2 or minor < 6:
    sys.exit(f"Sparkle pin {version} does not satisfy from: 2.6.0")
if not revision:
    sys.exit("Sparkle pin is missing a revision")
print(f"Sparkle pin: {version} ({revision})")

pbx = open(project, encoding="utf-8").read()
yml = open(spec, encoding="utf-8").read()
checks = [
    ("OpenHostsAppStore", pbx, "project is missing the OpenHostsAppStore target"),
    ("OpenHostsAppStore:", yml, "project.yml is missing the OpenHostsAppStore target"),
    ("SWIFT_ACTIVE_COMPILATION_CONDITIONS = APPSTORE", pbx, "APPSTORE flag missing from the Xcode project"),
    ("SWIFT_ACTIVE_COMPILATION_CONDITIONS: APPSTORE", yml, "APPSTORE flag missing from project.yml"),
    ("OpenHosts/OpenHostsAppStore.entitlements", pbx, "App Store entitlements missing from the Xcode project"),
    ("OpenHosts/OpenHostsAppStore.entitlements", yml, "App Store entitlements missing from project.yml"),
    ("https://github.com/sparkle-project/Sparkle", pbx, "Developer ID Sparkle package reference is missing"),
    ("package: Sparkle", yml, "project.yml no longer declares Sparkle"),
]
for needle, haystack, message in checks:
    if needle not in haystack:
        sys.exit(message)

# The App Store target must not link Sparkle. Its package product list is only SharedKit.
app_store = pbx.split("name = OpenHostsAppStore;", 1)
if len(app_store) != 2:
    sys.exit("could not find the OpenHostsAppStore native target")
target_body = app_store[1].split("name = ", 1)[0]
if "Sparkle" in target_body:
    sys.exit("OpenHostsAppStore target links Sparkle")
print("Committed App Store target matches project.yml (no xcodegen).")
PY

echo "ci_post_clone: using the committed Xcode project."
