#!/usr/bin/env python3
"""Rename the built app: patch every compiled table and Info.plist after resources copy.

The name is `app_name(PRODUCT_NAME, PRODUCT_BUNDLE_IDENTIFIER)`: Release says Notchcast, Debug Notchcast Dev, and a
copy built with its own bundle id adds that id's suffix. It is also written to CFBundleDisplayName, which
`Bundle.appDisplayName` reads at run time.

No arguments: the Tinycast target's build phase (project.yml). `--verify <app>`: fail unless patched.
`--name <product name> <bundle id>`: print the name a build would get.
"""
import functools
import json
import os
import plistlib
import re
import sys
from pathlib import Path

OLD, NEW = "Tinycast", "Notchcast"
ROOT = Path(__file__).resolve().parent.parent
# The Settings category and the island's label name the module group, not the build, in every channel.
FORK_TABLE = "Notchcast"
CHANNELS = {"app.notchcast", "app.notchcast.dev"}
SUFFIX_PREFIXES = ("app.notchcast.dev.", "app.notchcast.")
# The executable is linked under PRODUCT_NAME; renaming its key would point Launch Services at nothing.
KEPT_INFO_KEYS = {"CFBundleExecutable", "CFBundleIdentifier"}
# Strings that keep the upstream name on purpose; anything else saying it fails the build.
ALLOWLIST = {
    "Support Tinycast": "credit: the menu row opens upstream's sponsor page",
    "Join the Tinycast community": "credit: About's community link is upstream's Discord",
}
# Proof the phase ran: upstream's About row, present in every build.
WITNESS = ("Localizable", "About Tinycast", "About Notchcast")
HELPER_NAME_KEYS = {"CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"}


def app_name(product_name, bundle_id):
    if not bundle_id or bundle_id in CHANNELS:
        return product_name
    suffix = next((bundle_id[len(prefix):] for prefix in SUFFIX_PREFIXES if bundle_id.startswith(prefix)),
                  bundle_id.rsplit(".", 1)[-1])
    return f"{product_name} {suffix}"


def spellings(name):
    # Release keeps the plain rename; others also take Notchcast and any earlier run's name, so reruns are no-ops.
    if name == NEW:
        return re.compile(OLD)
    return re.compile(rf"{re.escape(name)}|(?:{OLD}|{NEW})(?: Dev\b)?")


def rename(value, name=NEW):
    if isinstance(value, str):
        return spellings(name).sub(lambda _: name, value)
    if isinstance(value, dict):
        return {key: rename(item, name) for key, item in value.items()}
    if isinstance(value, list):
        return [rename(item, name) for item in value]
    return value


def stale(value, name):
    return rename(value, name) != value


@functools.cache
def catalog_paths():
    return {path.stem: path for path in (ROOT / "Tinycast").rglob("*.xcstrings") if path.stem != FORK_TABLE}


def source_values(name):
    # Xcode leaves an English value out of the compiled table when it equals its key.
    catalog = json.loads(catalog_paths()[name].read_text())
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


def patch_table(path, language, table_name, name):
    if table_name == FORK_TABLE:
        return 0
    table = load(path)
    if language == "en" and path.suffix == ".strings" and table_name in catalog_paths():
        for key, value in source_values(table_name).items():
            if stale(value, name) and key not in table:
                table[key] = value
    for key in list(table):
        if key not in ALLOWLIST and stale(table[key], name):
            table[key] = rename(table[key], name)
    owned = sum(name in json.dumps(value) for key, value in table.items() if name not in key)
    if table_name == "InfoPlist":
        # Info.plist values are renamed below, and Launch Services looks a value up by its text.
        for key in [key for key in table if stale(key, name) and key not in ALLOWLIST]:
            table[rename(key, name)] = table[key]
    save(path, table)
    return owned


def patch_info(path, name):
    info = load(path)
    for key, value in info.items():
        if key not in ALLOWLIST and key not in KEPT_INFO_KEYS and stale(value, name):
            info[key] = rename(value, name)
    info["CFBundleDisplayName"] = name
    save(path, info)


def tables(app):
    return sorted((app / "Contents/Resources").glob("*.lproj/*.strings*"))


def built_name(app):
    return load(app / "Contents/Info.plist").get("CFBundleDisplayName", NEW)


def leftovers(app, name):
    found = []
    for path in [app / "Contents/Info.plist", *tables(app)]:
        if path.stem == FORK_TABLE:
            continue
        for key, value in load(path).items():
            if key not in ALLOWLIST and key not in KEPT_INFO_KEYS and stale(value, name):
                found.append(f"{path.relative_to(app)}: {key!r} does not say {name}")
    # A key-only string never reaches the table, so the app would show the key itself.
    for catalog in sorted(catalog_paths()):
        path = app / "Contents/Resources/en.lproj" / f"{catalog}.strings"
        shipped = load(path) if path.exists() else {}
        for key, value in source_values(catalog).items():
            if key not in ALLOWLIST and stale(value, name) and stale(shipped.get(key, value), name):
                found.append(f"{path.relative_to(app)}: {key!r} does not say {name}")
    return found


def helper_leftovers(app):
    paths = sorted((app / "Contents/Helpers").rglob("*"))
    found = [f"{path.relative_to(app)} still says {OLD}" for path in paths if OLD.lower() in path.name.lower()]
    for path in [path for path in paths if path.name == "Info.plist"]:
        found += [f"{path.relative_to(app)}: {key!r} still says {OLD}"
                  for key, value in load(path).items() if says_old(key, json.dumps(value))]
    return found


def says_old(key, text):
    # Shown names fail in any case; identifiers such as com.tinycast.* stay, as in the main Info.plist.
    return OLD.lower() in text.lower() if key in HELPER_NAME_KEYS else OLD in text


def fail(lines):
    for line in lines:
        print(f"error: name-override: {line}", file=sys.stderr)
    sys.exit(1)


def check(app):
    name = built_name(app)
    problems = [
        f"{line}. Allowlist it in notchcast/name-override.py"
        for line in leftovers(app, name)
    ]
    problems += [
        f"{line}. Its embed phase signs it before this one runs, so rename it in project.yml"
        for line in helper_leftovers(app)
    ]
    witness = app / "Contents/Resources/en.lproj" / f"{WITNESS[0]}.strings"
    if not witness.exists() or load(witness).get(WITNESS[1]) != rename(WITNESS[2], name):
        problems.append(f"{witness.relative_to(app)} lacks {WITNESS[1]!r}: the rename phase did not run")
    if problems:
        fail(problems)


def build_phase():
    app = Path(os.environ["TARGET_BUILD_DIR"]) / os.environ["WRAPPER_NAME"]
    name = app_name(os.environ.get("PRODUCT_NAME", NEW), os.environ.get("PRODUCT_BUNDLE_IDENTIFIER", ""))
    counts = {}
    for catalog in sorted(catalog_paths()):
        # A catalog whose English is all key-only ships no en table, so its keys would show unrenamed.
        path = app / "Contents/Resources/en.lproj" / f"{catalog}.strings"
        if not path.exists() and any(stale(value, name) for value in source_values(catalog).values()):
            path.parent.mkdir(parents=True, exist_ok=True)
            save(path, {})
    for path in tables(app):
        language = path.parent.stem
        counts[language] = counts.get(language, 0) + patch_table(path, language, path.stem, name)
    patch_info(app / "Contents/Info.plist", name)
    if not sum(counts.values()):
        fail([f"patched no entries in {app.name}: the string tables moved or the rename is stale"])
    check(app)
    summary = ", ".join(f"{place} {count}" for place, count in sorted(counts.items()))
    print(f"name-override: {sum(counts.values())} entries renamed {OLD} -> {name} ({summary})")
    stamp = Path(os.environ["DERIVED_FILE_DIR"]) / "name-override.stamp"
    stamp.write_text(f"{sum(counts.values())}\n")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--verify"] and len(sys.argv) == 3:
        check(Path(sys.argv[2]))
        print(f"name-override: {sys.argv[2]} says {built_name(Path(sys.argv[2]))}")
    elif sys.argv[1:2] == ["--name"] and len(sys.argv) == 4:
        print(app_name(sys.argv[2], sys.argv[3]))
    elif len(sys.argv) == 1:
        build_phase()
    else:
        fail(["usage: name-override.py [--verify <app> | --name <product name> <bundle id>]"])
