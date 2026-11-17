#!/usr/bin/env python3
"""Cover harness-times.py: recording from a runner log, packing, and the hash fallback."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("harness-times.py")
spec = importlib.util.spec_from_file_location("harness_times", SCRIPT)
times = importlib.util.module_from_spec(spec)
spec.loader.exec_module(times)

QUEUE = [f"1 {name} -Onone Source.swift" for name in ("slow", "mid", "a", "b", "c", "new", "skip")]
TIMES = {"slow": 120.0, "mid": 50.0, "a": 10.0, "b": 8.0, "c": 6.0, "skip": 4.0}


def shards(count, recorded, skip=""):
    return [times.narrow(QUEUE, "", skip, f"{index} {count}", recorded) for index in range(count)]


class HarnessTimesTest(unittest.TestCase):
    def test_record_sums_compile_and_run_of_passing_harnesses(self):
        log = ("2026-11-17T13:14:31Z [ 1/53] \x1b[32mok\x1b[0m    FuzzTests                   0.3s"
               "  \x1b[2m(compile 0.1s)\x1b[0m\n[ 2/53] ok    nc-Island-test   20.0s  (compile 12.5s)\n"
               "\x1b[31mFAIL\x1b[0m  Broken    assertion failed after 1.0s\n")
        self.assertEqual(times.record(log), "FuzzTests 0.4\nnc-Island-test 32.5\n")
        self.assertEqual(times.parse(times.record(log)), {"FuzzTests": 0.4, "nc-Island-test": 32.5})

    def test_every_harness_runs_in_exactly_one_shard(self):
        for recorded in (TIMES, {}):
            for count in (1, 2, 3, 5):
                names = [line.split()[1] for kept, _ in shards(count, recorded) for line in kept]
                self.assertEqual(sorted(names), sorted(line.split()[1] for line in QUEUE), (count, recorded))

    def test_packing_balances_by_time_and_unknown_weighs_the_median(self):
        place, weight, loads = times.pack([line.split()[1] for line in QUEUE], TIMES, 2)
        self.assertEqual(weight["new"], 9.0)
        self.assertEqual(place["slow"], 0)
        self.assertEqual({name for name, index in place.items() if index == 0}, {"slow"})
        self.assertEqual(loads, [120.0, 87.0])

    def test_a_shard_starts_its_longest_harness_first(self):
        kept, report = shards(2, TIMES)[1]
        self.assertEqual([line.split()[:2] for line in kept],
                         [["0", "mid"], ["1", "a"], ["2", "new"], ["3", "b"], ["4", "c"], ["5", "skip"]])
        self.assertIn("split: by recorded time, 6 known, 1 at the median", report)
        self.assertIn("shard 1 of 2: 6 of 7 harnesses", report)

    def test_runner_skips_apply_after_the_split(self):
        packed = [kept for kept, _ in shards(2, TIMES)]
        skipped = [kept for kept, _ in shards(2, TIMES, skip="skip")]
        self.assertEqual([[line for line in kept if " skip " not in line] for kept in packed], skipped)

    def test_no_times_keeps_the_name_hash_split(self):
        kept, report = shards(3, {})[0]
        expected = [line + "\n" for line in QUEUE if times.name_hash(line.split()[1]) % 3 == 0]
        self.assertEqual(kept, expected)
        self.assertIn("split: by name hash, no recorded times", report)
        self.assertEqual([times.name_hash(name) for name in ("FuzzTests", "nc-DisplaySound-mutation-test")],
                         [515726, 222816])

    def test_selection_narrows_before_packing(self):
        kept, _ = times.narrow(QUEUE, "a b", "", "0 2", TIMES)
        other, _ = times.narrow(QUEUE, "a b", "", "1 2", TIMES)
        self.assertEqual(sorted(line.split()[1] for line in kept + other), ["a", "b"])
        self.assertTrue(kept and other)

    def test_cli_filter_writes_the_kept_queue(self):
        with tempfile.TemporaryDirectory() as work:
            queue = Path(work, "queue")
            queue.write_text("\n".join(QUEUE) + "\n")
            env = {"NOTCHCAST_SHARD": "0 2", "NOTCHCAST_TIMES": "".join(f"{n} {t}\n" for n, t in TIMES.items())}
            result = subprocess.run(["python3", str(SCRIPT), "filter", str(queue)], env=env,
                                    capture_output=True, text=True, check=True)
            self.assertEqual(Path(work, "queue.kept").read_text(), "0 slow -Onone Source.swift\n")
            self.assertIn("shard 0 of 2: 1 of 7 harnesses", result.stderr)


if __name__ == "__main__":
    unittest.main()
