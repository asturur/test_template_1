# Embedded core digest mismatch

Checkpoint: [status.md](status.md). Verified read-only, 2026-10-27.

The current stop is a firmware integrity rejection, not another unknown register.
The MMU-aware native reference reaches `0x50003290`, an unconditional self-branch
with IRQ unmasked. Its caller is `BLNE 0x3290` at `0x32e8`, immediately after
comparing computed and expected digest bytes. Native LR is `0x500032ec`.

## Exact checked data

The original NEM-4 core, SHA-256
`afc1cc8b693f2b68d23ca203aa4d4eb4266baad4ab718f013a33b915d39574ef`,
contains this descriptor at file `0x8f18`:

| Field | Value |
| --- | --- |
| Checked virtual start | `0x50009000` |
| Checked virtual end, inclusive | `0x511b4fff` |
| Corresponding logical file range | `[0x9000, 0x11b5000)` |
| Byte count | 18,530,304 |
| Embedded expected MD5, file `0x8f20` | `2c09c86ff047484fdcc0e226f49c44a9` |
| Python hashlib MD5 of the supplied bytes | `1784c17a6fd17b0841226546434db048` |
| Complete FPGA-computed digest | `1784c17a6fd17b0841226546434db048` |

The hardware result is recovered from all sixteen selected-byte writes to
physical `0x0c004748..0x0c004757` in `memory-tail.tsv`. It matches an independent
MD5 implementation over the supplied logical ROM bytes. The software reference
also rejects the comparison's first byte (`0x17` computed versus `0x2c` expected).
This supports correct execution of the hash; it does not authenticate the dump.

The checked range is entirely before the core end `0x511c0000` and therefore
before the separately reconstructed extension. Its synthesized header and
directories cannot account for this mismatch. The descriptor itself also lies
outside the checked range. No original firmware input was modified or bypassed.

## Reproduce without CPU execution

```sh
make inspect-firmware-digest
# Add --hdl RUN_FOLDER to include another complete hardware trace.
```

`sim/inspect_firmware_digest.py` verifies the pinned core, reads the descriptor,
computes MD5, recovers the hardware digest and records source-result/trace hashes
in `build/sim/firmware-digest-analysis.json`. No long LCD/hash execution is needed
to rediscover this result.

## Next investigation

Determine why the logical dump differs from its embedded expected digest: for
example a runtime-patched dump, postprocessing, or a difference from the original
flash image. The cause is not authenticated. The equal flat-file/FPGA digest
establishes the current virtual input seen by this check; it does not establish
a complete physical flash layout.

The [other firmware variants](firmware-inventory.md) have now been scanned
read-only. `make inspect-digest-variants` records the candidate ranges, expected
and computed digests, per-image hashes and static literal references. All three
distinct core images differ from their embedded expected values. The QD descriptors
and references are static evidence: QD startup has not been executed here.

NEM-4's second descriptor at file `0x8f00` covers virtual
`0x51230000..0x5136efff`. Its expected MD5 is
`72ac17daea805cf2adf2bd6db7c26765`; the reconstructed tail's bytes hash to
`30f998ac14c9a77fad5eb0c74a4cccbd`. That range starts 58,168 bytes before the
recovered ROOT snapshot, so its original prefix is not known. This second mismatch
may reflect reconstruction assumptions; the distinct core mismatch cannot.

## Explicit progress probes

`sim/digest_probe.py` builds a separate derived image only when requested.
`--digest-probe core` changes the first embedded expected digest; `both` changes
both. The images contain respectively 16 and 31 changed bytes, entirely in the
selected digest fields outside the checked ranges. The original core and recovered
ROOT remain unchanged. Their manifest records original and derived SHA-256,
before/after bytes, ranges and `authenticity_verified: false`. Both CLI runners
validate the original image and extension first, then record the derived image
and manifest. Cross-scenario comparisons reject mismatches.

Under the existing `6=512` ADC and other startup assumptions, the independent
native CPU produces:

- `core`: passes the first digest and rejects the extension at `0x50003290`,
  with r0=`0x51230000`, r1=`0x5136efff`, computed first byte `0x30` and
  expected `0x72`.
- `both`: passes both digest comparisons and reaches an unknown read at physical
  `0x0c120a08`, virtual PC `0x5000326c`. IRQs are still not modeled or injected.

These derived images are **experiments**, not authenticated repairs, and do not
explain the original digest mismatch. The original default path still rejects its
unmodified digest. Separate immediate/delayed FPGA verification is in progress;
current state belongs in [status.md](status.md). Never silently replace the input
or present the patched digest as evidence of original hardware contents.

```sh
python3 sim/test_digest_probe.py
python3 sim/digest_probe.py --mode core
python3 sim/digest_probe.py --mode both
build/oracle/venv/bin/python sim/oracle.py --ideal-clocks --lcd-probe \
  --rom-extension --boot-io-probe --uem-adc 6=512 --digest-probe both \
  --mmu-reference --fast-rom-reference --compact-bus --no-instruction-trace \
  --max-instructions 500000000
```

The other firmware variants' provenance and a real physical image remain useful
independent forensic targets. Timer/interrupt behavior is now the next hardware
slice for the explicitly patched experiment; see [uem-control-bus.md](uem-control-bus.md).
