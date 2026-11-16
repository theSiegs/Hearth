"""Regenerates Hearth's starter list of app categories (custom_components/hearth/categories_data/starter.json).

The starter list is what Hearth knows about apps before any lookup (categories.py): the confirmed answers of the
retired App Facts catalog (every shard: Android packages, Microsoft Store, Xbox, Windows package families, Steam,
Switch and played-title names), its hand overrides (an override that says "none of the ten" is kept as an explicit
no-category answer, so no store lookup second-guesses it), the System screens set, and Hearth's own additions below
(parental-control apps and big games the catalog lacked).

    python tool/categories_starter.py --catalog <app-facts checkout> [--out <starter.json>]

It reads the checkout's sources through the checkout's own tools/check_catalog.py (the same resolution the catalog
published with), so it needs nothing but Python 3. Only public facts go in: store ids, app names as the stores show
them, and categories. Never a household's apps.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import subprocess
import sys

FORMAT = "hearth.starter/1"
# What Hearth reads (categories.py): the ten categories, System screens, and the finer details
CATEGORIES = ("game", "video", "audio", "image", "social", "messaging", "news", "maps", "productivity",
              "accessibility", "interface")
DETAILS = {"youtube": "video", "streaming": "video", "education": "productivity", "companion": "productivity",
           "system": "productivity"}
NAME_MAX = 60
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "custom_components", "hearth", "categories_data",
                   "starter.json")

# Hearth's own additions: they win over the catalog's answer for the same key
EXTRAS = {
    # Parental controls: never a game, never a pool (the system detail goes to Other by default)
    "android:com.google.android.apps.kids.familylink": {"category": "productivity", "detail": "system",
                                                        "name": "Google Family Link"},
    "android:com.google.android.apps.kids.familylinkhelper": {"category": "productivity", "detail": "system",
                                                              "name": "Family Link parental controls"},
    "android:com.microsoft.familysafety": {"category": "productivity", "detail": "system",
                                           "name": "Microsoft Family Safety"},
    "android:com.microsoft.xboxfamily": {"category": "productivity", "detail": "system",
                                         "name": "Xbox Family Settings"},
    "android:com.nintendo.znma": {"category": "productivity", "detail": "system",
                                  "name": "Nintendo Switch Parental Controls"},
    # Big games the catalog's seed list missed
    "android:com.kitkagames.fallbuddies": {"category": "game", "name": "Stumble Guys"},
    "android:com.robtopx.geometryjump": {"category": "game", "name": "Geometry Dash"},
    "android:com.robtopx.geometryjumplite": {"category": "game", "name": "Geometry Dash Lite"},
    "android:com.mojang.minecrafttrialpe": {"category": "game", "app": "minecraft", "name": "Minecraft Trial"},
    "android:com.ea.gp.fifamobile": {"category": "game", "name": "EA SPORTS FC Mobile"},
    "android:com.supercell.hayday": {"category": "game", "name": "Hay Day"},
    "android:com.supercell.squad": {"category": "game", "name": "Squad Busters"},
    "android:com.king.candycrushsodasaga": {"category": "game", "name": "Candy Crush Soda Saga"},
    "android:com.playrix.homescapes": {"category": "game", "name": "Homescapes"},
    "android:com.playrix.gardenscapes": {"category": "game", "name": "Gardenscapes"},
}
# Left out: an app that reached the catalog from one household's samples rather than a generic list (a local school
# bus app); a store lookup answers for it when a kid uses it
DROP = frozenset({"android:com.buswhere.schools"})


def _clean(entry: dict) -> dict | None:
    """One starter entry from a published one: its category and detail when Hearth knows them, its name, its app
    slug. None when it says nothing Hearth reads."""
    category = entry.get("category")
    detail = entry.get("detail") if entry.get("detail") in DETAILS else None
    if category not in CATEGORIES:
        category = None
    if category is None and detail is None:
        return None
    if category is None:
        category = DETAILS[detail]
    out = {"category": category}
    if detail:
        out["detail"] = detail
    if isinstance(entry.get("app"), str):
        out["app"] = entry["app"]
    if isinstance(entry.get("name"), str) and entry["name"].strip():
        out["name"] = " ".join(entry["name"].split())[:NAME_MAX]
    return out


def build(catalog: str) -> tuple[dict, dict]:
    """(keys, counts) from the catalog checkout at [catalog]."""
    sys.path.insert(0, os.path.join(catalog, "tools"))
    import check_catalog  # noqa: PLC0415 - the checkout's own module

    src = check_catalog.load(catalog)
    shards = check_catalog.published(src)
    keys: dict[str, dict] = {}
    counts: dict[str, int] = {}
    for shard, entries in shards.items():
        for key, entry in entries.items():
            if entry.get("state") != "confirmed" or key in DROP:
                continue
            if (clean := _clean(entry)) is not None:
                keys[key] = clean
                counts[f"confirmed:{shard}"] = counts.get(f"confirmed:{shard}", 0) + 1
    # Hand overrides that say an app is none of the ten (a browser, an airline): kept as an explicit no-category
    # answer, so a store's genre never second-guesses the owner's call
    for package, override in src["android_overrides"].items():
        category = override if isinstance(override, str) else (override or {}).get("category")
        key = f"android:{package}"
        if category == "unknown" and key not in keys and key not in DROP:
            entry = {"category": None}
            name = (shards.get("android", {}).get(key) or {}).get("name")
            if isinstance(name, str) and name.strip():
                entry["name"] = " ".join(name.split())[:NAME_MAX]
            keys[key] = entry
            counts["none-by-override"] = counts.get("none-by-override", 0) + 1
    counts["hand-overrides-read"] = len(src["android_overrides"]) + len(src["overrides"])
    for key, entry in EXTRAS.items():
        counts["hearth-extras" if key not in keys else "hearth-extras-replacing"] = (
            counts.get("hearth-extras" if key not in keys else "hearth-extras-replacing", 0) + 1)
        keys[key] = dict(entry)
    # An app slug only where it links two keys or more (the lookup goes through it); else it says nothing
    by_app: dict[str, int] = {}
    for entry in keys.values():
        if "app" in entry:
            by_app[entry["app"]] = by_app.get(entry["app"], 0) + 1
    for entry in keys.values():
        if "app" in entry and by_app[entry["app"]] < 2:
            del entry["app"]
    counts["interface"] = sum(1 for e in keys.values() if e.get("category") == "interface")
    counts["total"] = len(keys)
    return keys, counts


def dump(keys: dict, source: str) -> str:
    """The file's text: one key per line, sorted, so a diff is one line per app."""
    lines = [f"    {json.dumps(k)}: {json.dumps(keys[k], separators=(', ', ': '), sort_keys=True)}" for k in sorted(keys)]
    head = {"format": FORMAT, "generated": datetime.date.today().isoformat(), "source": source}
    return ("{\n" + "".join(f'  {json.dumps(k)}: {json.dumps(v)},\n' for k, v in head.items())
            + '  "keys": {\n' + ",\n".join(lines) + "\n  }\n}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--catalog", required=True, help="a local checkout of the app-facts repository")
    parser.add_argument("--out", default=OUT)
    args = parser.parse_args()
    keys, counts = build(args.catalog)
    try:
        commit = subprocess.run(["git", "-C", args.catalog, "rev-parse", "--short", "HEAD"], capture_output=True,
                                text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        commit = "unknown"
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(dump(keys, f"app-facts {commit} and Hearth's additions"))
    for name in sorted(counts):
        print(f"{name}: {counts[name]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
