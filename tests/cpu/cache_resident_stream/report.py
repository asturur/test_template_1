#!/usr/bin/env python3
"""Capture source identity and summarize independently checked simulation events."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
NAMES = ["successive_words_both_halves", "alternating_two_lines", "same_word_partial_bytes",
         "lower_half_only", "upper_half_only"]
PREFIXES = ("OFFER ", "EDGE ", "ACCEPT ", "RESPONSE ", "COMMIT ", "SUMMARY ", "HIST ", "VERIFIED ", "PASS:")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_hashes():
    paths = [ROOT / "rtl/ngage_bram.v", *sorted((ROOT / "rtl/arm920").glob("*.sv")),
             *sorted((ROOT / "tests/cpu/cache_resident_stream").glob("*.*")),
             ROOT / "tests/cpu/cache_resident/test.v", ROOT / "tests/cpu/cache_resident/sim.sh"]
    return {str(p.relative_to(ROOT)): digest(p) for p in paths if p.is_file()}


def command(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def records(path):
    return [s for s in path.read_text().splitlines() if s.startswith(PREFIXES)]


def fields(line):
    return {k: int(v) for k, v in re.findall(r"(\w+)=([0-9]+)(?: |$)", line)}


def report(out):
    identity = json.loads((out / "source.json").read_text())
    if identity["sha256"] != source_hashes():
        raise SystemExit("Sources changed during simulation")
    normal = records(out / "normal.log")
    if normal != records(out / "repeat.log"):
        raise SystemExit("Repeat event streams differ")
    if not any(s.startswith("PASS:") for s in normal):
        raise SystemExit("Normal run did not pass")
    negative = (out / "negative.log").read_text()
    if "checker byte mismatch (negative control=1)" not in negative:
        raise SystemExit("Wrong-byte control did not fail as expected")
    streams = []
    for line in normal:
        if not line.startswith("SUMMARY "):
            continue
        row = fields(line)
        sid = row["stream"]
        row["name"] = NAMES[sid]
        offers = [fields(s) for s in normal if s.startswith(f"OFFER stream={sid} ")]
        row["offered_edges"] = len(offers)
        row["backpressured_offer_edges"] = sum(not e["ready"] for e in offers)
        row["accept_intervals"] = {}
        row["commit_intervals"] = {}
        for hist in normal:
            if hist.startswith(f"HIST stream={sid} "):
                h = fields(hist)
                if h["accepts"]:
                    row["accept_intervals"][h["interval"]] = h["accepts"]
                if h["commits"]:
                    row["commit_intervals"][h["interval"]] = h["commits"]
        for event, count in (("ACCEPT", "accepted"), ("COMMIT", "committed"), ("RESPONSE", "responses")):
            events = [fields(s) for s in normal if s.startswith(f"{event} stream={sid} ")]
            if len(events) != row[count] or [e["id"] for e in events] != list(range(256)):
                raise SystemExit(f"{event} count/order mismatch")
            if event != "RESPONSE":
                kind = "accept" if event == "ACCEPT" else "commit"
                if (events[0]["edge"], events[-1]["edge"]) != (row[f"first_{kind}"], row[f"last_{kind}"]):
                    raise SystemExit("Summary edge mismatch")
                row[f"{kind}_stores_per_clock"] = (len(events)-1)/(events[-1]["edge"]-events[0]["edge"])
        row["dirty_verification"] = next(s for s in normal if s.startswith(f"VERIFIED stream={sid} "))
        streams.append(row)
    if len(streams) != 5:
        raise SystemExit("Missing stream")
    result = {
        "source": identity, "raw_output": str(out.relative_to(ROOT)),
        "edge_convention": "Edge 1 is first clock posedge. Offer/ready/response/data-RAM write ports sampled before NBA; RAM and tag bytes checked at +1ns. Driver changes at negedge.",
        "streams": streams, "correctness": "PASS: ordered exactly-once responses and actual RAM writes, slot/word/mask/enabled bytes, full post-write word, dirty tag halves, ordinary readback and clean backing bytes; second clean produces zero writes",
        "repeat": "PASS: all events, edges, summaries and checks identical; exclude Verilator walltime footer",
        "negative_control": "PASS: +corrupt_expected fails at first RAM commit with checker byte mismatch (negative control=1)",
        "logs_sha256": {name: digest(out/name) for name in ("normal.log", "repeat.log", "negative.log")},
        "adjacent_trace": [s for s in normal if s.startswith("EDGE stream=0 ")],
    }
    (out / "result.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    mode, directory = sys.argv[1:]
    out = (ROOT / directory).resolve()
    if mode == "snapshot":
        identity = {"revision": command("git", "rev-parse", "HEAD"),
                    "branch": command("git", "branch", "--show-current"),
                    "working_tree": command("git", "status", "--short"),
                    "production_diff": command("git", "diff", "HEAD", "--", "rtl", "Template.sv"),
                    "image": command("docker", "image", "inspect", "jotego/simulator:arm64", "--format", "{{.Id}}"),
                    "sha256": source_hashes()}
        (out / "source.json").write_text(json.dumps(identity, indent=2) + "\n")
    elif mode == "report":
        report(out)
    else:
        raise SystemExit("Expected snapshot or report")
