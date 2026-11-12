"""Failures which real HDL qualification must distinguish from valid results."""
import unittest

from qualify import cold_refill_counter_checks, controller_negative_control, corrupt_comparison, deterministic_repeats, proxy_counter_checks


class Qualification(unittest.TestCase):
    def test_cold_stride_counters_distinguish_words_from_halfwords(self):
        row = dict(case="cache_line_stride", variant="h1", mode="line", profile="0:0", seed=1,
                   jitter=0, line_enabled=True, warmups=2, status="PASS",
                   windows=[{}, {}, dict(reads=0, writes=0, lines=65, halfwords=1040)])
        self.assertEqual(cold_refill_counter_checks([row])[0]["status"], "PASS")
        row["windows"][-1]["halfwords"] = 520
        self.assertEqual(cold_refill_counter_checks([row])[0]["status"], "FAIL")
        row.update(variant="h0", line_enabled=False)
        row["windows"][-1] = dict(reads=520, writes=0, lines=0, halfwords=0)
        self.assertEqual(cold_refill_counter_checks([row])[0]["status"], "PASS")

    def test_cp15_proxy_is_not_an_architectural_instruction_counter(self):
        row = dict(variant="h0", mode="scalar", case="cp15_reads", profile="0:0", jitter=0,
                   seed=1, status="PASS", windows=[dict(retire_proxy=1)])
        self.assertEqual(proxy_counter_checks([row])[0]["status"], "PASS")
        row["windows"] = [dict(retire_proxy=65)]
        self.assertEqual(proxy_counter_checks([row])[0]["status"], "FAIL")

    def test_assertion_mutation_keeps_register_and_failure_branch(self):
        # CMP before the closing marker belongs to the kernel and must survive.
        words = [0xE1500008, 0xE1A00000, 0xE1570008, 0x1A000001, 0xE12FFF19]
        data = b"".join(w.to_bytes(4, "little") for w in words)
        changed, mutation = corrupt_comparison(data, 4)
        actual = [int.from_bytes(changed[n:n+4], "little") for n in range(0, len(changed), 4)]
        self.assertEqual(actual, [words[0], words[1], 0xE35700FF, words[3], words[4]])
        self.assertEqual(mutation["offset"], 8)

    def test_absent_guest_comparison_cannot_be_qualified(self):
        with self.assertRaises(ValueError):
            corrupt_comparison(bytes(32), 4)

    def test_repeat_checks_raw_windows_and_whole_run_not_only_median(self):
        first = dict(variant="h0", mode="scalar", case="add", profile="0:0", jitter=0,
                     seed=1, status="PASS", windows=[dict(cycles=129, reads=0)], total=dict(cycles=1000))
        second = dict(first, seed=17)
        self.assertEqual(deterministic_repeats([first, second])[0]["status"], "PASS")
        for field, value in (("windows", [dict(cycles=129, reads=1)]), ("total", dict(cycles=1001)),
                             ("status", "FAIL")):
            with self.subTest(field=field):
                changed = dict(second, **{field: value})
                self.assertEqual(deterministic_repeats([first, changed])[0]["status"], "FAIL")
        self.assertEqual(deterministic_repeats([first])[0]["status"], "NOT_RUN")
        self.assertEqual(deterministic_repeats([dict(first, jitter=7)]), [])

    def test_controller_control_checks_cold_windows_and_whole_run(self):
        old = dict(variant="working_previous_sdram", mode="line", case="add", profile="0:0",
                   jitter=0, seed=1, status="PASS", windows=[dict(cycles=129, reads=0)], total=dict(cycles=1000))
        new = dict(old, variant="working")
        self.assertEqual(controller_negative_control([old, new])[0]["status"], "PASS")
        self.assertEqual(controller_negative_control([new])[0]["status"], "BLOCKED")
        new["windows"] = [dict(cycles=129, reads=1)]
        self.assertEqual(controller_negative_control([old, new])[0]["status"], "FAIL")


if __name__ == "__main__":
    unittest.main()
