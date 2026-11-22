#!/usr/bin/env python3
"""Summarize a paired phone replay and its separate RAM-tap calibration."""

import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import json
from pathlib import Path
import re

from PIL import Image


REGIONS = ("upload", "raw", "mdi_ring", "mdi_pointers", "mdi_control")
RAM_REGIONS = ("upload", "raw")
PHASES = {
    "cold": "cold_startup",
    "phone": "phone_ui",
    "launch": "game_launch_to_first_pcm",
    "audio_intro": "first_game_audio",
    "audio_after_input": "game_after_input",
    "late_audio": "late_game_runtime",
}


def access_detail(rows):
    widths = Counter()
    words, bytes_used, pcs = set(), set(), set()
    for row in rows:
        addr, mask = int(row["address"], 16), int(row["mask"], 16)
        lanes = [lane for lane in range(4) if mask & (0xFF << (8 * lane))]
        widths[len(lanes)] += int(row["count"])
        words.add(addr)
        bytes_used.update(addr + lane for lane in lanes)
        pcs.add("0x" + row["first_pc"])

    data = {
        "accesses": sum(widths.values()),
        "by_width_bytes": dict(sorted(widths.items())),
        "distinct_word_addresses": len(words),
        "distinct_byte_addresses": len(bytes_used),
        "byte_span": [f"0x{min(bytes_used):08x}", f"0x{max(bytes_used):08x}"],
        "first_s": min(float(row["first_s"]) for row in rows),
        "last_s": max(float(row["last_s"]) for row in rows),
        "first_seen_pc_count": len(pcs),
    }
    if len(pcs) <= 4:
        data["first_seen_pcs"] = sorted(pcs)
    return data


def summarize_run(directory):
    trace = (directory / "trace.log").read_text()
    grouped = defaultdict(list)
    with (directory / "accesses.tsv").open() as accesses:
        for row in csv.DictReader(accesses, delimiter="\t"):
            grouped[row["phase"], row["region"], row["op"]].append(row)

    start = re.search(r"^START ([\d.]+)$", trace, re.M)
    end = re.search(r"^END ([\d.]+) completed=true samples=(\d+) nonzero=(\d+)$", trace, re.M)
    if not start or not end:
        raise ValueError(f"Incomplete replay in {directory}")
    boundaries = [("cold", float(start[1]))]
    boundaries.extend((phase, float(t)) for t, phase in re.findall(r"^PHASE ([\d.]+) (\w+)$", trace, re.M))
    nonzero_by_phase = dict(re.findall(r"^PCM (\w+) (\d+)$", trace, re.M))

    phases = []
    ends = [t for _, t in boundaries[1:]] + [float(end[1])]
    for (phase, start_time), end_time in zip(boundaries, ends, strict=True):
        counts, details = {}, {}
        for region in REGIONS:
            counts[region] = [
                sum(int(row["count"]) for row in grouped[phase, region, direction])
                for direction in ("R", "W")
            ]
            if region in RAM_REGIONS and any(counts[region]):
                details[region] = {
                    direction: access_detail(grouped[phase, region, direction])
                    for direction in ("R", "W") if grouped[phase, region, direction]
                }
        phase_result = {
            "phase": PHASES[phase],
            "time_s": [start_time, end_time],
            "nonzero_emulated_pcm_samples": int(nonzero_by_phase.get(phase, 0)),
            "reads_writes": counts,
        }
        if details:
            phase_result["ram_access_detail"] = details
        phases.append(phase_result)

    screens = []
    for t, frame, samples in re.findall(r"^SNAP ([\d.]+) (\d+) nonzero=(\d+) error=nil$", trace, re.M):
        name = f"screen-{int(frame):02}.png"
        with Image.open(directory / name) as image:
            digest = hashlib.sha256(image.convert("RGB").tobytes()).hexdigest()
        screens.append({
            "time_s": float(t),
            "filename": name,
            "rgb_sha256": digest,
            "nonzero_emulated_pcm_samples_so_far": int(samples),
        })
    first_audio = re.search(r"^FIRST_AUDIO ([\d.]+)$", trace, re.M)
    return {
        "end_s": float(end[1]),
        "audio": {
            "first_nonzero_s": float(first_audio[1]) if first_audio else None,
            "sample_rate_hz": 16000,
            "total_elapsed_samples": int(end[2]),
            "nonzero_samples": int(end[3]),
        },
        "phases": phases,
        "screens": screens,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_dir", type=Path, help="Directory with calibration, sega and sonic run outputs")
    args = parser.parse_args()
    calibration = (args.output_dir / "calibration/trace.log").read_text()
    checks = re.findall(r"^([a-f0-9]{8}) ([a-f0-9]{8}) ([RW]) count=(\d+)$", calibration, re.M)
    if len(checks) != 12 or "PASS calibrated both physical windows" not in calibration:
        raise ValueError("Missing successful RAM-tap calibration")
    print(json.dumps({
        "calibration": {
            "passed": True,
            "address_mask_direction_count": [[f"0x{a}", f"0x{m}", d, int(n)] for a, m, d, n in checks],
        },
        "runs": {game: summarize_run(args.output_dir / game) for game in ("sega", "sonic")},
    }, indent=2))


if __name__ == "__main__":
    main()
