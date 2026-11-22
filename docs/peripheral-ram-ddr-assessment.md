# Reclaiming the two large UPP RAM banks on ngage-v5

The retained production fit at `5f8fae0` uses 438 of 553 M10Ks. The same production RTL is present at `53b707b`. Quartus assigns 64 M10Ks each to the 64 KiB DSP upload bank and the generic 64 KiB NOS bank. Moving both to HPS DDR3 removes 128 blocks gross, increasing the available count from 115 to 243 before accounting for the implementation. [Retained fit](https://github.com/asturur/test_template_1/actions/runs/45043488050) · [Production fit results](#production-fits-at-104-mhz)

## What would move

The upload bank covers `0x0C030000–0x0C03FFFF`. The generic NOS bank backs the part of `0x0C10xxxx` left after the MDI device claims its ring and pointer registers. The generic tail starts at `0x0C1003F0`. MDI can keep exchanging messages and PCM can keep fetching samples from SDRAM without a single access to either candidate bank. The separate NOS4K, auxiliary RAM and framebuffer are outside the proposed change. [UPP owner selection](../rtl/ngage_upp_peripherals.v) · [MDI ownership](../rtl/ngage_upp_mdi.v)

The earlier November 17 audit at commit `5a65948`, in `docs/peripheral-memory-placement.md`, proposed external backing and deferred implementation. It recorded a 36,248-byte NEM-4 upload reconstruction. The new NEM-4 cold-boot trace independently reproduces that byte count and address interval.

## Work observed during boot

| Guest and software model | DSP upload | Generic NOS |
| --- | --- | --- |
| NEM-4 Sega Rally cold boot in MAME | 18,124 halfword writes covering 36,248 bytes at offsets 0x0100–0x8E97. Zero reads. | 30 byte reads, 30 byte writes and two halfword writes |
| QD SonicN cold boot in MAME | 18,904 halfword writes covering 37,808 bytes at offsets 0x0100–0x94AF. Zero reads. | Same 30 reads and 32 writes |

The NOS byte accesses touched offsets 0x0FE0–0x0FFD. Its two halfword writes touched 0x03F0 and 0x03F2, immediately beyond the MDI-owned area. These are actual guest accesses. Preserve byte enables, zero-on-cold-start behavior and warm-reset retention for the full guest-visible banks, including addresses these games did not exercise.

A separate cold run of the retained ARM9V2 RTL reached the Nokia raster within 100 million clocks without accessing either bank. That run covers an earlier boot phase than the uploads in MAME.

## Play and sound

In 150 emulated seconds per title, calibrated ARM physical address-space taps recorded zero accesses to either candidate after startup. Sega Rally reached a Desert Championship race with visible driving progress. Its emulated PCM was active in the menus and after retirement, and silent during the race. SonicN reached the playable beach level, producing 91,340 nonzero emulated PCM samples between two active-play screenshots six seconds apart. MDI ring and pointer traffic continued. The Asphalt probe remained at the Phone UI and was excluded. These are MAME guest observations. The independent v5 RTL replay below checks the effect of peripheral stalls on PCM timing. [Guest trace and tap calibration](evidence/v5-upp-ram-game-traffic-20261122.json)

## Expected performance cost

Sol replayed the observed boot transfer counts through the production scalar DDR arbiter and flash adapter with a modeled HPS endpoint. The model brackets idle and intermittently busy DDR. The incremental estimates at 104 MHz subtract a modeled local BRAM access and a common handoff. The experiments do not measure HPS latency on a physical MiSTer.

| Guest work | Estimated extra boot time, no competing flash request |
| --- | ---: |
| NEM-4 upload | 0.70–1.51 ms |
| QD upload | 0.73–1.58 ms |
| Generic NOS access sequence | 3–9 µs |

Cold clearing is separate from guest traffic. A serial 32-bit clear through this port takes about 0.95–1.68 ms per 64 KiB bank at 104 MHz in those model settings. The existing on-chip arrays clear concurrently. The extra time visible at startup will depend on whether DDR clearing overlaps that initialization. Sustained competing flash traffic also changes service time. With a competing requester continuously missing in flash and the slowest modeled DDR service, the entire upload sequence took 9.29 ms for NEM-4 and 9.69 ms for QD (gross service time at 104 MHz). This deliberately saturated case measures shared-port interference. None of these numbers is a frame-rate estimate. [DDR service bench](../tests/phone/upp_ddr_cost/)

The v5 mixed SDRAM-pin replay with PCM, LCD and MMC took 1,189,662 clocks with either proposed bank subject to modeled wait states and no guest accesses to those banks. In a separate stress replay, the guest performed 256 reads and 256 writes per bank while PCM and LCD were active. Injecting 48 read and 24 write wait clocks on both banks accumulated 36,864 wait clocks. The mixed completion moved by 32 clocks because independent activity dominated elapsed time. All 128 PCM samples retained the same hash and first/last clocks with zero underruns. This verifies the modeled local wait behavior. The separate DDR service bench covers physical-protocol arbitration against a modeled HPS endpoint. [RTL replay measurements and reset checks](upp-ddr3-rtl-replay.md)

## Decision

Reclaim the generic NOS bank first, then the DSP upload bank on the same DDR client. Keep their guest address mappings independent and leave MDI ring/pointer traffic local. The NOS step has the smaller traffic cost. The upload step adds a predictable sequence of cold halfword writes. Simple scalar writes are sufficient for the first implementation. The observations preserve the reason for full writable backing of both windows, even on a title where play never reads them.

## Integrated DDR backing

The production `Template` maps DSP upload to HPS DDR byte addresses `0x31820000–0x3182FFFF` and generic NOS RAM to `0x31830000–0x3183FFFF`. The allocation sits between the PMM and diagnostic PCM ranges, within the DDR space reserved by the installed MiSTer Linux. Existing guest addresses and MDI claims stay in the UPP decoder. Partially enabled writes use the original byte lanes, and ordinary bank accesses bypass the flash cache. [Production wiring](../Template.sv) · [DDR memory audit](ddr-diagnostics.md#memory-and-reader)

Cold initialization zeros both banks in 256 chunks of 512 bytes through the shared DDR transport. Each 64-bit write advances only when the HPS port accepts it. Arbitration can serve other clients between chunks. The UPP waits for local initialization and DDR clear before reporting readiness. The clear can run while firmware loading or image mounting holds the phone in reset. A warm reset retains both banks, suppresses cancelled CPU replies, and allows the transport to drain the outstanding operation before releasing the CPU. The UPP and phone flash share the CPU side of the DDR reservation, so a guest SWP still has access to its target while auxiliary traffic is excluded. [UPP RAM handshake](../rtl/ngage_upp_peripherals.v) · [DDR request client](../rtl/ngage_upp_ddr_port.v)

The cold-gate test drives all 16,384 zero writes through the real `emu` logic with modeled HPS backpressure and a stub PLL. The shared-port test covers masks, SWP exclusion, flash persistence and reset drain. The ARM9V2 replay verifies SWP in each bank while LCD DMA waits, executes instructions from both banks, and checks PCM samples, the LCD frame and MMC writeback against the existing oracles. [Cold gate](../tests/phone/upp_ddr_top/) · [Shared-port test](../tests/phone/upp_ddr_transport/) · [ARM9V2 replay](../tests/phone/upp_ddr_ram/)

### Production fits at 104 MHz

All three builds of `61d51fe` reclaimed exactly 128 M10Ks. Use fell from 438 to 310 of 553, leaving 243 free. The UPP peripheral hierarchy fell from 161 to 33 M10Ks. The LCD framebuffer still uses 53, auxiliary RAM 16, and MDI 2. The CPU hierarchy retains its 82 blocks. Seed 43 has the best worst-corner setup slack among the three new images. All three produced bitstreams and passed hold, recovery, removal and minimum pulse width across the four timing corners. All three missed setup at 104 MHz. Physical boot and game audio on these images await a board test.

| Fitter seed | Worst core setup, ns | Fitted ALMs | RBF build |
| --- | ---: | ---: | --- |
| 43, previous BRAM build | −2.543 | 37,452 | [Retained reference](https://github.com/asturur/test_template_1/actions/runs/45043488050) |
| 43, HPS DDR | −2.809 | 38,017 | [Hardware test image](https://github.com/asturur/test_template_1/actions/runs/45072531740) |
| 13, HPS DDR | −3.282 | 37,927 | [Alternate](https://github.com/asturur/test_template_1/actions/runs/45072535827) |
| 31337, HPS DDR | −2.919 | 37,931 | [Alternate](https://github.com/asturur/test_template_1/actions/runs/45072539647) |

The locally archived RBFs and their build manifests are under `build/fit/v5-104mhz-61d51fe-seed<seed>/`. Seed 43's RBF SHA-256 is `2ff393f497a8166712744f163403930ccd65c37d686dda5078c622335f2cee5a`.

The matched seed gained 565 ALMs. Quartus attributes about 410 of that difference to the CPU fetch block's direct logic (599.5 to 1,009.8 ALMs). Its source hash matches. The synthesis reports show nearly identical direct combinational ALUT counts for fetch (1,022 to 1,019), while the fitted counts rise from 1,022 to 1,899. This points to the fitting stage as the first place to investigate the additional logic. It does not establish a particular duplication or routing cause.
