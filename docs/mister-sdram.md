# MiSTer SDRAM transport

**Current 2026-11-06 result:** [104 MHz DDIO/read-capture investigation](sdram-104mhz-ddio.md) supersedes the clock-path conclusions below. The top now forwards `clk_sys` through inverted `altddio_out`, with controller `READ_CAPTURE_NEGEDGE=1` (falling-edge DQ capture, then rising-edge registration). The unchanged four-state Micron model passes, including masks/reset/refresh and selected clock delays; the deliberately wrong-edge negative control still fails. The 104 MHz real-controller 5M boot and 102-event staged comparison pass. The old -90-degree/default-capture path remains a regression. Quartus IO placement, generated-clock/I/O constraints and board timing are still unverified.

`ngage_sdram_adapter` latches each word request, issues two halfword operations, waits for the controller's registered `rdy` and returns exactly one word response. The read-data test using the actual controller observed `ack` 29 ns before the corresponding `rdy` at the 104 MHz test clock. The adapter holds the memory operation through both halves. `ngage_sdram_arbiter` serializes the CPU and future DMA port and preserves the CPU lock across a swap; a continuously asserted Wishbone request after acknowledgement represents another transfer. The present top ties the DMA port off.

The physical 16 MiB range occupies SDRAM banks 0 and 1, each 4 million 16-bit halfwords (`AW=22`, 13 row and 9 column bits). The CPU map rejects the 0x0b000000 range. A cold PLL/controller reset triggers zeroing of all 8,388,608 halfwords. The phone CPU remains held while the scrub runs and also remains intentionally held for subsequent integration milestones. A normal phone reset does not clear RAM or reset the SDRAM controller; an accepted read is drained and its response discarded. Refresh continues during phone reset.

The chosen test clock matches the RTL PLL's nominal 104 MHz and -2404 ps phase; it has not been proven achievable in synthesis or on the board. At 104 MHz, the scheduler asks for nine refreshes every 6,800 clock cycles (approximately 65.4 microseconds per group, about 7.26 microseconds per refresh on average). The controller maintains its own refresh debt and arbitration. The high-frequency controller initialization delay was increased from 10,000 to 11,000 cycles to exceed 100 microseconds at the nominal clock. Neither refresh timing nor SDRAM I/O closure has been measured on hardware.

**PLL metadata remains a build gate:** the checked-in `rtl/pll.qip` IP metadata describes one 20 MHz output, while the instantiated generated `rtl/pll/pll_0002.v` requests two 104 MHz outputs with the second at -2404 ps. The RTL was not regenerated and the metadata was not guessed or rewritten; regenerate/reconcile with a compatible installed Quartus and verify the generated PLL before synthesis or hardware use. Also verify the actual SDRAM module capacity and its timing constraints; the Micron model used here does not check the full 8192-refresh retention requirement.

## Tests

Run from the repository root:

```sh
docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 tests/phone/sdram/run.sh
docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 tests/phone/sdram/run-scrub.sh
CPU_SDRAM_PATH=1 CPU_ASSOC_EXPERIMENT=1 CPU_DELAYS='0 3 11' CPU_MAX_CYCLES=1500000 CPU_PROGRAM=cache_load_widths tests/cpu/core/sim.sh
```

The first test drives the actual `jtframe_sdram64` and a Micron 256 Mbit behavioural model, checks all masks, bank and address boundaries, reset in flight, CPU/DMA lock and refresh under traffic. The model is kept locally at `scratch/sdram-reference/mt48lc16m16a2.v`, copied from `~/develop/jtpublicfork/modules/jtframe/hdl/ver/mt48lc16m16a2.v`; its SHA-256 is `d5a3a058550f22383da382ced23a16409360b8f213c5a89081ce18cc34b99b19`. It is not included in the core or distributed in Git. The second test checks every 16 MiB scrub address against an idealized controller. `CPU_SDRAM_PATH=1` routes CPU-test RAM transactions through the real new arbiter/adapter and an idealized halfword responder; its ROM and fault injection retain the existing test harness. This is not a full phone simulation.

## Night Slashers reference (2026-11-06)

MiSTer-devel/Arcade-NightSlashers_MiSTer c75532f uses a single 96 MHz `altera_pll` output for its jtframe controller and `altddio_out` to produce an inverted SDRAM pin clock. Its README reports working hardware. Its PLL QIP still describes 20 MHz even though its Verilog requests 96 MHz, so the metadata discrepancy alone is not proof of build failure. Our implementation differs: 104 MHz PLL with a second -90-degree SDRAM clock, a different controller revision, dedicated refresh, and 11,000-cycle initialization. Reproduce its 96 MHz/180-degree path in simulation before considering a switch; physical timing and actual generated-PLL interpretation need Quartus/hardware verification.

## 104 MHz inverted-clock experiment

The Night Slashers-style single PLL output and DDR-inverted clock was tested at 104 MHz. The four-state Micron model returned high-impedance read data at the adapter ready pulse. With 5.4 ns model tAC the half-cycle is only 4.8077 ns, and the controller ready/data alignment also matters; nominal Verilator two-state pass does not establish validity. A diagnostic earlier sample with tAC reduced to 4.5 ns passed, but changes the memory assumption and is not a physical timing fix. Candidate copies are in `scratch/milestone8-clock/candidate/`; the prior two-output clock remains the production configuration until the inverted path passes valid timing/board checks.

## JTFRAME CPS3 comparison

Local `jtpublicfork/cores/cps3/cfg/macros.def` sets `JTFRAME_PLL=jtframe_pll7000`, `JTFRAME_SDRAM96` and `JTFRAME_180SHIFT`, and documents a 112 MHz fast clock. The latter macro selects an `altddio_out` inverted output. In the fast path `jtframe_board_sdram.v` sets `HF=1` and forces `SHIFTED=0`, matching our controller defaults. JTFRAME memory requests capture `dst` and complete at `rdy`; with 16-bit bank length the bank controller schedules both at the same state. Its two-state C++ SDRAM model retains the prior DQ when not driving, unlike a four-state model that can show Z. Reproduce controller `dst`, `rdy`, raw DQ and both adapters at the same clock and model before selecting a fix. JTFRAME also warns that multiple writable banks can prevent I/O-pad placement; we enable two writable banks.
