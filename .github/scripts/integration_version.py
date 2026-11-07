"""Keeps the Home Assistant integration's version equal to the release version in pubspec.yaml.

    python3 .github/scripts/integration_version.py           # check: fails when they differ (CI and release run this)
    python3 .github/scripts/integration_version.py --write   # set custom_components/hearth/manifest.json from pubspec

The version is the pubspec name without the build number: 2026.11.08+8333 gives 2026.11.08.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
PUBSPEC = ROOT / "pubspec.yaml"
MANIFEST = ROOT / "custom_components" / "hearth" / "manifest.json"


def pubspec_version():
    match = re.search(r"^version:\s*([^\s+]+)", PUBSPEC.read_text(encoding="utf-8"), re.MULTILINE)
    if not match:
        sys.exit("pubspec.yaml has no version")
    return match.group(1)


def main():
    version = pubspec_version()
    text = MANIFEST.read_text(encoding="utf-8")
    current = json.loads(text).get("version")
    if "--write" in sys.argv[1:]:
        if current != version:
            # Only the version line changes, so the rest of the file keeps its layout.
            text = re.sub(r'("version":\s*")[^"]*(")', rf"\g<1>{version}\g<2>", text, count=1)
            MANIFEST.write_text(text, encoding="utf-8", newline="\n")
        print(f"manifest.json version {version}")
        return
    if current != version:
        sys.exit(
            f"custom_components/hearth/manifest.json has version {current}, pubspec.yaml {version}: "
            "run python3 .github/scripts/integration_version.py --write"
        )
    print(f"versions match: {version}")


if __name__ == "__main__":
    main()
