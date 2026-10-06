#!/usr/bin/env python3
"""The resource sampler records process-unique memory, and the analyzer only
passes or fails a memory budget by more than the baseline's own noise."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


def load(name, module):
    spec = importlib.util.spec_from_file_location(module, SCRIPTS / name)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


sampler = load("benchmark-resources.py", "sampler")
analyzer = load("analyze-resources.py", "analyzer")


def run(shell_mib, samples=20, compositor=60.0, roles=True, ramp=0.0, cpu=0.0):
    """A synthetic run: shell PID 500, compositor PID 900 (not the lowest)."""
    rows = []
    for index in range(samples):
        shell = (shell_mib + ramp * index / samples) * 1024
        rows.append({"elapsedSeconds": 1.0, "processes": {
            "500": {"cpuPercent": cpu, "rssKiB": shell * 1.3, "pssKiB": shell, "pssAnonKiB": shell * 0.9,
                    "ussKiB": shell * 0.95},
            "900": {"cpuPercent": 1.0, "rssKiB": compositor * 1024, "pssKiB": compositor * 1024,
                    "pssAnonKiB": 1.0, "ussKiB": 1.0}}})
    summary = {pid: {"cpuPercentMean": rows[0]["processes"][pid]["cpuPercent"]} for pid in ("500", "900")}
    result = {"schemaVersion": 2, "samples": rows, "summary": summary}
    if roles:
        result["roles"] = {"500": "shell", "900": "compositor"}
    return result


class AnalyzerTest(unittest.TestCase):
    def verdict(self, pairs, cohort="hover-cycle"):
        with tempfile.TemporaryDirectory() as folder:
            for index, (base, island) in enumerate(pairs, 1):
                for flag, value in (("false", base), ("true", island)):
                    Path(folder, f"{cohort}-island-{flag}-{index}.json").write_text(json.dumps(value))
            return analyzer.analyse(folder, cohort)

    def test_clear_margins_pass_and_fail(self):
        passed = self.verdict([(run(300), run(310)), (run(301), run(311)), (run(300.5), run(310.5))])
        self.assertEqual(passed["verdict"], "pass")
        self.assertAlmostEqual(passed["metrics"]["pssKiB"]["median"], 10.0, places=3)
        failed = self.verdict([(run(300), run(360)), (run(301), run(361)), (run(300), run(360))])
        self.assertEqual(failed["verdicts"]["pssKiB"], "FAIL")
        self.assertEqual(failed["verdict"], "FAIL")

    def test_a_delta_inside_the_baseline_noise_is_inconclusive(self):
        # The recorded hover cohort: a 31 MiB median against a baseline that
        # itself moved by 18 MiB between pairs cannot be called either way.
        result = self.verdict([(run(314), run(325)), (run(296), run(327)), (run(297), run(331))])
        self.assertEqual(result["verdicts"]["pssKiB"], "inconclusive")
        self.assertEqual(result["verdict"], "inconclusive")
        self.assertAlmostEqual(result["metrics"]["pssKiB"]["noise"], 18.0, places=3)

    def test_fewer_than_three_pairs_never_conclude(self):
        result = self.verdict([(run(300), run(301)), (run(300), run(301))])
        self.assertEqual(result["verdicts"]["pssKiB"], "inconclusive")

    def test_the_labelled_compositor_is_left_out(self):
        base, island = run(300, compositor=60), run(300, compositor=90)
        result = self.verdict([(base, island)] * 3)
        self.assertAlmostEqual(result["metrics"]["pssKiB"]["median"], 0.0, places=3)
        self.assertAlmostEqual(result["compositor"], 0.0, places=3)
        # An unlabelled run falls back to the lowest PID, here the shell.
        unlabelled = self.verdict([(run(300, roles=False), run(310, roles=False))] * 3)
        self.assertAlmostEqual(unlabelled["metrics"]["pssKiB"]["median"], 0.0, places=3)

    def test_growth_within_a_run_fails(self):
        result = self.verdict([(run(300), run(305, ramp=8))] * 3)
        self.assertGreater(result["growth"], 5)
        self.assertEqual(result["verdicts"]["growth"], "FAIL")

    def test_process_unique_memory_is_reported(self):
        result = self.verdict([(run(300), run(310))] * 3)
        self.assertAlmostEqual(result["metrics"]["ussKiB"]["median"], 9.5, places=3)
        self.assertAlmostEqual(result["metrics"]["pssAnonKiB"]["median"], 9.0, places=3)
        old = run(300)
        for sample in old["samples"]:
            for values in sample["processes"].values():
                del values["ussKiB"]
        self.assertIsNone(self.verdict([(old, run(310))] * 3)["metrics"]["ussKiB"])


class SamplerTest(unittest.TestCase):
    def test_sample_records_process_unique_memory(self):
        values = sampler.sample(os.getpid())
        for key in ("rssKiB", "pssKiB", "pssAnonKiB", "ussKiB"):
            self.assertGreater(values[key], 0, key)
        self.assertLessEqual(values["ussKiB"], values["rssKiB"])

    def test_pid_arguments_take_an_optional_role(self):
        self.assertEqual(sampler.parse_pid("42"), ("", 42))
        self.assertEqual(sampler.parse_pid("compositor:42"), ("compositor", 42))
        with self.assertRaises(Exception):
            sampler.parse_pid("bad role:42")


if __name__ == "__main__":
    unittest.main()
