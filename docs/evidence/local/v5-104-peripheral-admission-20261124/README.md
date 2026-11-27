# 104 MHz peripheral admission pacing

Local A/B on retained production `e7f1e31`, with the exact `e9552bd`
tree. The [simulation-only RTL patch](admission.patch) allows the
CPU-facing UPP bridge to start selected requests on every second or
third system edge. A held request uses the original capture, cancellation,
authorization and reply sequence after admission. Pacing may add zero or
one clock at ÷2, or zero through two at ÷3, before admission. A clock at
104 MHz is about 9.615 ns.

The experiment compares GPIO/EUART (`0x0c150000`–`0x0c1505ff` and the
GPIO30 register bank at `0x0c120c00`–`0x0c120c1f`), MMC host registers
(`0x0c120600`–`0x0c12063f`), and the broader CPU data window at
`0x0cxxxxxx` excluding the two raw UPP DDR banks. The GPIO/EUART
address ranges also cover neighboring NOS and CBUS registers. Local DMA,
SDRAM, the timer and device logic, IRQs, and the existing 34.667 MHz active
MMC card clock use their original logic and rates. The phase gate
estimates software-visible wait cost. It provides no extra setup time
between the current request and result registers under the existing timing
constraints.

## Fixed work and measured guest completion

Ranges cover every initial phase. Time is modeled guest time at 104 MHz,
measured from CPU release to checked completion.

| Work, admission scope | ÷1 | ÷2 added clocks | ÷3 added clocks |
| --- | ---: | ---: | ---: |
| Stock keypad, zero other memory waits | 7,302 clocks, 70.212 µs | 20–21, 0.274–0.288% | 41–43, 0.561–0.589% |
| Stock keypad, three other memory waits | 12,660 clocks, 121.731 µs | 23–24, 0.182–0.190% | 41–43, 0.324–0.340% |
| Authored GPIO/EUART stress | 91,443 clocks, 879.260 µs | 1,026–1,027, 1.122–1.123% | 1,026–1,028, 1.122–1.124% |
| Mixed card, LCD, PCM and UPP DDR, MMC registers only | 1,168,777 clocks, 11.23824 ms | 16–17, 0.0014–0.0015% | 1,041–1,043, 0.0891–0.0892% |
| Same mixed test, broader MMIO window | 1,168,777 clocks, 11.23824 ms | 20–21, 0.0017–0.0018% | 1,058–1,060, 0.0905–0.0907% |

The stock keypad caller executes the original dispatcher, scan and
acknowledgment instructions from the hash-verified decoded NEM-4 factory
core. The adapted test uses the retained ARM9v2 CPU and registers the
UPP request and response. It retains the existing fixture's MMU-off
address mapping, authored caller, key-input mailbox and synthetic
memory. All 44 ordered MMIO replies and effects match at every phase,
and all nine checked key events pass. Full Symbian input scheduling is
outside this fixture.

The [authored stress](gpio-euart-stress.S) uses the retained full-board
model with 512 key scans and EUART configuration readbacks. All 2,050
targeted accesses and guest checks pass. The instruction and bus
cadence yields similar mean added waits in this test at ÷2 and ÷3.
The separate directed bridge test matches all 307 replies and 308
sample records per keypad setting, including masks, errors, cancellation
and held responses. It includes a few phase-aligned stimulus cases.

GPIO-only pacing leaves the mixed test unchanged, with zero admissions
in that scope. MMC and broader MMIO pacing preserve CMD24 data and
persistence, the PIO readback, HPS read/write counts, the full LCD frame,
both UPP DDR banks and the active MMC clock's three-system-clock rising
edge spacing. Poll counts and transaction timing change, so the blocked
admission clocks do not directly add up to total completion delay.
Every MMC-paced and broader-MMIO-paced run changes PCM sample index 2,
the third of 128 startup samples. The other 127 values match, and all
runs retain the sample count, spacing, zero underruns and zero
overwrites. The strict PCM hash check rejected the first changed run.
Characterization logged and compared each sample without requiring the
original hash, while preserving the other functional checks.

The previously checked 105 fixed-work windows and four native PolyCount
frames record zero MMIO accesses. Their bounded payload harnesses provide
no evidence for whole-game impacts. This experiment did not change or
measure MMC pin dividers, measure a routed timing gain, or change
production. [Per-phase counts, hashes and checks](receipt.json)

## Reproduction

The simulation staging area was `scratch/v5-peripheral-divide`.
The mixed source is the [prepared write-data pin replay](../../../experiments/v5-performance/prepared-wb-write-data.md#reapply-and-verify)
on `e9552bd`, with the admission patch and test-only workload and
observation hooks. The stock workload uses
[the original keypad fixture](../../../../tests/phone/keypad/original/README.md)
with a registered UPP bridge/stage and the `0x50320000`–`0x5041ffff`
slice of the verified factory core. For the mixed executable, use
`+pace_div=1`, `2` or `3`, `+pace_mask=1` for GPIO/EUART, `2` for
MMC or `4` for the broad scope, and every `+pace_offset` below the
divisor. The [collector](collect.py) checks all staged raw results.
