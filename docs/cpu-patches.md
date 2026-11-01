# CPU compatibility fixes

Current checkpoint and resume tasks: [status.md](status.md).

`rtl/arm/` is the ONLY ZAP copy in the project: pinned upstream krevanth/ZAP
`fc7bd75` plus the ordered series in `patches/zap/`. The Verilator boot
simulations (`scratch/*/build.py`, `sim/run.py`) and the Quartus build
(`files.qip`) all compile it. Edit files there, record each edit as the next
numbered upstream-relative patch, and run `patches/zap/verify.sh`: it downloads
the original upstream to `scratch/zap-upstream/` (git-ignored, reference only),
checks it against the hashes in `rtl/arm/UPSTREAM.json`, applies the series and
requires a byte-identical match. `make sim-upstream`/`sim-unmodified` use the
same download. `rtl/ngage_cpu.sv` is the shared RTL integration boundary.

History (2026-11-01): before this, `third_party/zap` held upstream + Quartus
fixes only, while every simulation used an untracked scratch copy
(`scratch/boot-v15-quiet-zap`) carrying 0001-0009 plus three unrecorded changes,
so the FPGA build was not the CPU the boot evidence came from. The unrecorded
changes were extracted as 0010-0012 (upstream + 0001-0012 reproduced that copy
byte-for-byte), then 0013/0014 were added. A from-reset authentic run to 150M
cycles was cycle-identical between the old scratch copy and the consolidated
tree (same bus/instruction traces, 41,013,833 transactions); checkpoints made
with the old copy may not restore (Verilator state layout differs). The patched
tree then moved from `third_party/zap/src/rtl` to `rtl/arm` and `third_party/`
was removed (file contents unchanged).

## Translated accesses when caches are disabled

The unmodified instruction and data cache FSMs use the virtual address for the
cache-disabled external request. This bypasses a successful MMU translation.
Patch 0001 selects the translated physical address in both paths. With the MMU
disabled, the translation unit already supplies the identity address.

The nonidentity data/FCSE test passes with caches enabled and disabled. A separate
code-fetch test maps virtual `0x30000000` to physical ROM at zero, leaves both
caches disabled, jumps to the translated code, and checks the visible PC.

## ARM920T alignment checking

Patch 0002 preserves CP15 c1.A and detects misaligned data accesses using the
full modified virtual address before ZAP drops its low address bits. Halfword
and word accesses fault at their respective alignment; bytes remain valid.
The early check prevents a misaligned access from initiating a page-table walk.
The data cache returns an abort with FSR `0x01` and the original fault address,
with priority over translation/domain/permission errors and without a target
memory write. The implementation is for the cache/MMU CPU configuration used
by this project; it does not add an abort controller to ZAP's ONLY_CORE mode.

The [ARM920T manual](https://documentation-service.arm.com/static/5e8e2a5b88295d1e18d381bb)
sections 2.3.5, 3.5, and 3.7.1 define these controls and fault semantics.
Other reserved/read-only CP15 bits remain ZAP's implementation, so the entire
control readback is not asserted to match a physical ARM920T.

`alignment_cases` checks 32 expected aborts across MMU-off, MMU-on/cache-off,
cache-on/uncacheable RAM, and cache-on/cacheable RAM configurations. It checks
word and halfword loads/stores, signed halfwords, fault addresses/status,
exception return addresses, unchanged memory after aborted stores, priority over
an unmapped access, byte operations, and unaligned word rotation after disabling A.

## Ordering a return from RAM into flash

Firmware runs identification/configuration routines from scratch memory. Its last
flash-reset store is immediately followed by a return into the flash array.
With delayed memory, ZAP's deeper pipeline can start the return fetch while the
flash is still in identification mode. The measured failure was a fetch at ROM
`0x5954` before the reset store acknowledged.

Patch 0003 holds the instruction front end while the instruction cache is
disabled and an older store is in the post-ALU/memory stages. The existing FIFO
write-inhibit honors that hold. Data execution still advances so the store can
complete. Branch prediction remains unchanged; disabling it alone did not fix
the ordering problem and is not part of the maintained patch set.

The firmware now reaches the same peripheral frontier with immediate and delayed
memory. An independent synthetic `flash_return` program copies its helper to RAM,
enters flash identification mode, reads the manufacturer ID, issues reset, and
returns to ROM. It reaches its expected completion stop with delays of 0, 0-3,
and 0-7 cycles. The flash array is never modified by this test.

## Optional simulation console suppression

Patch 0004 adds the `+ngage-compact-trace` switch around the duplicate retirement
console print. Retirement outputs, assertions, CPU state, and synthesis paths
are unchanged. The harness still checks architectural fetch aborts and records
its last retirement. This keeps long firmware delay loops from producing several
gigabytes of duplicate text; the runner's `--compact-trace` also filters ordinary
memory/instruction logs while retaining device I/O and faults.

Only the standalone harness defines `NGAGE_RUNTIME_TRACE` and initializes
Verilator's command arguments. Other benches retain the default console print
without evaluating runtime plusargs. The first upstream recheck exposed that
bench-initialization requirement; the current patch passes both original benches.

## Correctly completing nonblocking data-cache loads

Patch 0005 carries six bits of original load metadata from the core through the
D-cache and captures them alongside the missed register index. Its background
completion now selects the byte/halfword, sign-extends when requested, or rotates
an unaligned word before writing the asynchronous register port. Later requests
that hit under the miss cannot replace those captured controls.

The original miss path wrote a whole cache word directly into the destination,
bypassing `zap_memory_main`'s ordinary load transform. Real firmware exposed this
at virtual `0x500034f0`: cached hits read the register table correctly, but a miss
for byte `0x6da0` ultimately supplied `0x0026003b` where byte `0x3b` was required.
The lookup then entered its permanent failure loop at `0x50003524`.

`cache_load_widths` isolates the bug without Nokia firmware. Before the patch,
it returned `0x80ff7f01` for an unsigned byte expected to be `0x01`, with both
immediate and delayed memory. The fixed diagnostic checks misses and hits across
all byte lanes, signed/unsigned halfwords, unaligned-word rotation with A clear,
and the real adjacent-LDRB/ORR dependency pattern. It is part of `make sim-compat`.
The configured little-endian path is the tested scope.

## Qualifying branch state on a BTB tag miss

Patch 0006 reports strongly-not-taken for an invalid or mismatched predictor
entry. Previously the raw prediction state could claim a taken branch from an
unrelated tag, despite no redirect having occurred. The real firmware then fell
through a cached return into its literal pool and requested `0x0c120100`.

`btb_return` trains an aliased BTB entry and reproduces the wrong access without
Nokia payload. With the fix, immediate and delayed cases reach their intended
terminal write. See [branch-prediction.md](branch-prediction.md) for exact evidence,
failed cold reproducers, measured cycles, and the six-patch verification.

## Patches 0007-0009

0007 sets the terminal-exception FSR only when the Wishbone transfer actually
errored, so an acknowledged transfer no longer overwrites CP15 fault state.
0008 fixes the Thumb format-11 SP-relative LDR/STR offset sign (upstream
subtracted). 0009 makes the CP15 cache type register report ARM920T
associativity (64-way) and ctype 6: EKA1's clean-by-index loop derives its way
increment from the assoc field, and upstream's 0 made it run 2^32 iterations
(commit 0164a87). The physical caches stay direct mapped.

## 0010: retain D-cache translation across a background refill

Recovered from the `scratch/ldm-*` experiment chain (identity-v6..v15,
tlb-handshake v1-v4) that fixed LDM/cached-load corruption during boot. While a
CPU request is stalled behind a background line refill, the D-cache keeps the
TLB result it already obtained (`pending_translation`) instead of re-looking up
with a pipeline address that has moved on; the refill FSM holds the micro-op
(no ack/err2) on a background miss, forwards the completed line to a waiting
load or store in the same line, and commits the refill on the release edge.
`zap_tlb`/`zap_cache_tag_ram` export the checked lookup context used to decide
when the retained translation is valid. The simulation-only `assert`/`$fatal`
checks that the pending request context never changes are ignored by synthesis.
This is the CPU every boot milestone since 2026-10-28 ran on, but it has no
standalone reproducer yet (unlike 0005/0006).

## 0011: Thumb hi-register op with SBZ bits traps as UND

`decode_alu_hi()` reached `$fatal` for op=11 halfwords that are neither BX nor
BLX. Wrong-path fetches of literal-pool data after an unconditional branch
decode such halfwords without executing them (apmime 0x50603bc8, word
0x506047ec, 2026-10-31). They now decode to the UND trap. Also rewords the 0008
comment.

## 0012: silence simulation info floods

Comments out the UNPREDICTABLE PC-as-shift-operand `$info` in `zap_decode`
(N-Gage frame-drawing code hits it in hot loops; 186MB of log) and empties
three section-descriptor `$info` messages in `zap_tlb_fsm`. No datapath change.

## 0013: Quartus 17.0.2 compatibility

Formerly repo commits 446a44a/7fd435b. No logic change: typed localparams/struct
typedefs moved out of parameter lists (BTB, CP15), `foreach`/`inside` replaced,
explicit `generate` regions, sized enum literals, simulation-only assertion
blocks guarded with `SYNTHESIS`.

## 0014: byte-lane cache data RAM

`zap_ram_simple_ben` (cache data RAM, 256 bits wide with 32 byte enables) is
stored as one 8-bit memory per lane. Quartus 17 did not infer block RAM from
the looped byte-enable slice and built each 16KB cache from ~135K registers
(CI run 41263284904: the CPU alone was 122,721 ALUTs / 275,049 registers).
Behavior is identical: 400,000 random cycles including same-address
write/read collisions matched the original module on both outputs.

## Verification and limits

```sh
make sim-compat             # All focused acceptance checks must pass
make sim-unmodified         # Reproduce the two original CPU compatibility gaps
make sim-upstream-patched   # Original ARM32 and Thumb regressions, patched CPU
make sim-upstream           # Original regressions, unmodified source
make sim-rtl-lint           # ARM64 Verilator syntax check, SYNTHESIS paths
```

The focused acceptance suite and original upstream ARM32/Thumb regressions pass
on the patched CPU. The unmodified comparison reproduces the original alignment
and cache-disabled data-translation failures. Synthesis-path lint passes with
ARM64 Verilator; this is not an FPGA resource, timing, or placement result.

ZAP retains its 17-stage pipeline, ARMv5TE-capable decoder, direct-mapped caches,
and its other CP15/TLB behavior. Passing these checks does not establish a complete
ARM920T implementation, original Nokia execution timing, or Symbian compatibility.
