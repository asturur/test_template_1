# 104 MHz SDRAM clock forwarding and read capture

2026-11-06 investigation following Terra's single-output/inverted-clock experiment. The maintained top now uses the existing PLL's 104 MHz system output to drive `SDRAM_CLK` through `rtl/ngage_sdram_clock.v` (`altddio_out`). The controller uses `READ_CAPTURE_NEGEDGE=1`. This configuration passes four-state timing-model tests and bounded firmware execution; FPGA fit, TimeQuest closure and real-board operation are **not verified**.

## Root cause measured in the original timing model

The old arrangement used a nominal -90-degree pin clock and sampled DQ on rising system edges. Changing only the pin clock to an inverted system clock moves the SDRAM data-valid window. At the selected 104 MHz clock and default Micron model `tAC=5.4 ns`, `tOH=3.0 ns`, the two rising system edges straddle the entire single-word data window. Neither delaying `rdy` nor preserving an earlier rising-edge sample can manufacture valid input data.

A trace of the first read, using the unmodified four-state reference model:

| Event | Simulation time, ns | Value |
| --- | ---: | --- |
| Rising system edge | 107704.008 | DQ=Z; data not ready |
| SDRAM data becomes valid | 107704.600 | DQ=0000 |
| Falling system edge | 107708.816 | DQ=0000; valid capture point |
| SDRAM releases data | 107711.816 | DQ=Z |
| Next rising system edge | 107713.624 | DQ=Z; register the previously captured word |
| Adapter sees registered ready | 107723.240 | registered controller data=0000 |

These timestamps are from the testbench's quantized nominal 104 MHz period (9.616 ns). For this case, capture lies 4.216 ns after data becomes valid and 3 ns before release. These are ideal model margins, **not fitted FPGA setup/hold slack**. A generic conclusion that 104 MHz cannot work because tAC exceeds half a period was too strong: the appropriate falling-edge capture has nearly a full memory period for access and samples the preceding word before the next update/release.

Sources and small experiments are retained in `scratch/sdram104-review/`; `timing.log` records the table, `inverted.log` reproduces the failure, and `inverted-capture.log` records the successful isolated change. No reference-model timing parameter or original vendor file was changed to obtain the pass. The earlier experiment with reduced tAC is not the solution used here.

## Implemented path

- `rtl/ngage_sdram_clock.v` instantiates `altddio_out`, with high-edge data 0, low-edge data 1, and `outclock=clk_sys`. This forwards an inverted clock through the output IO register, directly to the top-level SDRAM clock pin. The [Altera ALTDDIO_OUT documentation](https://docs.altera.com/r/docs/683148/current/altddio_out-ip-core-signals?contentId=m_dGFzbt~hiDb8vC9SvyhQ) specifies the rising/falling input association and direct pin connection. This matches the local JTFRAME MiSTer 180SHIFT clock-forwarding convention.
- `rtl/sdram/jtframe_sdram64.v` adds the default-off parameter `READ_CAPTURE_NEGEDGE`. With it enabled, one falling-edge register samples physical DQ, and the existing rising-edge `dout` register transfers that word into the original `dst/rdy` timing. Using a falling-edge `dout` alone is insufficient: the next falling edge overwrites it before the adapter consumes `rdy`. The two registers are deliberate.
- `SHIFTED=0`, bank state timing, CAS latency, adapter completion semantics, refresh cadence, CPU frequency and timer assumptions remain unchanged. The parameter defaults to 0 so the existing shifted-clock regression still tests the original interface.
- `Template.sv` connects the DDIO wrapper and selects `READ_CAPTURE_NEGEDGE=1`. The PLL already requests 104 MHz from 50 MHz; its frequency parameters were not changed. Its old -90-degree second output is now unconnected, so no special second-output phase is required by the SDRAM pin path. Removing that unused PLL output is an optional later IP cleanup, requiring actual Quartus validation; no regenerated/compiled PLL is claimed here.
- `files.qip` includes the clock module and requests `FAST_INPUT_REGISTER ON` for `SDRAM_DQ[*]`. This is a placement request, not proof that the register fits in the IO cell. The controller's input register has no reset/enable mux. `useioff` on an internal register was deliberately avoided; the documented attribute applies to top-level ports.

A falling-to-rising internal path has approximately half a system period. That path must meet timing; do not apply an asynchronous clock exception or false-path constraint to hide it.

## Reproducible validation

From the repository root, using the existing image:

```sh
docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c 'sh tests/phone/sdram/run-ddio.sh && sh tests/phone/sdram/run.sh && sh tests/phone/mister_transport/lint-top.sh'
sh tests/phone/sdram/run-verilator-reference.sh
sh tests/phone/hardware_boot/compare-run.sh
```

Results:

- The four-state **negative control**, inverted clock with original rising-only input capture, still fails with Z data on the first read. The test requires that failure, preventing a two-state pass from masking the bug.
- Inverted DDIO clock plus falling/rising capture passes the unchanged Micron test with additional modeled clock-pin delays of 0, 0.25, 0.5 and 1 ns. Each runs all 16 write masks, low/high halfwords, both RAM banks, bank/end boundaries, reset while waiting, short reset followed by a new request, CPU/DMA lock and continuous traffic across 372 refresh commands. No reduced tAC or tOH is used.
- The original -90-degree/default-capture regression and CPU/DMA arbiter tests pass.
- The two-state Verilator reference test also passes, using the already documented test-only DQ/PS2 compatibility treatment where applicable; the four-state result is authoritative for detecting Z in the memory window. `tests/phone/sdram/ddio_model.v` is only an ideal clock-forwarding model, not a vendor primitive timing model, and is never included in `files.qip`.
- The real-controller firmware smoke now uses the nominal **104 MHz inverted DDIO path**, rather than the earlier 100 MHz/-90-degree test clock. It reaches 5M cycles, 375,773 acknowledged transactions, 18 known speculative scratch-fetch faults, no data faults and no LCD pixels. The staged comparison still matches all 102 ordered compact events and 1,016 shadow claims. This is not the Nokia-logo milestone.
- Stubbed top-level elaboration passes; the current log has no LATCH, MULTIDRIVEN or UNOPTFLAT warnings. Remaining width/case/missing-port warnings are not a physical timing result.

Logs: `build/sim/unit-sdram-ddio/`, `build/sim/milestone7/`, `build/sim/unit-hardware-boot-real-sdram/` and small summaries in `scratch/sdram104-review/`. Existing host firmware/C: images were read only; no long firmware run, synthesis, hardware deployment or checkpoint removal was performed. Changed hierarchy/source invalidates old compiled simulator checkpoint compatibility; use a new lineage for the longer logo run.

## Remaining hardware gates for Terra

1. With compatible installed Quartus, elaborate the real `altera_pll` and `altddio_out`, check that the PLL actually produces 104 MHz and the clock output is in the output IO cell. Existing old 20 MHz QIP editor metadata alone is not proof of the synthesized clock frequency; inspect the actual PLL/clock reports. Do not download Quartus as a workaround for this investigation.
2. Define/check the generated **inverted** clock at `SDRAM_CLK` from the actual derived PLL clock. Constrain SDRAM input/output delays against the installed module's speed grade, forward clock flight time, data/command flight time, jitter and FPGA IO delays. The simplified model's 5.4/3 ns values are not measured board numbers. The current `Template.sdc` still needs this real interface timing work; no guessed delay values or unverified hierarchical clock queries were added here.
3. Verify falling-edge DQ capture is packed in the input IO cell, plus the rising-edge transfer half-cycle path. Verify output DQ, command/address/DQM setup and hold at the forwarded memory edge, and output enables/bus turnaround. Preserve both source edges in timing analysis. Local JTFRAME's warning about multiple writable banks remains relevant to our BA0+BA1 configuration; inspect actual placement rather than assuming it is solved.
4. Keep full scrub/refresh timing and run standalone pattern, walking-bit, all-mask and boundary tests on the actual MiSTer module over sustained refresh traffic before trusting the phone boot. Save error address, expected/actual value and clock/build identity. If physical margins fail, adjust the clock/capture design from timing evidence rather than weakening the memory specification or bypassing firmware timeouts.

The single system-clock DDIO/read-capture combination now has a concrete passing simulation implementation. The distinction between that result and a validated 104 MHz FPGA memory interface must remain explicit.
