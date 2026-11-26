# Retained 104 MHz seed sweep and timing follow-up

The retained clock and HDL tree is `e9552bd`. `11c4a0c` and `81a1b45`
both have the identical Git tree. Build date, original HDL, 16 KiB
per cache, physical 104 MHz clock and DDR debugging off are fixed.
The −1.5 ns milestone tracks progress. Timing closure requires
nonnegative setup, hold, recovery, removal and minimum pulse width
over the native routed corners and the SDRAM pin-register check.

| Seed | Run |
| ---: | --- |
| 1 | [45780077300](https://github.com/asturur/test_template_1/actions/runs/45780077300) |
| 2 | [45780081579](https://github.com/asturur/test_template_1/actions/runs/45780081579) |
| 3 | [45780077827](https://github.com/asturur/test_template_1/actions/runs/45780077827) |
| 4 | [45780074613](https://github.com/asturur/test_template_1/actions/runs/45780074613) |
| 5 | [45780076796](https://github.com/asturur/test_template_1/actions/runs/45780076796) |
| 6 | [45780082010](https://github.com/asturur/test_template_1/actions/runs/45780082010) |
| 7 | [45780082099](https://github.com/asturur/test_template_1/actions/runs/45780082099) |
| 13 | [45771268571](https://github.com/asturur/test_template_1/actions/runs/45771268571) |
| 43 | [45771267820](https://github.com/asturur/test_template_1/actions/runs/45771267820) |
| 31337 | [45771266151](https://github.com/asturur/test_template_1/actions/runs/45771266151) |

## Timing investigation during the sweep

At the hot corner on seed 13, 81 of 111 UPP peripheral paths below
−1.5 ns launch from the reset-drain duplicate. The main fanout reaches
the request-stage CYC and then the timer, ICU and keypad state-update
gates. Its worst timer path is −1.931 ns. The lane-13 UART return at
−2.061 ns starts at a captured address bit and is distinct. The same
seed has 32 paths below −1.5 ns ending at the Wishbone merger.

The MMC byte-count path is a smaller UPP target that appears on every
retained seed. It traverses bus acceptance and the wide `nfifo` increment.
The [prepared counter trial](mmc-count-prepare.md) splits that carry while
preserving the same MMC request and update edges. Fixed workloads, the
native frames, the mixed pin model and directed host tests measure the
prototype independently.
