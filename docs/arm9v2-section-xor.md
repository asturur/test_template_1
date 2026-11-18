# v5 data-side section TLB index

A read/write hook on the existing Sega Rally Unicorn oracle recorded
512,682 accesses in the `0x80000000` section and 109,848 in the
`0x10000000` section over one original 36,608-pixel frame. The oracle
passed its output and guard checks. Both virtual sections select index
zero in v5's direct-mapped 64-entry section TLB (`VA[25:20]`). A shadow
replay of the guest accesses gives 109,849 cold-start misses with that
index. A 64-entry index that XORs the two six-bit halves of the section
number gives two cold misses. A two-way table with 32 sets also gives two.
The shadow covers guest data accesses. The RTL scoreboard counts accepted
table bus beats and includes the harness around the frame.

The v5 netlist uses the folded D-side section index. It uses
`VA[25:20] ^ VA[31:26]` for both lookup and refill, retaining the original
upper tag. The index plus tag uniquely identifies each of the 4,096
virtual sections. The I-side section index and all other page banks use
the original RTL.

## Matched RTL results

Both builds pass all 15 retained payloads at both memory profiles with
two repeat runs and output checks. Each cell gives median CPU clocks at
`0:0 / 2:9` added I:D waits.

| Payload | Direct index | XOR index |
| --- | ---: | ---: |
| Sega Rally full frame | 3,461,218 / 4,502,989 | 2,360,190 / 2,441,229 |
| SPMark matrix | 17,437 / 17,793 | 17,271 / 17,382 |
| SPMark transpose | 1,899 / 2,583 | 1,620 / 1,803 |
| SPMark triangle edges | 12,634 / 13,430 | 11,832 / 11,931 |
| GLES full-frame fill | 92,612 / 237,167 | 92,605 / 237,155 |
| GLES halfword tail | 707 / 724 | 696 / 702 |
| GLES byte tail | 716 / 727 | 717 / 723 |
| Thumb JPEG | 35,913 / 35,921 | 35,903 / 35,903 |

Sega Rally takes 31.81% and 45.79% fewer clocks. In every scored frame,
D-side table beats fall from 109,850 to zero. Both versions still perform
4,633 D-cache refills and write back 17,096 words. The six-kernel SPMark
geometric throughput improves by 4.23% and 9.37%. The short game loops
move by less than 0.7%. The byte-tail test at `0:0` takes one extra cycle.

The full-phone replay with modeled DDR/SDRAM, 78 MHz CPU, 39 MHz MMC,
8 KiB D2, and 64 Hz NOS also passes. Median frame clocks fall from
3,975,090 to 2,383,065, a 40.05% reduction. Both builds pass the same
checked output and guard tests twice and reject the corrupted output
control with identical guest and helper work.

The directed guest makes four alternating reads of two sections and
checks that one maps to RAM and the other to a device. It repeats the
same reads after CP15 data-TLB invalidation. Each pass sees eight
section descriptor reads on the control and two on the candidate,
with both burst modes and at both directed wait settings. The remaining
CPU/bus contracts pass in the same runs.

Both stock-firmware cold runs reach the same byte-identical Nokia logo
framebuffer at 400 million clocks, with zero data-bus errors. The
control and folded variants reach the measured frame milestone at
295,684,044 and 295,687,101 clocks respectively. The three early bus
errors and the unsupported LCD flag occur in both runs. The evidence
includes the matched source and firmware provenance, frame digests, and
replay receipts.

[Matched benchmark and contract evidence](evidence/arm9v2-section-xor-20261118.json).

## Replay

The normal `ngage-v5` build selects the verified folded netlist. Run the
section-translation contract with the installed offline simulator.

```sh
ARM9V2_SECTION_INDEX=xor sh tests/cpu/arm9v2_board/run-contract.sh fresh-xor
```

To reproduce the direct-index control, extract the previous phone netlist
and select the expected eight descriptor reads per trial.

```sh
mkdir -p build/arm9v2-section-xor
git show 2a84b50:rtl/arm9v2/arm925t_phone.v > build/arm9v2-section-xor/direct.v
ARM9V2_SECTION_INDEX=direct ARM9V2_NETLIST=build/arm9v2-section-xor/direct.v \
  sh tests/cpu/arm9v2_board/run-contract.sh fresh-direct
```
