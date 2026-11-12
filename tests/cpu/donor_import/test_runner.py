"""Host-side checks for reference isolation and trustworthy result accounting.

These tests do not simulate the CPU. Runtime qualification remains a separate
gate even when every host test passes.
"""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import run
from benchmarks import assembly, cases


CASE = dict(warmups=2, samples=3, operations=10)


def good_log():
    lines = [f"WINDOW index={n} cycles=100 retire_proxy=20 reads=2 writes=0 lines=1 halfwords=16"
             for n in range(5)]
    return "\n".join(lines + ["RESULT windows=5 cycles=1000 reads=20 writes=20 lines=10 halfwords=160"])


def observation(variant, cycles):
    return dict(variant=variant, case="add", mode="line", profile="0:3", seed=1,
                jitter=0, status="PASS", binary_sha256="binary", harness_sha256="harness",
                operations=10, warmups=2, samples=3, memory_model="synthetic", image_id="image",
                body_cycles_median=cycles)


class Results(unittest.TestCase):
    def test_measured_body_excludes_warmups(self):
        log = good_log().replace("index=0 cycles=100", "index=0 cycles=200").replace(
            "index=1 cycles=100", "index=1 cycles=250")
        parsed = run.parse_log(log, CASE)
        self.assertEqual(parsed["body_cycles_median"], 100)
        self.assertEqual(parsed["cycles_per_operation"], 10)

    def test_missing_terminal_is_not_success(self):
        with self.assertRaises(ValueError):
            run.parse_log(good_log().split("RESULT")[0], CASE)

    def test_missing_window_is_not_success(self):
        with self.assertRaises(ValueError):
            run.parse_log("\n".join(good_log().splitlines()[1:]), CASE)

    def test_duplicate_window_is_not_success(self):
        with self.assertRaises(ValueError):
            run.parse_log(good_log().replace("index=2", "index=1"), CASE)

    def test_duplicate_completion_is_not_success(self):
        with self.assertRaises(ValueError):
            run.parse_log(good_log() + "\nRESULT windows=5", CASE)

    def test_negative_or_empty_window_is_not_success(self):
        for replacement in ("cycles=0", "cycles=-1", "reads=-1"):
            with self.subTest(replacement=replacement), self.assertRaises(ValueError):
                run.parse_log(good_log().replace("cycles=100", replacement, 1), CASE)

    def test_counter_reconciliation_is_required(self):
        with self.assertRaises(ValueError):
            run.parse_log(good_log().replace("lines=10 halfwords=160", "lines=1 halfwords=16"), CASE)

    def test_vendor_errors_override_completion(self):
        for diagnostic in ("ERROR: model timing", "%Error: assertion", "FATAL: guest failed"):
            with self.subTest(diagnostic=diagnostic), self.assertRaises(ValueError):
                run.parse_log(good_log() + "\n" + diagnostic, CASE)

    def test_distinct_cycle_and_throughput_ratios(self):
        result = run.compare_rows([observation("h0", 100), observation("h1", 80)], "h0", "h1")
        self.assertAlmostEqual(result[0]["cycles_saved"], 0.2)
        self.assertAlmostEqual(result[0]["throughput_gain"], 0.25)

    def test_changed_binary_harness_or_inputs_are_incomparable(self):
        for field in ("binary_sha256", "harness_sha256", "image_id", "memory_model", "operations", "warmups", "samples"):
            a, b = observation("h0", 100), observation("h1", 80)
            b[field] = "different"
            with self.subTest(field=field), self.assertRaises(ValueError):
                run.compare_rows([a, b], "h0", "h1")

    def test_failed_or_absent_candidate_is_blocked(self):
        self.assertEqual(run.compare_rows([observation("h0", 100)], "h0", "h1")[0]["status"], "BLOCKED")
        candidate = observation("h1", 80)
        candidate["status"] = "FAIL"
        self.assertEqual(run.compare_rows([observation("h0", 100), candidate], "h0", "h1")[0]["status"], "BLOCKED")

    def test_duplicate_observation_is_rejected(self):
        a = observation("h0", 100)
        with self.assertRaises(ValueError):
            run.compare_rows([a, a], "h0", "h1")

    def test_mismatched_wait_profiles_do_not_pair(self):
        candidate = observation("h1", 80)
        candidate["profile"] = "2:9"
        self.assertEqual(run.compare_rows([observation("h0", 100), candidate], "h0", "h1")[0]["status"], "BLOCKED")


class Isolation(unittest.TestCase):
    def test_frozen_sources_harness_and_programs_cannot_drift(self):
        for changed in ("tb.sv", "snapshot/rtl/core.sv", "program.hex"):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                for name in ("tb.sv", "snapshot/rtl/core.sv", "program.hex"):
                    path = root/name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(b"frozen")
                sha = run.digest(b"frozen")
                manifest = dict(harness="tb.sv", harness_sha256=sha,
                                variants={"h0":dict(directory="snapshot", files={"rtl/core.sv":sha})},
                                benchmarks=[dict(id="case", hex="program.hex", hex_sha256=sha)])
                with patch.object(run, "ROOT", root):
                    run.validate_frozen(manifest)
                    (root/changed).write_bytes(b"changed")
                    with self.assertRaises(ValueError):
                        run.validate_frozen(manifest)

    def test_exact_user_references(self):
        self.assertEqual(run.REFERENCES, {
            "h0": "ce8d2c902724a59e7537b845bc841dbd82d5bbf7",
            "h1": "3f5e8aeae3260562a814eacdd8d8aa505c044af8",
        })

    def test_project_source_filter_excludes_secrets_and_media(self):
        for path in (".aws/credentials", ".git/config", "firmware/phone.bin", "scratch/reference/rtl/arm/a.sv", ""):
            self.assertFalse(run.source_path(path), path)
        for path in ("rtl/arm/zap_core.sv", "rtl/arm920/tlb.sv", "rtl/ngage_sdram_adapter.v"):
            self.assertTrue(run.source_path(path), path)

    def test_historical_snapshot_reads_exact_git_objects(self):
        files = {"rtl/ngage_cpu.sv": b"module ngage_cpu; endmodule",
                 "rtl/arm/zap_core.sv": b"historical CPU", "rtl/arm920/cache_access.sv": b"historical cache"}
        def fake_git(*args, **kwargs):
            if args[0] == "rev-parse":
                return b"pinned-sha\n"
            if args[0] == "ls-tree":
                return ("\0".join([*files, ".aws/credentials"]) + "\0").encode()
            if args[0] == "show":
                self.assertTrue(args[1].startswith("pinned-sha:"))
                return files[args[1].split(":", 1)[1]]
            self.fail(f"unexpected git mutation: {args}")
        with tempfile.TemporaryDirectory() as tmp, patch.object(run, "git", side_effect=fake_git):
            destination = Path(tmp) / "snapshot"
            manifest = run.snapshot(destination, "requested")
            self.assertEqual((destination / "rtl/arm/zap_core.sv").read_bytes(), b"historical CPU")
            self.assertEqual(set(manifest["files"]), set(files))

    def test_controller_control_keeps_cpu_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            working, previous, control = root / "working", root / "previous", root / "control"
            cpu = working / "rtl/arm/zap_core.sv"
            cpu.parent.mkdir(parents=True)
            cpu.write_bytes(b"unchanged CPU")
            previous.mkdir()
            for target, name in run.PREVIOUS.items():
                path = working / target
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"new")
                (previous / name).write_bytes(b"old")
            result = run.old_controller_control(working, control, previous)
            self.assertEqual(result["status"], "PREPARED")
            self.assertEqual((control / "rtl/arm/zap_core.sv").read_bytes(), b"unchanged CPU")
            self.assertEqual((control / "rtl/ngage_sdram_adapter.v").read_bytes(), b"old")
            self.assertEqual((working / "rtl/ngage_sdram_adapter.v").read_bytes(), b"new")

    def test_missing_controller_backup_is_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run.old_controller_control(root / "working", root / "control", root / "missing")
            self.assertEqual(result["status"], "BLOCKED")
            self.assertFalse((root / "control").exists())

    def test_unsafe_experiment_names_are_rejected(self):
        for name in ("../escape", "/absolute", "..", ".", "contains space"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                run.locations(name)


class Programs(unittest.TestCase):
    def test_symbols_must_exist_and_be_ordered(self):
        self.assertEqual(run.symbols("00001000 T body_begin\n00002000 T body_end"),
                         dict(body_begin=4096, body_end=8192))
        for bad in ("", "00001000 T body_begin", "00002000 T body_begin\n00001000 T body_end"):
            with self.assertRaises(ValueError):
                run.symbols(bad)

    def test_all_kernels_have_guest_checks_and_window_markers(self):
        entries = cases()
        self.assertEqual(len({c["id"] for c in entries}), len(entries))
        for case in entries:
            source = assembly(case)
            self.assertIn(".global body_begin", source)
            self.assertIn(".global body_end", source)
            self.assertIn("0x50415353", source)
            self.assertIn("bne fail", source)
            self.assertGreater(case["operations"], 0)
            self.assertEqual(case["samples"], 3)

    def test_flags_and_signed_long_product_oracles(self):
        by_id = {case["id"]: case for case in cases()}
        self.assertEqual(by_id["carry_flags"]["expected"][3], 6)
        product = by_id["multiply_long"]["expected"]
        self.assertEqual((product[1] << 32) | product[0], 12884901882)
        self.assertEqual(by_id["load_formats"]["expected"][2], 0xFFFF80FF)


if __name__ == "__main__":
    unittest.main()
