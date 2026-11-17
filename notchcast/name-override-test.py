#!/usr/bin/env python3
"""name-override.py renames a fake bundle per channel, keeps the allowlist, and its check catches an unpatched one."""
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SOURCE = Path(__file__).with_name("name-override.py")
DIALOG = "An app or web page asked Tinycast to run this. Allow only links you trust."
RETRY = "Notchcast will try again."
CHANNELS = [
    ("Notchcast", "app.notchcast", "Notchcast"),
    ("Notchcast Dev", "app.notchcast.dev", "Notchcast Dev"),
    ("Notchcast Dev", "app.notchcast.dev.g818", "Notchcast Dev g818"),
    ("Notchcast Dev", "app.notchcast.dev.a+b(1)", "Notchcast Dev a+b(1)"),
    ("Notchcast Dev", "org.example.tester", "Notchcast Dev tester"),
]


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Xcode's shape: UTF-16 bytes under a UTF-8 declaration.
    path.write_bytes(plistlib.dumps(data).decode().encode("utf-16"))


def read(path):
    return plistlib.loads(path.read_bytes().decode("utf-16" if path.read_bytes()[:2] == b"\xff\xfe" else "utf-8").encode())


def catalog(path, keys):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Key-only entries: Xcode ships none of them in the en table.
    path.write_text(json.dumps({"sourceLanguage": "en", "strings": {key: {} for key in keys}}))


def phase_env(app, **build):
    return dict(os.environ, TARGET_BUILD_DIR=str(app.parent), WRAPPER_NAME=app.name, DERIVED_FILE_DIR=str(app.parent),
                **build)


def snapshot(app):
    return {path: path.read_bytes() for path in sorted(app.rglob("*")) if path.is_file()}


def run(*args, env=None):
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, env=env)


with tempfile.TemporaryDirectory() as temp:
    SCRIPT = Path(temp) / "source/notchcast/name-override.py"
    SCRIPT.parent.mkdir(parents=True)
    shutil.copy(SOURCE, SCRIPT)
    tinycast = SCRIPT.parent.parent / "Tinycast"
    catalog(tinycast / "Resources/Localizable.xcstrings", ["About Tinycast", "Quit Tinycast", DIALOG, "Support Tinycast"])
    catalog(tinycast / "Resources/InfoPlist.xcstrings", [])
    catalog(tinycast / "Resources/Notchcast.xcstrings", ["Notchcast"])
    catalog(tinycast / "Features/Notchcast/Retry/NotchcastRetry.xcstrings", [RETRY])
    # A catalog upstream adds later: its key-only strings must be renamed in every channel.
    catalog(tinycast / "Features/Extra/Extra.xcstrings", ["Tinycast broke"])

    app = Path(temp) / "Notchcast Dev.app"
    resources = app / "Contents/Resources"
    write(app / "Contents/Info.plist", {
        "NSCameraUsageDescription": "Tinycast shows a camera preview.",
        "NSHumanReadableCopyright": "Tinycast",
        "TinycastURLScheme": "notchcast",
    })
    write(resources / "en.lproj/Localizable.strings", {"Support Tinycast": "Support Tinycast"})
    write(resources / "de.lproj/Localizable.strings", {"About Tinycast": "Über Tinycast"})
    write(resources / "en.lproj/InfoPlist.strings", {"NSCameraUsageDescription": "Tinycast shows a camera preview."})

    unpatched = run("--verify", str(app))
    assert unpatched.returncode == 1 and "did not run" in unpatched.stderr, unpatched.stderr

    env = dict(os.environ, TARGET_BUILD_DIR=temp, WRAPPER_NAME=app.name, DERIVED_FILE_DIR=temp)
    phase = run(env=env)
    assert phase.returncode == 0, phase.stderr
    assert "entries renamed Tinycast -> Notchcast" in phase.stdout, phase.stdout

    info = read(app / "Contents/Info.plist")
    assert info["NSCameraUsageDescription"] == "Notchcast shows a camera preview.", info
    assert info["NSHumanReadableCopyright"] == "Notchcast", info
    assert info["TinycastURLScheme"] == "notchcast", "keys must keep their upstream spelling"
    english = read(resources / "en.lproj/Localizable.strings")
    assert english["About Tinycast"] == "About Notchcast", "key-only catalog string was not added"
    assert english["Support Tinycast"] == "Support Tinycast", "allowlisted credit was renamed"
    assert read(resources / "de.lproj/Localizable.strings")["About Tinycast"] == "Über Notchcast"
    assert run("--verify", str(app)).returncode == 0

    rerun = run(env=env)
    assert rerun.stdout == phase.stdout, "a rerun must count the same entries"

    def embed(name):
        helper = app / f"Contents/Helpers/{name}.app"
        write(helper / "Contents/Info.plist", {"CFBundleName": name, "CFBundleExecutable": name})
        (helper / f"Contents/MacOS/{name}").parent.mkdir(parents=True)
        (helper / f"Contents/MacOS/{name}").touch()
        return helper

    embed("Tinycast Dev Dictation")
    stale = run("--verify", str(app))
    assert stale.returncode == 1, "a helper still named Tinycast passed --verify"
    for part in ["Tinycast Dev Dictation.app still", "MacOS/Tinycast Dev Dictation still", "'CFBundleName'"]:
        assert part in stale.stderr, stale.stderr
    shutil.rmtree(app / "Contents/Helpers")
    embed("tinycast")
    assert run("--verify", str(app)).returncode == 1, "a lower-case tinycast helper passed --verify"
    shutil.rmtree(app / "Contents/Helpers")
    outer = embed("Notchcast Dev Dictation")
    inner = outer / "Contents/Helpers/Inner.app/Contents/Info.plist"
    write(inner, {"CFBundleDisplayName": "Tinycast Dictation"})
    nested = run("--verify", str(app))
    assert nested.returncode == 1 and "'CFBundleDisplayName'" in nested.stderr, nested.stderr
    shutil.rmtree(outer / "Contents/Helpers")
    assert run("--verify", str(app)).returncode == 0
    write(outer / "Contents/Info.plist", {"CFBundleName": "Notchcast Dev Dictation",
                                          "CFBundleIdentifier": "com.tinycast.app.v2scene.dictation"})
    kept = run("--verify", str(app))
    assert kept.returncode == 0, f"a com.tinycast.* helper identifier must stay: {kept.stderr}"

    for product, bundle_id, expected in CHANNELS:
        app = Path(temp) / bundle_id / f"{product}.app"
        english = app / "Contents/Resources/en.lproj"
        write(app / "Contents/Info.plist", {"CFBundleName": product, "CFBundleExecutable": product,
                                            "CFBundleIdentifier": bundle_id})
        write(english / "Localizable.strings", {"Quit Tinycast": "Quit Tinycast"})
        write(english / "InfoPlist.strings", {})
        write(english / "Notchcast.strings", {"Notchcast": "Notchcast"})
        env = phase_env(app, PRODUCT_NAME=product, PRODUCT_BUNDLE_IDENTIFIER=bundle_id)
        first = run(env=env)
        assert first.returncode == 0, f"{bundle_id}: {first.stderr}"
        built = snapshot(app)
        second = run(env=env)
        assert second.stdout == first.stdout and snapshot(app) == built, f"{bundle_id}: a rerun changed the bundle"
        assert run("--name", product, bundle_id).stdout.strip() == expected, bundle_id

        info = read(app / "Contents/Info.plist")
        assert info["CFBundleDisplayName"] == expected, f"{bundle_id}: {info}"
        assert info["CFBundleExecutable"] == product, f"{bundle_id}: the executable must not follow the name"
        table = read(english / "Localizable.strings")
        assert table[DIALOG] == DIALOG.replace("Tinycast", expected), f"{bundle_id}: {table.get(DIALOG)}"
        assert table["Quit Tinycast"] == f"Quit {expected}", f"{bundle_id}: {table['Quit Tinycast']}"
        retry = english / "NotchcastRetry.strings"
        renamed = None if expected == "Notchcast" else RETRY.replace("Notchcast", expected)
        assert (read(retry) if retry.exists() else {}).get(RETRY) == renamed, f"{bundle_id}: fork catalog"
        assert read(english / "Notchcast.strings") == {"Notchcast": "Notchcast"}, f"{bundle_id}: module category"
        extra = english / "Extra.strings"
        assert read(extra)["Tinycast broke"] == f"{expected} broke", f"{bundle_id}: new upstream catalog"
        verified = run("--verify", str(app))
        assert verified.returncode == 0 and verified.stdout.strip().endswith(f"says {expected}"), verified.stderr

        write(extra, {})
        unrenamed = run("--verify", str(app))
        assert unrenamed.returncode == 1 and "'Tinycast broke'" in unrenamed.stderr, f"{bundle_id}: {unrenamed.stderr}"

print("name-override-test: PASS")
