"""An attractive table must never conceal missing baselines or broken controls."""
import unittest

from report import VARIANTS, make_report


def observations():
    return [dict(variant=variant, case="add_dependent", mode="scalar", profile="0:0", seed=seed,
                 jitter=0, status="PASS", windows=[dict(cycles=129, retire_proxy=129)], total=dict(cycles=1000),
                 binary_sha256="binary", harness_sha256="harness", image_id="image",
                 operations=128, warmups=2, samples=3, memory_model="synthetic", body_cycles_median=129)
            for variant in VARIANTS for seed in (1, 17)]


class Report(unittest.TestCase):
    def test_missing_or_failed_anchor_cannot_make_a_complete_report(self):
        manifest = dict(benchmarks=[dict(id="add_dependent")])
        rows = observations()
        self.assertEqual(make_report(manifest, rows)["status"], "PASS")
        missing = make_report(manifest, rows[1:])
        self.assertEqual(missing["status"], "BLOCKED")
        self.assertEqual(len(missing["missing"]), 1)
        rows[0]["status"] = "FAIL"
        self.assertEqual(make_report(manifest, rows)["status"], "FAIL")

    def test_equal_medians_cannot_hide_broken_controller_control(self):
        rows = observations()
        rows[-1]["total"] = dict(cycles=1001)
        self.assertEqual(make_report(dict(benchmarks=[dict(id="add_dependent")]), rows)["status"], "FAIL")

    def test_duplicate_rows_cannot_count_as_repetitions(self):
        rows = observations()
        with self.assertRaises(ValueError):
            make_report(dict(benchmarks=[dict(id="add_dependent")]), rows + [rows[0]])


if __name__ == "__main__":
    unittest.main()
