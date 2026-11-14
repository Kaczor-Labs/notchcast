#!/usr/bin/env python3
"""Vendor selected library modules from an immutable engine commit, without modifying it."""
import argparse
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

UNSUPPORTED = ("exclude", "resources", "settings", "path", "sources", "pluginUsages")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkout", type=Path)
    parser.add_argument("commit")
    parser.add_argument("modules", nargs="*", default=["IslandCore", "IslandUI"])
    parser.add_argument("--check", action="store_true", help="compare without writing")
    args = parser.parse_args()
    if not args.modules or len(set(args.modules)) != len(args.modules):
        parser.error("provide distinct library module names")
    modules = sorted(args.modules)

    def git(*command):
        return subprocess.check_output(["git", "-C", str(args.checkout), *command])

    commit = git("rev-parse", "--verify", "--end-of-options", args.commit + "^{commit}").decode().strip()
    with tempfile.TemporaryDirectory(prefix="island-manifest-") as scratch:
        Path(scratch, "Package.swift").write_bytes(git("show", f"{commit}:Package.swift"))
        package = json.loads(subprocess.check_output(
            ["swift", "package", "dump-package", "--package-path", scratch]))
    targets = {target["name"]: target for target in package["targets"]}
    products = []
    declarations = []
    expected = {}
    for module in modules:
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*", module):
            parser.error("invalid module name")
        target = targets.get(module)
        if target is None or target["type"] != "regular":
            parser.error(f"not a library target: {module}")
        unsupported = [key for key in UNSUPPORTED if target.get(key)]
        if unsupported:
            parser.error(f"{module} uses {', '.join(unsupported)}, which the vendored manifest would drop")
        dependencies = []
        for dependency in target["dependencies"]:
            name = dependency.get("byName", dependency.get("target", [None]))[0]
            if name not in modules:
                parser.error(f"{module} requires module {name}; include it in the list")
            dependencies.append(name)
        products.append(f'        .library(name: "{module}", targets: ["{module}"]),')
        names = ", ".join(json.dumps(name) for name in dependencies)
        declarations.append(f'        .target(name: "{module}", dependencies: [{names}]),')
        prefix = f"Sources/{module}/"
        entries = git("ls-tree", "-rz", commit, "--", prefix).split(b"\0")
        count = 0
        for entry in filter(None, entries):
            metadata, path = entry.decode().split("\t", 1)
            if metadata.split()[0] not in ("100644", "100755"):
                parser.error(f"non-regular source: {path}")
            expected[path] = git("show", f"{commit}:{path}")
            count += 1
        if not count:
            parser.error(f"no sources for {module}")
    manifest = '\n'.join([
        '// swift-tools-version: 6.2', 'import PackageDescription', '',
        'let package = Package(', '    name: "IslandEngine",',
        '    platforms: [.macOS(.v26)],', '    products: [', *products,
        '    ],', '    targets: [', *declarations, '    ],',
        '    swiftLanguageModes: [.v6]', ')', '',
    ])
    expected["Package.swift"] = manifest.encode()
    expected["LICENSE"] = git("show", f"{commit}:LICENSE")
    trees = [f"{module} {git('rev-parse', f'{commit}:Sources/{module}').decode().strip()}\n" for module in modules]
    expected["REVISION"] = "".join([commit + "\n", *trees]).encode()
    destination = Path(__file__).resolve().parent / "vendor/IslandEngine"
    if args.check:
        actual = {str(path.relative_to(destination)): path.read_bytes()
                  for path in destination.rglob("*") if path.is_file()}
        if actual != expected:
            parser.exit(1, "FAIL: vendored tree differs from pinned sources\n")
        print(f"PASS: {len(expected) - 3} source files match {commit}")
        return
    destination.mkdir(parents=True, exist_ok=True)
    for path in sorted(destination.rglob("*"), reverse=True):
        if path.is_file() and str(path.relative_to(destination)) not in expected:
            path.unlink()
        elif path.is_dir() and not any(path.iterdir()):
            path.rmdir()
    for name, content in expected.items():
        path = destination / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    print(f"Vendored {', '.join(modules)} at {commit}")


if __name__ == "__main__":
    main()
