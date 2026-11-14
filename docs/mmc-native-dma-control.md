# Native MMC receive uses DMA control2

## Hardware result after the R2 fix

Build43603176364, commit199a9d5, seed44, RBF SHA256
`1a1719ce00430cd546dde5f06fc8f85c90cea2cd59811ce5a8daf48eae7e318a`
passes constrained78MHz timing (minimum setup+0.325ns, hold+0.216ns). It fits
37,826/41,910ALMs (90%),508/553M10Ks (92%).104MHz remains the design objective.
Original-ROM boot with the existing card now reads payload sectors, but stays
at Nokia. A guarded observation-only trace confirms exact original CID/CSD:

- CMD2: `00000053504d41524b10c0eb55d8bfbd`, native error0.
- CMD9: `8c0f002a0179a3ffb6c081e18a40001f`, native error0.
- CMD3/13/7/16 also succeed. CMD17 argument0/length512 receives its response,
  then waits with raw status4/data-busy. No DMA/data completion follows.

Thus the previous R2 correction is qualified on hardware; native filesystem
mounting and SPMark execution remain unverified.

## Exact rejected native descriptor

A passive register observer immediately after the original DMA start returns:

| Field | Value |
| --- | --- |
| Channel |0 |
| Request selector |2 |
| Interrupt enable |1 |
| Run register |0 (already rejected) |
| Source |10120624, fixed,8bits |
| Destination |0afe6cb4, increment mode4,32bits |
| Count |1ff =512byte peripheral units |

The unmodified receive chain is EPBUS503f57bc → import503fc318 → kernel50330ad4
→5032170c. At5032177c it loads control2 before the original control-write helper
50324bac. The donor also accepts control2 for both peripheral directions.
Our production filter required control3 for MMC RX, producing a zero-byte
rejected job with no success IRQ. Host data remains busy because nobody drains
the FIFO. Earlier authored RX3 tests missed the real caller's control value.

## Small production correction

Accept control2 for MMC RX. At dispatch, reuse the existing internal RX3 tag for
control2 descriptors with captured selector2 and a fixed source. The guest run
register still reports2, and the correct RX-ready pacing is selected. No added
registers, memories, DSP or general IRQ priority change. The pre-existing RX3
alias is retained for compatibility and separately tested; it is not the native
Nokia receive convention. Captured descriptors remain immutable after launch.

## Verification

| Check | Result |
| --- | --- |
| Original Nokia setup/start/stop on ZAP, production frontend before fix | TX2 passes; RX2 emits diagnostic error04 on channel2, matching rejection |
| Same unchanged instructions with fix, production profile, wait0/3 | Four exact16-byte cases pass11130/16814clocks, IRQ/stop/selector/untouched bytes checked |
| Same original generic profile | Four cases pass11130/16814clocks |
| Real production board/card/HPS/ZAP, native RX2 | Odd/padding, full512-byte DMA/PIO, identity, ICU, write protection pass197627clocks/4HPSreads |
| Same fixture, CPU Hold during metadata |198041clocks/5HPSreads |
| Production host bus/native-pin peer |30cases/132221clocks |
| All8 DMA channels, TX2/RX2 |96matrix transfers plus focused controls,669385clocks |
| All8 DMA channels, TX2/legacy RX3 |Same coverage,669385clocks |
| Language/style |Strict Verilog-2001 lint and pinned Verible pass |

The native helper test translates5812xxxx MMIO in its fixture and uses a byte
FIFO boundary spy. The separate full composition test supplies the real host,
card and HPS interface. Neither replaces the final native filesystem mount on
FPGA. The live DMA observer performs only passive programming-register reads,
preserves all registers/CPSR/SP, replays the original CMP, retains the checksum
check, and passes384 exact-output/state cases. It is not a startup workaround.
Sources/raw captures are under scratch/mmc-dma-native-20261114 and
scratch/mmc-dma-control2-20261114. New FPGA build/native mount remains the gate.

## Hardware follow-up: mount works

Build43609237775/cd46abe now mounts the same card with original firmware:
16MB capacity,1272kB used,15MB free. SPMark04 launches and presents native
Options/results. Run All Tests reports3D Game failed and no numeric score; the
app remains responsive. See [hardware evidence](mmc-spmark04.md). The first
sector/DMA blocker is passed. This seed has setup-0.270ns, so it is functional
experimental evidence rather than timing-clean release qualification.
