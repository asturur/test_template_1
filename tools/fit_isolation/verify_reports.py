#!/usr/bin/env python3
"""Check fit coverage, retaining the official reports as the source of truth."""

import argparse
import csv
import json
from pathlib import Path


CPU = {"ngage_cpu", "ngage2_arm925t", "ngage2_zap_cache", "ngage2_zap_dcache",
       "ngage2_zap_tlb", "ngage_arm9v2_refill"}
BOARD = {"ngage_upp", "ngage_sdram_scheduler", "ngage_sdram_line_mux", "ngage_lcd_stream",
         "ngage_dma_engine", "ngage_mmc_host", "ngage_mmc_card", "ngage_game_pcm",
         "ngage_ddr_flash_cache", "ngage_am29n643_state"}
GROUPS = {"dut-to-dut", "dut-to-harness", "harness-to-dut", "harness-to-harness"}


def fit_inventory(report):
    entities = []
    rams = []
    target = None
    headers = ()
    with report.open(errors="replace") as stream:
        for line in stream:
            if not line.startswith(";"):
                continue
            fields = [field.strip() for field in line.split(";")[1:-1]]
            if len(fields) == 1:
                target = rams if fields == ["Fitter RAM Summary"] else None
                headers = ()
            if "Full Hierarchy Name" in fields and "M10Ks" in fields:
                target, headers = entities, fields
            elif target is rams and {"Name", "Type", "Port A Depth"}.issubset(fields):
                headers = fields
            elif target is not None and headers and len(fields) == len(headers):
                target.append(dict(zip(headers, fields)))
    return entities, rams


def path_count(path):
    with path.open(newline="") as stream:
        return sum(1 for _ in csv.DictReader(stream))


def check_timing(timing, errors):
    export_errors = timing / "export-errors.txt"
    if not export_errors.is_file():
        errors.append("Missing TimeQuest export log")
    elif export_errors.stat().st_size:
        errors.append("One or more TimeQuest exports failed. See export-errors.txt.")

    corners = sorted(timing.glob("corner-*"))
    if len(corners) != 4:
        errors.append(f"Expected four operating corners, found {len(corners)}")
    for corner in corners:
        for name in ("fmax.rpt", "constraints.rpt", "unconstrained.rpt", "check-timing.rpt",
                     "physical-clock.txt", "core-setup-full.rpt", "groups.tsv"):
            if not (corner / name).is_file():
                errors.append(f"{corner.name} lacks {name}")
        for name in ("worst-setup.csv", "core-setup.csv"):
            path = corner / name
            if not path.is_file() or path_count(path) != 1000:
                errors.append(f"{corner.name} lacks 1000 paths in {name}")
        group_report = corner / "groups.tsv"
        if group_report.is_file():
            with group_report.open(newline="") as stream:
                groups = {row["group"]: row for row in csv.DictReader(stream, delimiter="\t")}
            for group in GROUPS:
                record = groups.get(group, {})
                count = record.get("reported_paths", "")
                if not count.isdigit() or int(count) < 1:
                    errors.append(f"{corner.name} has no {group} paths")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("cpu-only", "board-only"))
    options = parser.parse_args()
    output = Path("output_files")
    errors = []
    entities, rams = fit_inventory(output / "Template.fit.rpt")
    found = {row["Entity Name"] for row in entities}
    if options.mode == "cpu-only":
        required = CPU | {"ngage_cpu_isolation_peer"}
        excluded = BOARD
        if sum(row["Entity Name"] == "ngage2_zap_tlb" for row in entities) != 2:
            errors.append("CPU-only fit does not show both MMU TLB instances")
        for name in ("ngage2_zap_cache", "ngage2_zap_dcache"):
            if not any(row["Entity Name"] == name and int(row["M10Ks"].split()[0]) > 0 for row in entities):
                errors.append(f"No physical RAM blocks in {name}")
    else:
        required = BOARD | {"ngage_timing_board_cpu"}
        excluded = CPU
    if required - found:
        errors.append(f"Missing required fitted entities: {', '.join(sorted(required - found))}")
    if excluded & found:
        errors.append(f"Unexpected fitted entities: {', '.join(sorted(excluded & found))}")
    if not rams:
        errors.append("No fitted RAM inventory")
    check_timing(output / "timing", errors)

    report = {"mode": options.mode, "coverage_ok": not errors, "errors": errors,
              "entities": [row for row in entities if row["Entity Name"] in required | excluded],
              "fitted_ram_rows": rams}
    (output / "diagnostic-coverage.json").write_text(json.dumps(report, indent=2) + "\n")
    if errors:
        parser.exit(1, "\n".join(errors) + "\n")
    print(f"PASS {options.mode} fit inventory and timing export. Check measured slack separately.")


if __name__ == "__main__":
    main()
