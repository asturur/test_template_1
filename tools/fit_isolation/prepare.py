#!/usr/bin/env python3
"""Select the diagnostic top or CPU boundary in a disposable Git archive."""

import argparse
import hashlib
import json
from pathlib import Path
import re


def replace_unique(path, old, new):
    contents = path.read_bytes()
    if contents.count(old) != 1:
        raise ValueError(f"Expected one {old!r} in {path}")
    path.write_bytes(contents.replace(old, new))


def prepare(project, mode):
    config = project / "Template.qsf"
    files = project / "files.qip"
    directory = project / "tools/fit_isolation"
    config_before = config.read_bytes()
    source_before = {}
    if mode == "cpu-only":
        top = "ngage_cpu_isolation"
        constraints = project / "sys/sys_top.sdc"
        source_before["sys/sys_top.sdc"] = constraints.read_bytes()
        constraints.write_bytes((directory / "cpu_isolation.sdc").read_bytes())
        replace_unique(config, b"TOP_LEVEL_ENTITY sys_top", b"TOP_LEVEL_ENTITY ngage_cpu_isolation")
        selection = "VERILOG_FILE tools/fit_isolation/cpu_isolation.v"
        boundary = "production ngage_cpu; registered memory peer; board omitted"
    else:
        top = "sys_top"
        source = project / "rtl/ngage_cpu.sv"
        # Inherit the exact boundary signature, defaults, and widths. Only the
        # single UPP instance changes selection. Source and board SDC stay intact.
        header, _ = source.read_bytes().split(b"\n);", 1)
        if header.count(b"module ngage_cpu #(") != 1 or b"wb_block_data" not in header:
            raise ValueError("ngage_cpu boundary header changed")
        header = re.sub(
            rb"(?m)^    (output logic[^\n]+\bwb_(?:cyc|lock|address|write|write_data|byte_enable),)$",
            rb"    (* dont_retime *) \1", header,
        )
        generated = directory / "board_master.sv"
        generated.write_bytes(
            header.replace(b"module ngage_cpu #(", b"module ngage_timing_board_cpu #(")
            + b"\n);\n" + (directory / "board_master.vh").read_bytes()
        )
        upp = project / "rtl/ngage_upp.v"
        source_before["rtl/ngage_upp.v"] = upp.read_bytes()
        replace_unique(upp, b"            ngage_cpu #(\n", b"            ngage_timing_board_cpu #(\n")
        selection = "SYSTEMVERILOG_FILE tools/fit_isolation/board_master.sv"
        boundary = "production board; registered CPU transaction peer"

    source_before["Template.qsf"] = config_before
    source_before["files.qip"] = files.read_bytes()
    with files.open("ab") as handle:
        handle.write(f"\nset_global_assignment -name {selection}\n".encode())

    def digest(contents):
        return hashlib.sha256(contents).hexdigest()

    modified = {
        name: {"baseline_sha256": digest(before), "diagnostic_sha256": digest((project / name).read_bytes())}
        for name, before in source_before.items()
        if before != (project / name).read_bytes()
    }
    report = {
        "variant": mode,
        "release_eligible": False,
        "top_level_entity": top,
        "boundary": boundary,
        "expected_system_mhz": 104,
        "ddr_debugger": False,
        "substitutions": modified,
    }
    output = project / "output_files"
    output.mkdir(exist_ok=True)
    (output / "isolation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"{mode} timing diagnostic selected as {top}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--mode", required=True, choices=("cpu-only", "board-only"))
    args = parser.parse_args()
    if (args.project / ".git").exists():
        parser.error("Use a disposable project copy outside the checkout root")
    prepare(args.project, args.mode)


if __name__ == "__main__":
    main()
