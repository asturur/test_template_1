# ARM920T production TLBs and cache

The production core has separate64-entry instruction and data TLBs. Each table
is fully associative and shares all slots between1MiB sections,64KiB large pages,
4KiB small pages and1KiB tiny pages. It replaces the ZAP4/8/16/32 direct-mapped
page-size banks. ARM DDI0151C chapters2–3 define the descriptor, permissions,
replacement and CP15 contracts; the local manual is ARM920T_TRM1_S.pdf.

## Lookup and timing boundaries

`rtl/arm920/tlb_bank.sv` stores virtual tags/page kinds in registers for parallel
CAM comparison. Eight groups of eight matches feed a grouped selector; there is
no64-entry serial priority chain. Physical bases, all four AP quarters, domain,
C/B and page kind occupy explicit `ngage_bram` storage:64x38 logical bits per
TLB, padded to40physical bits by the Cyclone V primitive wrapper.

The sequence is registered comparison, grouped selection/synchronous BRAM read,
then permission-result capture in `rtl/arm920/tlb.sv`. No64-way CAM reduction
feeds CPU completion in one combinational cycle. This is an FPGA pipeline, not
a claim of ARM silicon cycle equivalence or measured104MHz closure.

A local checked1KiB permission token serves adjacent accesses immediately.
It is keyed by MVA[31:10], MMU enable, actual read/write direction, CPSR mode,
S/R, DACR and TTBR. The current low ten address bits supply the physical offset.
A1KiB token cannot borrow permissions across a small-page AP boundary. Context
changes require another main-table lookup; they do not implicitly change the
architectural contents of the main TLB. MMU-off access is identity, uncacheable
and unbufferable. Warm cached ADD throughput remains one clock.

The main table and walker accept only an actual current request. Privilege and
LDRT/STRT force-user state must accompany the P2 memory request, not a P1
lookahead instruction. Patch0054 corrects this CPU boundary; changing the TLB
alone could still falsely reject a privileged FIQ store after exception return. The old
lookahead/check/hold ports are gone from the TLB interface. The cache wrappers
retain their CPU integration ports, but no old cache implementation is selected.
Lookup waiting stalls rather than sending the ZAP instruction retry/redirect.
Explicit CP15 prefetch borrows the I-side request and restores a current-request
translation token before releasing CP15. Waiting for obsolete lookahead-stage
addresses caused a real prefetch regression; the corrected test passes.

## Architectural behavior

CP15c10 has independent I/D base, victim and preserve(P) state. Refills advance
the victim through63 then wrap to base. Lower slots can therefore be locked
against normal replacement. P is recorded per entry when filled and is separate
from replacement lockdown. CP15 readback exposes actual table state.

CP15c8 all-invalidate preserves P entries. Invalidate-by-MVA removes a matching
entry regardless of P; matching covers the entire mapping size. Table mutations
cancel lookup pipeline results and invalidate local permission tokens.

The walker snapshots request address, direction and translation context. A coarse
L2 address uses VA[19:12]; a fine L2 address uses VA[19:10]. Section/large/small/
tiny decoding retains all AP quarters and attributes. Invalid descriptors are
returned as translation faults, not installed as negative table entries. L1/L2
external table aborts use FSR0xC/0xE, with the L2 domain retained. Domain and
permission checks follow the ARM920 AP/S/R rules. Fault results are consumed
only by their owning request and cleared on completion.

Invalidation, MMU disable or TTBR changes during a walk prevent stale installation.
An issued bus transaction drains before the controller accepts another request.
Table reads still pass the write-buffer ordering gate and existing registered
SDRAM route; no peripheral/SDRAM clock or timing parameter changed.

## Production cache selection

The16KiB I/D caches remain64-way with32-byte lines. `cache_adapter.sv` and
`arm920_cache_adapter` replace the experimental adapter name. The cache is
unconditional; NGAGE_ASSOC_EXPERIMENT and CPU_ASSOC_EXPERIMENT are removed.

The old cache FSMs, tag/data storage, split-bank TLB, old walker/checker and RAM
helpers used only by those implementations are deleted from `rtl/arm` and the
QIP. The branch predictor's unrelated RAM helper remains. The associativity
regression is a normal passing test rather than an expected legacy failure.
Frozen simulator executables and original upstream provenance remain available;
this cleanup never alters a running simulator or its checkpoint lineage.

## Verification and limits

Directed tests cover all64 mixed-size slots,65th replacement, base wrap,
preservation, all/MVA invalidation and cancelled lookups; all page sizes/C/B,
fine indexing, permission truth tables, noncached translation-fault retry,
external table aborts, held requests and1KiB permission boundaries. A CPU
program verifies CP15 readback, preserved mappings and selective invalidation.

The complete CPU suite passed177 checks with no XFAIL, including the previously
failing FIQ-store return case, translated CP15 prefetch, SWP, FCSE, alignment,
cache maintenance, buffer ordering and cold multi-loads. The two association
entrypoints both run the production cache. Whole-top structural elaboration and
Intel primitive-path lint pass. Patch0053 and the preceding series reproduce
`rtl/arm` exactly; verifier uses `patch -E` to honor deleted source files.

The final50M cold run is `build/sim/runs/tlb64-final-cold-50m/`, model27535b46216966c0.
It completes at00006154 with12known initial bus faults/data0, before LCD init.
This bounded cold run does not establish a full phone/UI boot. The matched
filesystem comparison is an explicitly audited diagnostic checkpoint fork,
not arbitrary old/new restore compatibility. See [mmcstore-scan.md](mmcstore-scan.md)
for the19.64% throughput /16.78% latency improvement,57 actual walks over50M
and diagnostic checkpoint continuation proof. No hardware build or104MHz fit was performed.
