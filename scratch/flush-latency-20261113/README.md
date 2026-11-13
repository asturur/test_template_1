# Native Phone profile-startup probes

Resume with `docs/phone-profile-startup.md`; raw media, ROM words, generated
scripts/ELFs and capture logs remain ignored. Only small probe/test sources are
tracked. Nothing here is a production firmware patch or full-phone simulation.

From the repo root:

```sh
sh scratch/flush-latency-20261113/run.sh
python3 scratch/flush-latency-20261113/prepare_profile.py
# Or prepare_io.py for dense Phone-only EStor pathname/I/O tracing.
```

Both prepare scripts use the maintained native observer's original-service-ROM,
pinned exit payload, checksum and fresh-Hold guards; they add only the pinned
research probe. First build `tools/build_exit_trace.py` if its payload is absent.
Generated `profile-prepared/observer.py` defaults to read-only preflight; --apply
requires a fresh held CPU/save Off and verifies the full resulting ROM hash.
Use the mister-control skill's cached settings/reload/start procedure. Never
patch an already-running or warm-held phone. Reload removes all ROM hooks.

`prepare_c_comparison.py` builds a separate data-only fresh-Hold script for the
captured native initialized C4a75e4cb...; default requires the profile observer's
exact ROM hash. --original-rom instead requires original88fd596a... and writes
no firmware. Both require original baseline Caf5017dc..., unchanged PMM71189f7f,
saved Run off and two advancing held snapshots; card files are untouched.
It needs the private `scratch/menu-bringup-20261112/menu-working-c.vhd` source.

The profile observer reports id1=native ProfileLookup CountL, extra=actual
CProfileDb expected-count field; id2=RDbStoreDatabase::OpenL (void; r0 is not a
status); id3=CFileStore::OpenL result pointer. Only id1 at50A13501 uses the
verified native SP+328 frame field. CPU fixtures check this frame and returns.

The detailed I/O observer tests and native hardware captures are preserved.
Use `measure_strict.py` only on phone-running.jsonl: it rejects malformed/non-
adjacent messages and any pair crossing reader gaps. The original parse.py
and FIFO pair estimates are rejected; do not reuse their long-latency claims.
Rerunning the dense observer with the incremental reader is still pending.

Do not interpret initialized-C success as factory-erased cold-start performance,
complete native SIM readiness, or qualified external RF/DSP startup. No PLL,
FPGA logic or other-thread simulation changes were made by this investigation.
