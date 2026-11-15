#!/usr/bin/env python3
"""name-override.py renames a fake bundle, keeps the allowlist, and its check catches an unpatched one."""
import os
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).with_name("name-override.py")


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Xcode's shape: UTF-16 bytes under a UTF-8 declaration.
    path.write_bytes(plistlib.dumps(data).decode().encode("utf-16"))


def read(path):
    return plistlib.loads(path.read_bytes().decode("utf-16" if path.read_bytes()[:2] == b"\xff\xfe" else "utf-8").encode())


def run(*args, env=None):
    return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, env=env)


with tempfile.TemporaryDirectory() as temp:
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

print("name-override-test: PASS")
