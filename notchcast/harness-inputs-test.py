#!/usr/bin/env python3
"""Exercise harness selection and compiler inputs through the shipped scripts."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
HIDDEN = "Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift"
TAB = "Tinycast/Features/Settings/SettingsTab.swift"
EXAMPLE = "Tinycast/Features/Example/Model/Example.swift"


class HarnessInputsTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="harness-inputs-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        for folder in ("Tests", "Scripts", "notchcast", "bin", "Tinycast/Features/Example/Model",
                       "Tinycast/Features/Example/Service", str(Path(HIDDEN).parent), str(Path(TAB).parent)):
            (self.root / folder).mkdir(parents=True, exist_ok=True)
        for name in ("changed-harnesses.sh", "command-harness-sources.sh", "harness_inputs.py",
                     "test-harnesses.sh", "harness-times.py", "check-module-harness.py"):
            if (ROOT / "notchcast" / name).exists():
                shutil.copy(ROOT / "notchcast" / name, self.root / "notchcast" / name)
        (self.root / "Scripts/run-tests.sh").touch()
        (self.root / "notchcast/config.env").write_text('CI_SKIP_TESTS=""\n')
        (self.root / "bin/git").write_text(
            '#!/bin/bash\ncase "$1" in\nrev-parse) printf "%s\\n" "$FIXTURE_ROOT" ;;\n'
            'diff) if [[ " $* " == *" -z "* ]]; then printf "%s\\0" "$CHANGED"; '
            'else printf "%s\\n" "$CHANGED"; fi ;;\nesac\n')
        (self.root / "bin/git").chmod(0o755)
        self.env = {**os.environ, "PATH": f"{self.root}/bin:{os.environ['PATH']}",
                    "FIXTURE_ROOT": str(self.root), "GITHUB_ACTIONS": ""}
        self.env.pop("GITHUB_ACTIONS")
        (self.root / "Tinycast/Features/Example/Model/Example.swift").touch()
        (self.root / HIDDEN).touch()
        (self.root / TAB).touch()
        (self.root / "Tests/nc-Example-conditional-test.swift").write_text(
            f'// notchcast-sources: Tinycast/Features/Example/Model/*.swift {TAB}\n')
        (self.root / "Tests/notchcast-reader-test.swift").write_text(
            '// notchcast-sources: -parse-as-library\n// notchcast-reads: fixtures/*.txt\n')
        (self.root / "Tests/nc-Example-folder-test.swift").touch()

    def selected(self, changed):
        result = subprocess.run(["bash", "notchcast/changed-harnesses.sh", "base", "head"],
                                cwd=self.root, env={**self.env, "CHANGED": changed},
                                text=True, capture_output=True, check=True)
        print(f"{changed} selects {result.stdout.strip().replace(chr(10), ', ')}", flush=True)
        return result.stdout.splitlines()

    def test_conditional_source_selects_consumer(self):
        self.assertIn("nc-Example-conditional-test", self.selected(HIDDEN))

    def test_upstream_registration_selects_conditional_tabs_consumer(self):
        shutil.copy(ROOT / "Scripts/run-tests.sh", self.root / "Scripts/run-tests.sh")
        (self.root / "Tests/SettingsHistoryTests.swift").touch()
        self.assertIn("SettingsHistoryTests", self.selected(HIDDEN))

    def test_index_only_registration_is_never_selected(self):
        (self.root / "Scripts/run-tests.sh").write_text(
            f'run index -O IndexTests {EXAMPLE}\nrun -O index OptimizedIndexTests {EXAMPLE}\n'
            f'run slow -O RunnableTests \\\n    {EXAMPLE}\n')
        for name in ("IndexTests", "OptimizedIndexTests", "RunnableTests"):
            (self.root / f"Tests/{name}.swift").touch()
        selected = self.selected(EXAMPLE)
        self.assertIn("RunnableTests", selected)
        self.assertNotIn("IndexTests", selected)
        self.assertNotIn("OptimizedIndexTests", selected)

    def test_upstream_queue_gets_only_additional_inputs(self):
        source = TAB
        (self.root / "Scripts/run-tests.sh").write_text(
            'S=Tinycast/Features/Settings\nBASE="$S/SettingsTab.swift"\n'
            'run slow -O LauncherSettingsFileTests \\\n    $BASE # upstream inputs\n')
        (self.root / "Tests/LauncherSettingsFileTests.swift").write_text(
            '// notchcast-sources: -framework AppKit\n')
        queue = self.root / "queue"
        queue.write_text(f"0 LauncherSettingsFileTests -O {source}\n")
        subprocess.run(["bash", "-c", 'emit_db=0; SELF=upstream; QUEUE=queue; '
                        'run() { :; }; source notchcast/test-harnesses.sh'],
                       cwd=self.root, env=self.env, check=True)
        arguments = queue.read_text().split()
        self.assertEqual(1, arguments.count(source))
        self.assertIn(HIDDEN, arguments)
        self.assertEqual(["-framework", "AppKit"], arguments[arguments.index("-framework"):][:2])

    def test_upstream_camel_case_harness_gets_its_header_inputs(self):
        (self.root / "Scripts/run-tests.sh").write_text(
            'run AppearanceTests Tinycast/DesignSystem/Theme.swift\n')
        (self.root / "Tests/AppearanceTests.swift").write_text(
            '// notchcast-sources: Tinycast/Features/Example/Model/*.swift\n')
        queue = self.root / "queue"
        queue.write_text("0 AppearanceTests - Tinycast/DesignSystem/Theme.swift\n")
        subprocess.run(["bash", "-c", 'emit_db=0; SELF=upstream; QUEUE=queue; '
                        'run() { :; }; source notchcast/test-harnesses.sh'],
                       cwd=self.root, env=self.env, check=True)
        self.assertIn(EXAMPLE, queue.read_text().split())

    def test_text_read_selects_consumer_even_after_deletion(self):
        self.assertIn("notchcast-reader-test", self.selected("fixtures/deleted.txt"))

    def test_folder_source_selects_consumer_even_after_deletion(self):
        self.assertIn("nc-Example-folder-test",
                      self.selected("Tinycast/Features/Example/Service/Removed.swift"))

    def test_unrelated_change_does_not_select_consumers(self):
        self.assertEqual(["notchcast-hidden-features-test"], self.selected("unrelated.txt"))

    def test_runner_keeps_reads_out_of_compiler_arguments(self):
        result = subprocess.run(["bash", "-c", 'emit_db=0; SELF=upstream; QUEUE=queue; '
                                 'run() { printf "%s\\n" "$*"; }; source notchcast/test-harnesses.sh'],
                                cwd=self.root, env=self.env, text=True, capture_output=True, check=True)
        lines = result.stdout.splitlines()
        conditional = next(line for line in lines if line.startswith("nc-Example-conditional-test "))
        self.assertIn(HIDDEN, conditional)
        self.assertNotIn("fixtures/", result.stdout)
        self.assertIn("notchcast-reader-test -parse-as-library", lines)

    def test_conditional_globs_do_not_duplicate_sources_or_drop_repeated_flags(self):
        source = HIDDEN
        (self.root / "Tests/nc-Example-overlap-test.swift").write_text(
            f"// notchcast-sources: -framework AppKit -framework Foundation {source} {TAB}\n")
        result = subprocess.run(["bash", "-c", 'emit_db=0; SELF=upstream; QUEUE=queue; '
                                 'run() { printf "%s\\n" "$*"; }; source notchcast/test-harnesses.sh'],
                                cwd=self.root, env=self.env, text=True, capture_output=True, check=True)
        arguments = next(line.split()[1:] for line in result.stdout.splitlines()
                         if line.startswith("nc-Example-overlap-test "))
        self.assertEqual(1, arguments.count(source))
        self.assertEqual(["-framework", "AppKit", "-framework", "Foundation"], arguments[:4])

    def compiled_as_the_runner_does(self, name, *arguments):
        script = 'name=$0; source notchcast/command-harness-sources.sh; printf "%s\\n" "$@"'
        return subprocess.run(["bash", "-c", script, name, *arguments], cwd=self.root, env=self.env,
                              text=True, capture_output=True, check=True).stdout.splitlines()

    def test_settings_tab_compilation_gets_the_hidden_tabs_once(self):
        added = self.compiled_as_the_runner_does("SettingsHistoryTests", TAB)
        self.assertEqual([1, 1], [added.count(TAB), added.count(HIDDEN)])
        listed = self.compiled_as_the_runner_does("SettingsHistoryTests", TAB, HIDDEN)
        self.assertEqual(1, listed.count(HIDDEN))
        self.assertNotIn(HIDDEN, self.compiled_as_the_runner_does("ExampleTests", EXAMPLE))

    def test_runner_batches_conditional_inputs_in_one_bash_invocation(self):
        calls = self.root / "bash-calls"
        (self.root / "bin/bash").write_text(
            '#!/bin/bash\nprintf "call\\n" >> "$BASH_CALLS"\nexec /bin/bash "$@"\n')
        (self.root / "bin/bash").chmod(0o755)
        subprocess.run(["/bin/bash", "-c", 'emit_db=0; SELF=upstream; QUEUE=queue; '
                        'run() { :; }; source notchcast/test-harnesses.sh'],
                       cwd=self.root, env={**self.env, "BASH_CALLS": str(calls)}, check=True)
        self.assertEqual(["call"], calls.read_text().splitlines())

    def assert_runner_refuses_invalid_inputs(self):
        result = subprocess.run(["bash", "-uc", 'emit_db=0; SELF=upstream; QUEUE=queue; '
                                 'run() { printf "registered %s\\n" "$*"; }; '
                                 'source notchcast/test-harnesses.sh; printf "suite passed\\n"'],
                                cwd=self.root, env=self.env, text=True, capture_output=True)
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("::error::", result.stderr)
        self.assertNotIn("suite passed", result.stdout)
        self.assertNotIn("registered", result.stdout)

    def test_bad_header_fails_runner_even_when_source_status_is_ignored(self):
        (self.root / "Tests/nc-Example-broken-test.swift").write_text(
            '// notchcast-sources: -Xcc "-DBROKEN\n')
        self.assert_runner_refuses_invalid_inputs()

    def test_invalid_utf8_fails_runner(self):
        (self.root / "Tests/nc-Example-broken-test.swift").write_bytes(bytes([255]))
        self.assert_runner_refuses_invalid_inputs()

    def test_conditional_helper_failure_fails_runner(self):
        (self.root / "notchcast/command-harness-sources.sh").write_text('false\nprintf "masked\\n"\n')
        self.assert_runner_refuses_invalid_inputs()

    def test_module_check_fails_only_on_an_uncompiled_module(self):
        compiled = "Tinycast/Features/Example/Model/ExampleModule.swift"
        orphan = "Tinycast/Features/Other/OtherModule.swift"
        for path in (compiled, orphan):
            (self.root / path).parent.mkdir(parents=True, exist_ok=True)
            (self.root / path).touch()
        for changed, failed in ((compiled, False), (orphan, True)):
            with self.subTest(changed=changed):
                result = subprocess.run(["python3", "notchcast/check-module-harness.py", "base", "head"],
                                        cwd=self.root, env={**self.env, "CHANGED": changed},
                                        text=True, capture_output=True)
                self.assertEqual(failed, result.returncode == 1, result.stdout + result.stderr)
                self.assertEqual(failed, f"::error file={changed}::" in result.stdout)

    def add_kit(self, name, text):
        (self.root / "Tests/Kit").mkdir(exist_ok=True)
        (self.root / f"Tests/Kit/{name}.kit").write_text(text)

    def runner_lines(self, env=None):
        result = subprocess.run(["bash", "-c", 'emit_db=0; SELF=upstream; QUEUE=queue; '
                                 'run() { printf "%s\\n" "$*"; }; source notchcast/test-harnesses.sh'],
                                cwd=self.root, env=env or self.env, text=True, capture_output=True, check=True)
        return result.stdout.splitlines()

    def test_kit_line_expands_to_its_listed_sources(self):
        for name in ("A", "B", "C"):
            (self.root / f"Tinycast/Features/Example/Model/{name}.swift").touch()
        self.add_kit("pair", "# shared\n\nTinycast/Features/Example/Model/A.swift  # first\n"
                             "Tinycast/Features/Example/Model/B.swift\n")
        self.add_kit("star", "Tinycast/Features/Example/Model/*.swift\n-parse-as-library\n")
        (self.root / "Tests/nc-Example-kit-test.swift").write_text(
            "// notchcast-kit: pair\n// notchcast-sources: -framework AppKit Tinycast/Features/Example/Model/A.swift\n")
        (self.root / "Tests/nc-Example-stars-test.swift").write_text("// notchcast-kit: pair star\n")
        lines = self.runner_lines()
        self.assertTrue(any(line.startswith("nc-Example-kit-test Tinycast/Features/Example/Model/A.swift "
                                            "Tinycast/Features/Example/Model/B.swift -framework AppKit")
                            for line in lines), lines)
        stars = next(line.split() for line in lines if line.startswith("nc-Example-stars-test "))
        self.assertEqual(1, stars.count("Tinycast/Features/Example/Model/A.swift"))
        self.assertEqual(["Tinycast/Features/Example/Model/B.swift"], stars[2:3])
        self.assertIn("-parse-as-library", stars)

    def test_kit_file_and_matched_source_select_every_user(self):
        self.add_kit("pair", "Tinycast/Features/Example/Model/*.swift\n")
        (self.root / "Tests/nc-Example-kit-test.swift").write_text("// notchcast-kit: pair\n")
        (self.root / "Tests/nc-Other-kit-test.swift").write_text("// notchcast-kit: pair\n")
        for changed in ("Tests/Kit/pair.kit", "Tinycast/Features/Example/Model/Removed.swift"):
            with self.subTest(changed=changed):
                selected = self.selected(changed)
                self.assertIn("nc-Example-kit-test", selected)
                self.assertIn("nc-Other-kit-test", selected)
        self.assertNotIn("nc-Example-kit-test", self.selected("Tests/Kit/other.kit"))

    def test_kit_line_with_two_paths_selects_on_each(self):
        self.add_kit("pair", "Tinycast/Features/Example/Model/A.swift Tinycast/Features/Example/Model/B.swift\n")
        (self.root / "Tests/nc-Example-kit-test.swift").write_text("// notchcast-kit: pair\n")
        for changed in ("Tinycast/Features/Example/Model/A.swift", "Tinycast/Features/Example/Model/B.swift"):
            with self.subTest(changed=changed):
                self.assertIn("nc-Example-kit-test", self.selected(changed))

    def test_unknown_kit_fails_runner(self):
        (self.root / "Tests/nc-Example-kit-test.swift").write_text("// notchcast-kit: missing\n")
        self.assert_runner_refuses_invalid_inputs()

    def test_empty_kit_fails_runner(self):
        self.add_kit("hollow", "# only a comment\n\n")
        (self.root / "Tests/nc-Example-kit-test.swift").write_text("// notchcast-kit: hollow\n")
        self.assert_runner_refuses_invalid_inputs()

    def test_kit_line_naming_no_kit_fails_runner(self):
        (self.root / "Tests/nc-Example-kit-test.swift").write_text("// notchcast-kit:\n")
        self.assert_runner_refuses_invalid_inputs()

    def test_resolver_cli_reports_kit_error_and_exits_nonzero(self):
        (self.root / "Tests/nc-Example-kit-test.swift").write_text("// notchcast-kit: missing\n")
        result = subprocess.run(["python3", "notchcast/harness_inputs.py"], cwd=self.root, env=self.env,
                                text=True, capture_output=True)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("::error::unknown notchcast-kit 'missing'", result.stderr)

    def git_fixture(self):
        env = {**self.env, "PATH": os.environ["PATH"], "GIT_AUTHOR_NAME": "t", "GIT_COMMITTER_NAME": "t",
               "GIT_AUTHOR_EMAIL": "t@example.invalid", "GIT_COMMITTER_EMAIL": "t@example.invalid"}
        for command in (["init", "-q", "-b", "main"], ["add", "-A"], ["commit", "-qm", "upstream"],
                        ["update-ref", "refs/remotes/upstream/main", "HEAD"]):
            subprocess.run(["git", *command], cwd=self.root, env=env, check=True)
        return env

    def fork_runner(self, env, harness, text=""):
        (self.root / harness).write_text(text)
        subprocess.run(["git", "add", "-A"], cwd=self.root, env=env, check=True)
        subprocess.run(["git", "commit", "-qm", "fork"], cwd=self.root, env=env, check=True)
        return subprocess.run(["bash", "-c", 'emit_db=0; SELF=upstream; QUEUE=queue; '
                               'run() { printf "registered %s\\n" "$*"; }; source notchcast/test-harnesses.sh'],
                              cwd=self.root, env=env, text=True, capture_output=True)

    def test_fork_owned_upstream_style_harness_without_header_fails_loudly(self):
        (self.root / "Tests/ext-old-test.swift").touch()
        env = self.git_fixture()
        result = self.fork_runner(env, "Tests/forked-test.swift")
        self.assertIn("::error::Tests/forked-test.swift needs a // notchcast-sources: header", result.stderr)
        self.assertIn("registered forked-test", result.stdout)
        self.assertNotIn("ext-old-test", result.stdout + result.stderr)
        (self.root / "Tests/forked-test.swift").write_text("// notchcast-sources: -parse-as-library\n")
        self.assertIn("forked-test -parse-as-library", self.runner_lines(env))

    def test_fork_owned_harness_with_only_a_reads_header_fails_loudly(self):
        env = self.git_fixture()
        result = self.fork_runner(env, "Tests/forked-test.swift", "// notchcast-reads: fixtures/*.txt\n")
        self.assertIn("::error::Tests/forked-test.swift needs a // notchcast-sources: header", result.stderr)
        self.assertIn("registered forked-test", result.stdout)

    def test_resolver_in_an_exported_tree_skips_the_fork_check(self):
        (self.root / "Tests/ext-old-test.swift").touch()
        env = self.git_fixture()
        export = tempfile.TemporaryDirectory(prefix="harness-export-")
        self.addCleanup(export.cleanup)
        archive = subprocess.run(["git", "archive", "HEAD"], cwd=self.root, env=env, check=True,
                                 capture_output=True).stdout
        subprocess.run(["tar", "-x", "-C", export.name], input=archive, check=True)
        outputs = [subprocess.run(["python3", "notchcast/harness_inputs.py"], cwd=cwd, env=env,
                                  text=True, capture_output=True) for cwd in (self.root, export.name)]
        for result in outputs:
            self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(outputs[0].stdout, outputs[1].stdout)

    def test_fork_check_fetches_a_missing_upstream_ref_and_fails_closed_without_it(self):
        env = self.git_fixture()
        remote = tempfile.TemporaryDirectory(prefix="harness-upstream-")
        self.addCleanup(remote.cleanup)
        subprocess.run(["git", "clone", "-q", "--bare", str(self.root), f"{remote.name}/up.git"],
                       env=env, check=True, capture_output=True)
        env |= {"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": f"url.{remote.name}/.insteadOf",
                "GIT_CONFIG_VALUE_0": "https://github.com/"}
        for repo, fetched in (("up", True), ("missing", False)):
            with self.subTest(repo=repo):
                subprocess.run(["git", "update-ref", "-d", "refs/remotes/upstream/main"],
                               cwd=self.root, env=env, check=True)
                (self.root / "notchcast/config.env").write_text(f'CI_SKIP_TESTS=""\nUPSTREAM_REPO={repo}\n')
                result = self.fork_runner(env, "Tests/forked-test.swift")
                self.assertEqual(0 if fetched else 1, result.returncode, result.stderr)
                if fetched:
                    self.assertIn("::error::Tests/forked-test.swift needs a // notchcast-sources: header",
                                  result.stderr)
                else:
                    self.assertIn("::error::cannot fetch refs/remotes/upstream/main", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
