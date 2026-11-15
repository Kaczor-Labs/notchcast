#!/usr/bin/env python3
"""Rename the built app to Notchcast: patch every compiled table and Info.plist after resources copy.

No arguments: the Tinycast target's build phase (project.yml). `--verify <app>`: fail unless patched.
"""
import json
import os
import plistlib
import sys
from pathlib import Path

OLD, NEW = "Tinycast", "Notchcast"
ROOT = Path(__file__).resolve().parent.parent
# Keep in step with the phase's inputFiles in project.yml, so a catalog edit reruns the phase.
CATALOGS = ["Localizable", "InfoPlist"]
FORK_TABLE = "Notchcast"
# Strings that keep the upstream name on purpose; anything else saying it fails the build.
ALLOWLIST = {
    "Support Tinycast": "credit: the menu row opens upstream's sponsor page",
    "Join the Tinycast community": "credit: About's community link is upstream's Discord",
}
# Proof the phase ran: upstream's About row, present in every build.
WITNESS = ("Localizable", "About Tinycast", "About Notchcast")


def rename(value):
    if isinstance(value, str):
        return value.replace(OLD, NEW)
    if isinstance(value, dict):
        return {key: rename(item) for key, item in value.items()}
    if isinstance(value, list):
        return [rename(item) for item in value]
    return value


def source_values(name):
    # Xcode leaves an English value out of the compiled table when it equals its key.
    catalog = json.loads((ROOT / "Tinycast/Resources" / f"{name}.xcstrings").read_text())
    values = {}
    for key, entry in catalog["strings"].items():
        english = entry.get("localizations", {}).get(catalog["sourceLanguage"], {})
        if "variations" in english or "substitutions" in english:
            continue
        values[key] = english.get("stringUnit", {}).get("value", key)
    return values


def load(path):
    data = path.read_bytes()
    # Xcode writes the tables as UTF-16 under a UTF-8 declaration, which expat refuses.
    if data[:2] in (b"\xff\xfe", b"\xfe\xff"):
        data = data.decode("utf-16").encode()
    return plistlib.loads(data)


def save(path, data):
    with path.open("wb") as handle:
        plistlib.dump(data, handle, fmt=plistlib.FMT_XML)


def patch_table(path, language, name):
    table = load(path)
    if language == "en" and path.suffix == ".strings" and name in CATALOGS:
        for key, value in source_values(name).items():
            if OLD in value and key not in table:
                table[key] = value
    for key in list(table):
        if key not in ALLOWLIST and OLD in json.dumps(table[key]):
            table[key] = rename(table[key])
    owned = 0 if name == FORK_TABLE else sum(
        NEW in json.dumps(value) for key, value in table.items() if NEW not in key)
    if name == "InfoPlist":
        # Info.plist values are renamed below, and Launch Services looks a value up by its text.
        for key in [key for key in table if OLD in key and key not in ALLOWLIST]:
            table[rename(key)] = table[key]
    save(path, table)
    return owned


def patch_info(path):
    info = load(path)
    for key, value in info.items():
        if key not in ALLOWLIST and OLD in json.dumps(value):
            info[key] = rename(value)
    save(path, info)


def tables(app):
    return sorted((app / "Contents/Resources").glob("*.lproj/*.strings*"))


def leftovers(app):
    found = []
    for path in [app / "Contents/Info.plist", *tables(app)]:
        for key, value in load(path).items():
            if key not in ALLOWLIST and OLD in json.dumps(value):
                found.append(f"{path.relative_to(app)}: {key!r} still says {OLD}")
    # A key-only string never reaches the table, so the app would show the key itself.
    for catalog in sorted((ROOT / "Tinycast/Resources").glob("*.xcstrings")):
        path = app / "Contents/Resources/en.lproj" / f"{catalog.stem}.strings"
        shipped = load(path) if path.exists() else {}
        for key, value in source_values(catalog.stem).items():
            if OLD in value and key not in ALLOWLIST and OLD in shipped.get(key, OLD):
                found.append(f"{path.relative_to(app)}: {key!r} still says {OLD}")
    return found


def helper_leftovers(app):
    paths = sorted((app / "Contents/Helpers").rglob("*"))
    found = [f"{path.relative_to(app)} still says {OLD}" for path in paths if OLD.lower() in path.name.lower()]
    for path in [path for path in paths if path.name == "Info.plist"]:
        found += [f"{path.relative_to(app)}: {key!r} still says {OLD}"
                  for key, value in load(path).items() if OLD.lower() in json.dumps(value).lower()]
    return found


def fail(lines):
    for line in lines:
        print(f"error: name-override: {line}", file=sys.stderr)
    sys.exit(1)


def check(app):
    problems = [
        f"{line}. Add its catalog to CATALOGS, or allowlist it in notchcast/name-override.py"
        for line in leftovers(app)
    ]
    problems += [
        f"{line}. Its embed phase signs it before this one runs, so rename it in project.yml"
        for line in helper_leftovers(app)
    ]
    witness = app / "Contents/Resources/en.lproj" / f"{WITNESS[0]}.strings"
    if not witness.exists() or load(witness).get(WITNESS[1]) != WITNESS[2]:
        problems.append(f"{witness.relative_to(app)} lacks {WITNESS[1]!r}: the rename phase did not run")
    if problems:
        fail(problems)


def build_phase():
    app = Path(os.environ["TARGET_BUILD_DIR"]) / os.environ["WRAPPER_NAME"]
    counts = {}
    for path in tables(app):
        language = path.parent.stem
        counts[language] = counts.get(language, 0) + patch_table(path, language, path.stem)
    patch_info(app / "Contents/Info.plist")
    if not sum(counts.values()):
        fail([f"patched no entries in {app.name}: the string tables moved or the rename is stale"])
    check(app)
    summary = ", ".join(f"{place} {count}" for place, count in sorted(counts.items()))
    print(f"name-override: {sum(counts.values())} entries renamed {OLD} -> {NEW} ({summary})")
    stamp = Path(os.environ["DERIVED_FILE_DIR"]) / "name-override.stamp"
    stamp.write_text(f"{sum(counts.values())}\n")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--verify"] and len(sys.argv) == 3:
        check(Path(sys.argv[2]))
        print(f"name-override: {sys.argv[2]} says {NEW}")
    elif len(sys.argv) == 1:
        build_phase()
    else:
        fail(["usage: name-override.py [--verify <app>]"])
