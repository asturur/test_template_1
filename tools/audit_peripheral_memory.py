#!/usr/bin/env python3
"""Extract non-overlapping peripheral resource rows from a retained Quartus fit.

Read-only: no network, builds, Git operations or modification of fit artifacts.
ALMs in parentheses are direct; memory counts include children. Never sum a
selected parent with its child. Source hashes permit comparison after promotion.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NODES = (
    "ngage_bram_be:upload_ram", "ngage_bram_be:nosmem_ram",
    "ngage_bram_be:aux_ram", "ngage_bram_be:gpio15_ram",
    "ngage_bram_be:nos4k_ram_i", "ngage_boot_regs:boot_regs",
    "ngage_icu_extra:extra_regs", "ngage_sparse_regs:d_regs",
    "ngage_cbus_uem:cbus", "ngage_upp_euart:euart1",
    "ngage_upp_mdi:upp_mdi", "ngage_mmc_host:mmc_enabled.host",
    "ngage_mmc_card:mmc_shortcut.card", "ngage_simif:simif_enabled.simif",
)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("fit", type=Path)
    ap.add_argument("--summary", type=Path, required=True)
    args = ap.parse_args()
    summary = json.loads(args.summary.read_text())
    expected = summary["source"]["compiled_source_sha256"]
    rows = []
    active = False
    for line in args.fit.read_text(encoding="latin1").splitlines():
        if "; Compilation Hierarchy Node " in line:
            active = True
            continue
        if not active:
            continue
        c = [v.strip() for v in line.split(";")[1:-1]]
        if len(c) < 17 or c[0].strip("|") not in NODES:
            continue
        rows.append(dict(node=c[0].strip("|"), hierarchy=c[14],
                         alm_inclusive=float(c[1].split()[0]),
                         alm_direct=float(c[1].split("(")[1].rstrip(")")),
                         registers_inclusive=int(c[7].split()[0]),
                         registers_direct=int(c[7].split("(")[1].rstrip(")")),
                         memory_bits=int(c[9]), m10ks=int(c[10])))
    assert len(rows) == len(NODES), (len(rows), len(NODES))
    assert len({r["node"] for r in rows}) == len(NODES)
    # Selected subtrees are disjoint, including the MDI peer only via its parent.
    for a in rows:
        for b in rows:
            if a is not b:
                assert not b["hierarchy"].startswith(a["hierarchy"] + "|")
    sources = {}
    for name in ("Template.sv", "rtl/ngage_upp_peripherals.v", "rtl/ngage_bram.v",
                 "rtl/ngage_bram_be.v", "rtl/ngage_upp_mdi.v", "rtl/ngage_boot_regs.v",
                 "rtl/ngage_icu_extra.v", "rtl/ngage_cbus_uem.v", "rtl/ngage_sparse_regs.v",
                 "rtl/ngage_upp_euart.v", "rtl/ngage_mmc_card.v", "rtl/ngage_mmc_host.v",
                 "rtl/ngage_simif.v", "rtl/ngage_sdram_adapter.v"):
        sha = digest(ROOT / name)
        sources[name] = dict(sha256=sha, matches_fit=sha == expected.get(name))
    inventory = sorted({int(line.split()[0], 16) for line in
                        (ROOT / "tests/phone/board_inventory/addresses.tsv").read_text().splitlines()
                        if line.strip()})
    nos = [a for a in inventory if a >> 16 == 0x0c10]
    banks = [r for r in rows if r["node"] in
             ("ngage_bram_be:upload_ram", "ngage_bram_be:nosmem_ram")]
    assert sum(r["m10ks"] for r in banks) == 128
    print(json.dumps(dict(
        fit_path=str(args.fit), fit_sha256=digest(args.fit),
        fit_commit=summary["source"]["actual_commit"],
        seed=summary["source"]["seed"], debugger=summary["source"]["debugger"],
        resources={k: summary["resources"][k] for k in
                   ("ALMs", "registers", "M10Ks", "occupied_LABs")},
        independent_subtrees=rows, sources=sources,
        retained_inventory=dict(nos_addresses=[f"{a:08x}" for a in nos],
                                generic_tail_addresses=sum(a >= 0x0c1003f0 for a in nos),
                                runtime_access_counts_available=False),
        two_banks=dict(m10ks=128, alm_inclusive=sum(r["alm_inclusive"] for r in banks)),
        tlb_reservation=dict(unfitted_extra_m10ks=[10, 16], remaining_after_reservation=[35, 41]),
    ), indent=2))


if __name__ == "__main__":
    main()
