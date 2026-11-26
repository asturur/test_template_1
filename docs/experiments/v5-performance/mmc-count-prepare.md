# Prepare the next MMC FIFO byte counter group

The [design patch](patches/mmc-count-prepare.patch) starts at `11c4a0c`,
the exact retained 104 MHz tree. It changes `rtl/ngage_mmc_host.v`.
The host already transfers up to four bytes per accepted CPU or DMA
FIFO operation. Keep the next value of the upper ten counter bits
in a register. Calculate the low three bits and their carry before
applying the bus acceptance. A crossed group updates the upper count
and its saved successor on the original edge. Reset and transfer start
clear the count and reinitialize the successor. The MMC divider, bus
admission, pointers, card state and data edges follow the existing RTL.

The retained fits show the following counts of below-target setup paths
ending at `nfifo`, the guest-to-FIFO byte counter. The path families
include the UPP address/claim chain and late LCD reservation. Several
continue through `mmc_accept` and the full carry chain. The prepared
counter removes that carry chain from the upper-bit data update.
Routed checks remain open.

| Retained seed | Hot paths below −1.5 ns | Cold paths below −1.5 ns | Worst named `nfifo` slack |
| ---: | ---: | ---: | ---: |
| 43 | 16 | 6 | −1.910 ns |
| 13 | 15 | 15 | −1.932 ns |
| 31337 | 12 | 14 | −2.243 ns |

The standalone 104 MHz production candidate is `9a02faf`, the child
of forward restore `2e410c9`. The restore matches the retained tree.
The fitter uses the same-day `81a1b45` controls with DDR debugging off.
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45793456733) ·
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45793453000) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45793455943)

## Routed results

| Seed | Retained setup | Prepared setup | Change | Retained ALMs | Prepared ALMs |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 13 | −2.061 ns | −3.316 ns | −1.255 ns | 36,420 | 36,055 |
| 43 | −2.508 ns | −2.811 ns | −0.303 ns | 36,446 | 36,014 |
| 31337 | −2.471 ns | −2.765 ns | −0.294 ns | 36,461 | 36,017 |
| Median | −2.471 ns | −2.811 ns | −0.340 ns | 36,446 | 36,017 |

Park `9a02faf` as an area-saving option. Median area fell by 429 ALMs
and all fits used 321 M10Ks. The named `nfifo` hot paths fell from
15/16/19 to 2/4/11 for seeds 13/43/31337. The worst remaining named
path at that destination lost 0.153–0.180 ns. Median core setup TNS
fell from −5143.651 to −7282.192 ns. The limiting paths move through
SDRAM request handling or reset to I-cache readiness/Wishbone address.
All three passed hold, recovery, removal, pulse width and SDRAM pin
packing, and failed setup. The best candidate RBF is
`build/fit/v5-104mhz-9a02faf-seed31337/ngage1.rbf`.
Forward restore `88796f65` returns to the exact retained tree.
[Matched fit and route evidence](../../evidence/v5-104-mmc-count-prepare-fits.json)

## Qualification

The arithmetic checks cover every byte mask and remaining count,
and every initial counter value and accepted increment from zero to
four. The pin-based CMD16, integer-clock and three data peers match
the control. The internal observer compares the complete counter and
the saved group against the original expressions on every clock. The
additional 4 KiB TX and RX cases match in 258,366 clocks and cross
1,278 eight-byte boundaries. The mixed 104 MHz board replay matches
all 171,496 SDRAM, PCM, LCD and MMC records. All 105 fixed workload
windows and four native PolyCount frames match the retained cycles,
outputs and traces. [Verification receipt](../../evidence/v5-104-mmc-count-prepare.json)

## Replay

Use the [fixture patch](patches/mmc-count-prepare-replay.patch). To rerun
the host comparison, stage the retained RTL and unit tests under both
`reference` and `source` and apply the design patch to `source`.

```sh
catalog=docs/experiments/v5-performance
area=scratch/v5-fit-loop/mmc-count-prepare
git apply "$catalog/patches/mmc-count-prepare-replay.patch"
for leg in reference source; do
  mkdir -p "$area/$leg"
  git archive 11c4a0c rtl/ngage_mmc_host.v tests/phone/mmc_host | tar -x -C "$area/$leg"
done
git apply --directory="$area/source" "$catalog/patches/mmc-count-prepare.patch"
python3 -B "$area/check-arithmetic.py"
python3 -B "$area/prepare-host-tests.py"
for leg in reference source; do
  (
    cd "$area/$leg"
    sh tests/phone/mmc_host/run.sh
    out=build/sim/unit-mmc-host
    iverilog -g2001 -s tb -Ptb.DIV=3 -o "$out/long" rtl/ngage_mmc_host.v "$out/long_tb.v"
    vvp "$out/long"
  )
done
```

For the mixed replay, prepare the [retained pin model](prepared-wb-write-data.md#reapply-and-verify),
run `python3 -B "$area/mixed.py"`, and repeat the build and trace comparison
in `build/sim/v5-104-mmc-count-prepare-pin-mixed/mixed`.
For the fixed and native replay, copy the retained CPU netlist and
wrapper, DDR stream, UPP and DMA source into the scratch leg as in the
[previous runner](live-rs-prep.md#reproduce). Copy the two observers and
run this fixture's `replay.py` with `fixed` and `native` and
`--output qualification`.

## Combined replay with separate SDRAM write replies

Applying the [Wishbone design patch](patches/wb-reply-class.patch) and
the MMC design patch to `11c4a0c` reproduces the combined `347e5aa` tree.
The archive verifier checks all ten changed file hashes. The combined
RTL passed both directed suites, including 258,366 clocks of 4 KiB MMC
reads and writes and 42 directed Wishbone edges. The real SDRAM mixed
test matched 171,496 events over 1,201,547 clocks and observed 18,945
D-only write replies. All 105 fixed windows and the four native frames
(57,508,371 clocks) also matched. [Combined receipt](../../evidence/v5-104-wb-mmc-combined.json)

Use the [Wishbone replay recipe](wb-reply-class.md#replay) in a fresh
`scratch/v5-fit-loop/wb-mmc-combined-replay` directory at the same depth
as the original. Apply both design patches and the directed Wishbone
fixture. Copy `replay.py`, `qualify_bench.py` and `prepare_mixed.py`
from the standalone Wishbone replay tools into the combined source's
`build/reply-class` directory. Apply the
[runner override](patches/wb-mmc-replay-overrides.patch) there with
`patch -p1` so both simulation recipes compile and check the MMC file.
The MMC directed checks use the same host fixture steps as the
standalone test above, with the combined RTL in the candidate directory.
