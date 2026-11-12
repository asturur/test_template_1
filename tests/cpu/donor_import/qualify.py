#!/usr/bin/env python3
"""Qualify completed HDL attempts without changing frozen sources or programs.

Negative programs are separate copies with a deliberately wrong guest comparison.
This is assertion/observer qualification, not a complete independent ISA oracle.
"""
import argparse
import json
import subprocess
from pathlib import Path

from run import IMAGE, ROOT, container_path, digest, locations, parse_log, validate_frozen, write_json


# Counts derived from the explicit kernel instruction streams/control flow,
# including the closing NOP. These are ordinary-uop-last observer expectations,
# not an architectural instruction counter: CP15's 64 MRCs are excluded.
EXPECTED_PROXY = {
    "add_dependent": 129, "alu_independent": 129, "carry_flags": 129,
    "shift_dependent": 65, "multiply_accumulate": 33, "multiply_long": 33,
    "load_dependent": 65, "load_independent": 129, "load_formats": 129,
    "store_reload": 97, "block_copy": 33, "direct_branch": 194,
    "call_return": 97, "cp15_reads": 1, "cache_line_stride": 66,
}


def proxy_counter_checks(rows):
    result = []
    for row in rows:
        if "case" not in row:
            continue
        expected = EXPECTED_PROXY.get(row["case"])
        status = "NOT_RUN" if expected is None else "BLOCKED"
        if expected is not None and row["status"] == "PASS":
            status = "PASS" if all(w["retire_proxy"] == expected for w in row["windows"]) else "FAIL"
        result.append(dict(case=row["case"], variant=row["variant"], mode=row["mode"],
                           profile=row["profile"], seed=row["seed"], jitter=row["jitter"],
                           expected_proxy_per_window=expected, status=status))
    return result


def cold_refill_counter_checks(rows):
    """The cold stride performs 65 complete, clean 32-byte line fills."""
    result = []
    for row in rows:
        if row.get("case") != "cache_line_stride":
            continue
        expected = dict(reads=0, writes=0, lines=65, halfwords=1040) if row["line_enabled"] else dict(
            reads=520, writes=0, lines=0, halfwords=0)
        status = "BLOCKED"
        if row["status"] == "PASS":
            measured = row["windows"][row["warmups"]:]
            status = "PASS" if measured and all(all(w[k] == v for k, v in expected.items()) for w in measured) else "FAIL"
        result.append(dict(case=row["case"], variant=row["variant"], mode=row["mode"],
                           profile=row["profile"], seed=row["seed"], jitter=row["jitter"],
                           expected_per_measured_window=expected, status=status))
    return result


def corrupt_comparison(data, body_end):
    """Replace the first checked result's CMP rN,r8 with CMP rN,#255.

    All initial kernels assert a first result other than 255. Preserve the BNE
    and failure mailbox path, so the original guest assertion must reject it.
    """
    changed = bytearray(data)
    for offset in range(body_end + 4, len(data) - 3, 4):
        word = int.from_bytes(data[offset:offset + 4], "little")
        if word & 0xFFF0FFFF == 0xE1500008:
            replacement = 0xE35000FF | (word & 0x000F0000)
            changed[offset:offset + 4] = replacement.to_bytes(4, "little")
            return bytes(changed), dict(offset=offset, original=f"{word:08x}", replacement=f"{replacement:08x}")
    raise ValueError("no guest comparison found after closing marker")


def deterministic_repeats(rows):
    """At jitter=0 seed cannot affect traffic; reconcile every raw counter."""
    groups = {}
    for row in rows:
        if "case" not in row or row.get("jitter") != 0:
            continue
        key = tuple(row[k] for k in ("variant", "mode", "case", "profile"))
        groups.setdefault(key, []).append(row)
    result = []
    for key, samples in sorted(groups.items()):
        status = "PASS"
        if len(samples) < 2:
            status = "NOT_RUN"
        elif any(r["status"] != "PASS" for r in samples):
            status = "FAIL"
        elif any((r["windows"], r["total"]) != (samples[0]["windows"], samples[0]["total"])
                 for r in samples[1:]):
            status = "FAIL"
        result.append(dict(zip(("variant", "mode", "case", "profile"), key),
                           status=status, seeds=[r["seed"] for r in samples]))
    return result


def controller_negative_control(rows):
    indexed = {}
    for row in rows:
        if "case" not in row:
            continue
        key = tuple(row[k] for k in ("case", "mode", "profile", "seed", "jitter"))
        indexed[(row["variant"], key)] = row
    result = []
    identities = {key for variant, key in indexed if variant in {"working", "working_previous_sdram"}}
    for key in sorted(identities):
        old = indexed.get(("working_previous_sdram", key))
        new = indexed.get(("working", key))
        status = "BLOCKED"
        if old and new and old["status"] == new["status"] == "PASS":
            status = "PASS" if (old["windows"], old["total"]) == (new["windows"], new["total"]) else "FAIL"
        result.append(dict(zip(("case", "mode", "profile", "seed", "jitter"), key), status=status))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name")
    parser.add_argument("attempt")
    parser.add_argument("--variant", action="append")
    parser.add_argument("--case", action="append")
    parser.add_argument("--completed-only", action="store_true",
                        help="qualify a captured set of completed observations while the matrix continues")
    args = parser.parse_args()
    if not args.attempt.isdigit() or len(args.attempt) != 4:
        parser.error("attempt must be four digits")
    _, output = locations(args.name)
    manifest = json.loads((output / "manifest.json").read_text())
    validate_frozen(manifest)
    original = output / "attempts" / args.attempt
    if args.completed_only:
        rows = [json.loads(p.read_text()) for p in sorted(original.glob("*/*/*/*/*/result.json"))]
        images = {r["image_id"] for r in rows}
        if len(images) != 1:
            raise ValueError("completed observations lack a single simulator image")
        initial = dict(rows=rows, image_id=images.pop())
    else:
        initial = json.loads((original / "result.json").read_text())
    # Qualification runs are append-only, just like the benchmark attempts.
    index = 1
    while (original / f"qualification-{index:04d}").exists():
        index += 1
    target = original / f"qualification-{index:04d}"
    target.mkdir()
    support = target / "support"
    support.mkdir()
    support_hashes = {}
    for name in ("qualify.py", "run.py", "benchmarks.py"):
        data = Path(__file__).with_name(name).read_bytes()
        (support / name).write_bytes(data)
        support_hashes[name] = digest(data)
    result = dict(scope="Guest assertions, ADD observer edges and deterministic repeats; no full ISA/CPI qualification",
                  runner_sha256=digest(Path(__file__).read_bytes()), rows=[],
                  support_sources_sha256=support_hashes,
                  completed_only=args.completed_only,
                  captured_observations=[r.get("log", r.get("reason")) for r in initial["rows"]],
                  proxy_counter_checks=proxy_counter_checks(initial["rows"]),
                  cold_refill_counter_checks=cold_refill_counter_checks(initial["rows"]),
                  deterministic_repeats=deterministic_repeats(initial["rows"]),
                  controller_negative_control=controller_negative_control(initial["rows"]))
    probe = subprocess.run(["docker", "image", "inspect", IMAGE, "--format", "{{.Id}}"],
                           capture_output=True, text=True)
    if probe.returncode or probe.stdout.strip() != initial.get("image_id"):
        result.update(status="BLOCKED", reason="original simulator image unavailable or changed")
        write_json(target / "result.json", result)
        return 2
    docker = ["docker", "run", "--rm", "--pull=never", "--network", "none", "--platform", "linux/arm64",
              "-v", str(ROOT) + ":/work", "-w", "/work", "--entrypoint"]
    programs = {c["id"]: c for c in manifest["benchmarks"]}
    unique = {}
    for row in initial["rows"]:
        if row.get("status") != "PASS" or "case" not in row:
            continue
        if args.variant and row["variant"] not in args.variant:
            continue
        if args.case and row["case"] not in args.case:
            continue
        # One negative check per binary/build is sufficient, independent of waits.
        if row["profile"] == "0:0":
            unique.setdefault((row["variant"], row["mode"], row["case"]), row)
    for (variant, mode, case_id), baseline in unique.items():
        case = programs[case_id]
        build = original / variant / mode
        executable = build / "obj/Vbench"
        directory = target / variant / mode / case_id
        directory.mkdir(parents=True)
        provenance = dict(executable_sha256=digest(executable.read_bytes()),
                          build_log_sha256=digest((build / "build.log").read_bytes()),
                          source_id=baseline["source_id"], harness_sha256=baseline["harness_sha256"])
        def execute(label, program, begin=case["body_begin"], end=case["body_end"], expected=None):
            argv = docker + [container_path(executable), IMAGE,
                             "+program=" + container_path(program), f"+begin_pc={begin:x}", f"+end_pc={end:x}",
                             "+i_wait=0", "+d_wait=0", "+seed=1", "+jitter=0", "+max_cycles=300000",
                             "+ngage-compact-trace"]
            process = subprocess.run(argv, capture_output=True, text=True)
            log = directory / (label + ".log")
            log.write_text(json.dumps(argv) + "\n" + process.stdout + process.stderr)
            observation = dict(variant=variant, mode=mode, case=case_id, check=label,
                               log=str(log.relative_to(ROOT)), exit_code=process.returncode, **provenance)
            try:
                if expected is not None:
                    if process.returncode == 0 or expected not in log.read_text() or "RESULT " in log.read_text():
                        raise ValueError("negative control did not produce the required failure")
                    try:
                        parse_log(log.read_text(), case)
                    except ValueError:
                        pass
                    else:
                        raise ValueError("parser accepted the negative control")
                else:
                    if process.returncode:
                        raise ValueError("positive replay failed")
                    replay = parse_log(log.read_text(), case)
                    if (replay["windows"], replay["total"]) != (baseline["windows"], baseline["total"]):
                        raise ValueError("positive replay differs from original observation")
                    if any(w["retire_proxy"] != 129 for w in replay["windows"]):
                        raise ValueError("ADD window must contain 128 ADDs plus closing NOP")
                    if any(w["cycles"] != 129 for w in replay["windows"][case["warmups"]:]):
                        raise ValueError("warmed ADD window differs from known one-per-cycle schedule")
                observation["status"] = "PASS"
            except ValueError as exc:
                observation.update(status="FAIL", reason=str(exc))
            result["rows"].append(observation)
            write_json(target / "result.json", result)
            print(variant, mode, case_id, label, observation["status"], flush=True)
        binary = (ROOT / case["hex"]).with_suffix(".bin").read_bytes()
        if digest(binary) != case["binary_sha256"]:
            raise ValueError("assembled binary changed after preparation")
        changed, mutation = corrupt_comparison(binary, case["body_end"])
        corrupt = directory / "wrong-expectation.hex"
        padded = changed + bytes(65536 - len(changed))
        corrupt.write_text("".join(f"{int.from_bytes(padded[n:n+4], 'little'):08x}\n" for n in range(0, 65536, 4)))
        write_json(directory / "mutation.json", dict(**mutation, binary_sha256=digest(changed)))
        execute("guest_assertion", corrupt, expected="guest result check failed")
        if case_id == "add_dependent":
            program = ROOT / case["hex"]
            execute("known_add_replay", program)
            execute("missing_begin", program, begin=0xFFFFFFFC, expected="window end without start")
            execute("missing_end", program, end=0xFFFFFFFC, expected="overlapping benchmark window")
            execute("equal_markers", program, end=case["body_begin"], expected="distinct window markers required")
    statuses = [r["status"] for r in result["rows"]]
    result["status"] = "PASS" if statuses and all(s == "PASS" for s in statuses) else "FAIL"
    if any(r["status"] == "FAIL" for r in result["deterministic_repeats"] + result["controller_negative_control"]
           + result["proxy_counter_checks"] + result["cold_refill_counter_checks"]):
        result["status"] = "FAIL"
    write_json(target / "result.json", result)
    print(target / "result.json")
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
