"""The Home Assistant integration's version: custom_components/hearth/manifest.json is the one place it is kept.

    python3 .github/scripts/integration_version.py                    # check: the manifest has a CalVer version (CI)
    python3 .github/scripts/integration_version.py --tag v2026.12.01  # and the tag is that version (the release)
    python3 .github/scripts/integration_version.py --notes v2026.12.01  # the CHANGELOG.md section for the release

The version is date-style CalVer, YYYY.MM.NN (2026.12.01), raised by hand in the manifest with a CHANGELOG.md section
of the same name. Hearth TV, the TV app, has its own version in theSiegs/HearthTV; the two no longer move together.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
MANIFEST = ROOT / "custom_components" / "hearth" / "manifest.json"
CHANGELOG = ROOT / "CHANGELOG.md"
CALVER = re.compile(r"^\d{4}\.\d{2}\.\d{2,}$")


def manifest_version():
    version = json.loads(MANIFEST.read_text(encoding="utf-8")).get("version")
    if not isinstance(version, str) or not CALVER.match(version):
        sys.exit(f"custom_components/hearth/manifest.json: version {version!r} isn't YYYY.MM.NN")
    return version


def notes(tag):
    """The CHANGELOG.md section headed with the tag's version, or a line pointing at the file."""
    version = tag.removeprefix("v")
    text = CHANGELOG.read_text(encoding="utf-8") if CHANGELOG.exists() else ""
    match = re.search(rf"^## {re.escape(version)}\s*$(.*?)(?=^## |\Z)", text, re.MULTILINE | re.DOTALL)
    body = match.group(1).strip() if match else "See CHANGELOG.md."
    return body + "\n\nInstall or update with HACS. Hearth TV, the TV app, is released from https://github.com/theSiegs/HearthTV.\n"


def main():
    args = sys.argv[1:]
    if args[:1] == ["--notes"] and len(args) == 2:
        sys.stdout.write(notes(args[1]))
        return
    version = manifest_version()
    if args[:1] == ["--tag"] and len(args) == 2:
        tag_version = args[1].removeprefix("v").split("-")[0]
        if tag_version != version:
            sys.exit(f"tag {args[1]} isn't the manifest's version {version}")
    print(f"integration version {version}")


if __name__ == "__main__":
    main()
