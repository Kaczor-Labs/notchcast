#!/usr/bin/env python3
"""Exercise immutable source selection and dependency validation with a private fixture repo."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


with tempfile.TemporaryDirectory(prefix="island-sync-test-") as temporary:
    root = Path(temporary)
    engine = root / "engine"
    engine.mkdir()
    script = root / "fork/sync-island-engine.py"
    script.parent.mkdir()
    shutil.copyfile(Path(__file__).with_name("sync-island-engine.py"), script)

    def git(*arguments):
        return subprocess.check_output(["git", "-C", str(engine), *arguments], stderr=subprocess.PIPE).decode().strip()

    git("init", "-q")
    (engine / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "Fixture", targets: [
    .target(name: "IslandCore"),
    .target(name: "IslandUI", dependencies: ["IslandCore"]),
])
''')
    for module in ("IslandCore", "IslandUI"):
        source = engine / f"Sources/{module}/Value.swift"
        source.parent.mkdir(parents=True)
        source.write_text("public let value = 42\n")
    (engine / "Tests").mkdir()
    (engine / "Tests/secret.txt").write_text("excluded fixture\n")
    git("add", ".")
    git("-c", "user.name=Damian", "-c", "user.email=336236323+kaczordodgers@users.noreply.github.com",
        "commit", "-qm", "Fixture")
    commit = git("rev-parse", "HEAD")
    (engine / "Sources/IslandCore/Value.swift").write_text("uncommitted changes\n")

    def sync(*arguments):
        return subprocess.run([sys.executable, str(script), str(engine), commit, *arguments],
                              capture_output=True, text=True, env=os.environ)

    assert sync().returncode == 0
    vendor = script.parent / "vendor/IslandEngine"
    assert (vendor / "Sources/IslandCore/Value.swift").read_text() == "public let value = 42\n"
    assert (vendor / "REVISION").read_text() == commit + "\n"
    assert not (vendor / "Tests").exists()
    assert sync("--check").returncode == 0
    assert sync("IslandUI").returncode != 0
    assert sync("Missing").returncode != 0
    assert sync("--check").returncode == 0
    (vendor / "stale.swift").write_text("stale\n")
    assert sync("--check").returncode != 0
    assert sync().returncode == 0
    assert sync().returncode == 0
    assert sync("--check").returncode == 0
    print("PASS: immutable sync, source-only copy, dependency validation, stale removal, repeatability")
