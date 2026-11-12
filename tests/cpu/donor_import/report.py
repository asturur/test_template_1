#!/usr/bin/env python3
"""Export complete per-case tables; refuse to hide failed/missing observations."""
import argparse
import csv
import io
import json
from collections import Counter

from qualify import cold_refill_counter_checks, controller_negative_control, deterministic_repeats, proxy_counter_checks
from run import compare_rows, digest, locations, validate_frozen, write_json


VARIANTS = ("h0", "h1", "working", "working_previous_sdram")
PAIRS = (("h0", "h1"), ("h1", "working"), ("h0", "working"),
         ("working_previous_sdram", "working"))
OPERATION_UNITS = {
    "add_dependent": "ADD instruction",
    "alu_independent": "arithmetic instruction",
    "carry_flags": "ADD/ADC/SUB/SBC instruction",
    "shift_dependent": "shifted data-processing instruction",
    "multiply_accumulate": "MUL/MLA instruction",
    "multiply_long": "SMULL/SMLAL instruction",
    "load_dependent": "load-plus-ADD iteration",
    "load_independent": "word load",
    "load_formats": "formatted load",
    "store_reload": "increment/store/reload iteration",
    "block_copy": "32-bit word copied",
    "direct_branch": "loop iteration (ADD/SUBS/BNE)",
    "call_return": "leaf call (BL/ADD/MOV pc,lr)",
    "cp15_reads": "CP15 read",
    "cache_line_stride": "cold word load with 256-byte stride",
}


def make_report(manifest, rows):
    # Infer selected traffic settings, but require every manifest kernel and
    # every pinned variant. Partial attempts remain explicitly incomplete.
    settings = sorted({tuple(r[k] for k in ("mode", "profile", "seed", "jitter"))
                       for r in rows if "case" in r})
    indexed = {}
    for row in rows:
        if "case" not in row:
            continue
        key = tuple(row[k] for k in ("variant", "case", "mode", "profile", "seed", "jitter"))
        if key in indexed:
            raise ValueError("duplicate observation")
        indexed[key] = row
    expected = [(variant, case["id"], *setting) for variant in VARIANTS
                for case in manifest["benchmarks"] for setting in settings]
    missing = [list(key) for key in expected if key not in indexed]
    comparisons = {a + "__" + b: compare_rows([r for r in rows if "case" in r], a, b) for a, b in PAIRS}
    repeats = deterministic_repeats(rows)
    control = controller_negative_control(rows)
    counters = proxy_counter_checks(rows)
    fills = cold_refill_counter_checks(rows)
    complete = (bool(settings) and not missing and all(r["status"] == "PASS" for r in rows)
                and all(r["status"] == "PASS" for r in repeats + control + counters + fills)
                and bool(control))
    failed = any(r["status"] == "FAIL" for r in rows + repeats + control + counters + fills)
    return dict(status="PASS" if complete else "FAIL" if failed else "BLOCKED", observations=len(indexed),
                statuses=dict(Counter(r["status"] for r in rows)), missing=missing,
                deterministic_repeats=repeats, controller_negative_control=control,
                proxy_counter_checks=counters,
                cold_refill_counter_checks=fills,
                comparisons=comparisons)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name")
    parser.add_argument("attempt")
    args = parser.parse_args()
    if not args.attempt.isdigit() or len(args.attempt) != 4:
        parser.error("attempt must be four digits")
    _, output = locations(args.name)
    manifest = json.loads((output / "manifest.json").read_text())
    validate_frozen(manifest)
    directory = output / "attempts" / args.attempt
    result = json.loads((directory / "result.json").read_text())
    report = make_report(manifest, result["rows"])
    report.update(experiment=args.name, attempt=args.attempt, image_id=result.get("image_id"),
                  variants={name: {k: v[k] for k in ("commit", "kind", "source_id")}
                            for name, v in manifest["variants"].items() if "source_id" in v},
                  harness_sha256=manifest["harness_sha256"], memory_model=manifest["memory_model"],
                  operation_units=OPERATION_UNITS,
                  limitations=["Partial phase00/01; no complete ISA/CPI, physical controller, resource, routed timing or gameplay claim",
                               "Warm-up windows excluded from body medians; retire_proxy is not architectural instructions",
                               "No overall score: full benchmark groups/weights remain to be frozen before imports"])
    report["builds"] = {}
    for variant, mode in sorted({(r["variant"], r["mode"]) for r in result["rows"] if "case" in r}):
        build = directory / variant / mode
        log = build / "build.log"
        executable = build / "obj/Vbench"
        report["builds"][variant + "/" + mode] = dict(
            executable_sha256=digest(executable.read_bytes()), build_log_sha256=digest(log.read_bytes()),
            command=json.loads(log.read_text().splitlines()[0]))
    write_json(directory / "report.json", report)
    csv_text = io.StringIO()
    columns = ("variant", "case", "mode", "profile", "seed", "jitter", "status", "body_cycles_median",
               "operations", "operation_unit", "cycles_per_operation", "source_id", "binary_sha256", "harness_sha256", "log")
    writer = csv.DictWriter(csv_text, fieldnames=columns, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(dict(r, operation_unit=OPERATION_UNITS[r["case"]]) for r in result["rows"] if "case" in r)
    (directory / "report.csv").write_text(csv_text.getvalue())
    lines = ["# Frozen CPU baseline: first ARM batch", "", f"Experiment `{args.name}`, attempt `{args.attempt}`: **{report['status']}**.", "",
             "Values are median body clocks; initial two warm-ups are excluded. Each cell lists seeds in order. "
             "This is synthetic memory, not SDRAM timing or FPS. H0 uses scalar refill even in the line-mode comparison.", ""]
    rows = [r for r in result["rows"] if "case" in r]
    for mode, profile, jitter in sorted({(r["mode"], r["profile"], r["jitter"]) for r in rows}):
        lines += [f"## {mode}, I:D waits {profile}, jitter {jitter}", "",
                  "| Case | H0 | H1 | Frozen current | Current + old SDRAM |", "| --- | ---: | ---: | ---: | ---: |"]
        for case in manifest["benchmarks"]:
            cells = [case["id"]]
            for variant in VARIANTS:
                selected = sorted((r for r in rows if (r["variant"], r["case"], r["mode"], r["profile"], r["jitter"])
                                   == (variant, case["id"], mode, profile, jitter)), key=lambda r: r["seed"])
                cells.append(" / ".join(str(r["body_cycles_median"]) if r["status"] == "PASS" else r["status"]
                                        for r in selected) or "NOT_RUN")
            lines.append("| " + " | ".join(cells) + " |")
        lines.append("")
    lines += [f"Deterministic pairs: {dict(Counter(r['status'] for r in report['deterministic_repeats']))}.", "",
              f"Controller negative controls (all windows and whole-run counters): {dict(Counter(r['status'] for r in report['controller_negative_control']))}.", "",
              "Per-case cycle savings and throughput gains are separate fields in report.json. "
              "H1→current includes intervening CPU changes. There is no overall score for this partial suite.", ""]
    lines += ["## Useful operation definitions", "", "| Case | Count | Unit |", "| --- | ---: | --- |"]
    lines += [f"| {case['id']} | {case['operations']} | {OPERATION_UNITS[case['id']]} |"
              for case in manifest["benchmarks"]]
    lines += ["", "Cycles per operation include the closing NOP and the complete named body. "
              "A compound iteration is not one architectural instruction, and these ratios are not isolated load/branch latency.", ""]
    (directory / "report.md").write_text("\n".join(lines))
    print(f"{report['status']}: {report['observations']} observations, {len(report['missing'])} missing")
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
