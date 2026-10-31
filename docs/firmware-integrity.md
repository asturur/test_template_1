# Embedded core digest mismatch

## 2026-10-31 *** SOLVED: the stock digest 2c09c86f IS reproduced; read-side scrambler fully reversed *** (update made with Claude)

The authenticity question raised by the external researcher is CLOSED. The
NEM-4 flash read-side scrambler is fully reverse-engineered: 16 per-halfword
GF(2) formulas P_i = C_i XOR C_{j(i)} XOR (linear address) XOR (<=2 quadratic
address products), A = absolute byte physical address. Each bit is exact
(100.0000%) on all 1,093,312 known-plaintext halfwords, and - the proof -
descrambling the whole scrambled window [0xa000,0x2b3000) and hashing the
core digest range VA 0x50009000..0x511B4FFF gives MD5
2c09c86ff047484fdcc0e226f49c44a9, EXACTLY the stock embedded expected value
(independently recomputed). MD5 cannot match by chance, so every formula is
verified at every address, including the (A19,A20,A21)=0 regime the training
data never visited.

CONSEQUENCES:
 - The reported Nokia/N-Gage boot NO LONGER depends on replacing the expected
   digest: an authentic ROM can be assembled from the Nokia service files
   (nem440.3c1/.326), the scrambled window descrambled in place, and the
   firmware's own MD5 self-check passes NATIVELY. The digest-probe images are
   superseded for authenticity (they remain only as a faster build shortcut).
 - The previously "unreachable" 21% of the window ([0xa000,0x6e030) and
   [0x725c0,0x9d280), 584,944 bytes) is now DECRYPTED from ciphertext+address
   alone (entropy ~8.0 -> ~6.1-6.5; plausible Thumb code + VA pointer tables).
   The real baseband/NOS content is recovered. No live descrambled capture is
   needed after all.
 - Supersedes every earlier "provably unmatchable / cipher gated / gsmstuff
   can't reach the gaps" conclusion in this file and in flashing_how.md
   sections 8/9. The gaps were reachable because descrambling needs only the
   ciphertext (which we have for the gaps) plus the address.

Artifacts: the 16 formulas in build/firmware/thc/scrambler-model.json (also
scratch/flash-cipher-r4/model.json); full derivation, address convention,
held-out validation, gap decrypt and the digest recipe in the untracked
claudia-handoff/flashing_how.md section 10; scripts scratch/flash-cipher-r4/.
The researcher's two anchor formulas (bits 9 and 10) were reproduced
symbol-for-symbol by the independent solve.

---


## 2026-10-31 FLASH-TRANSFORM ANSWER (second investigation; note written with Claude)

Full write-up: claudia-handoff/flashing_how.md (untracked research package);
scripts scratch/flash-transform/. Headline conclusions, each hash-verified:
 1. THE FLASH STORES THE SERVICE PAYLOAD VERBATIM. Chip-mirror proof: the
    live dump's pre-remap window equals the service file's raw scrambled
    bytes exactly (53,248/53,248 at [0xa000,0x17000)), and ~14.9 MiB of the
    image is byte-identical service-vs-chip. The WD2/Starship flash writer
    and the UFS host traffic both write payloads verbatim. So the
    service->flash step has NO transform: an FPGA "flash the service
    package" option that writes record payloads at their record addresses
    reproduces authentic on-chip content TODAY.
 2. The scramble is a READ-SIDE descrambler on the cellular-MCU fetch path
    only; Symbian never reads that window (the boot remap shadows it).
    Running the NOS from flash needs that descrambler model (unsolved), or
    the current workaround (THC plaintext NOS + authentic IAT region).
 3. The "+8/+96 shifts" were reference-file bookkeeping, not flash framing.
 4. Cipher status after cryptanalysis round 2 (full write-up: section 8 of
    the untracked claudia-handoff/flashing_how.md; scripts
    scratch/flash-cipher/): PARTIAL BREAK.
    - ADDITIVITY PROVEN: ct = pt XOR f(absolute PA); modular add/sub
      combining refuted (carry argument over 1,093,312 halfwords).
    - FIRST KEY BIT SOLVED in closed form: keystream halfword bit 11 =
      1 ^ x7 ^ x8 ^ x11 ^ x14 ^ x19 (mask 0x84980, x = absolute CS0 PA);
      100.0000% on the 2.1MB training pair AND 100.0000% on the fully
      out-of-sample IAT pair where true plaintext is provable. Lanes 11
      and 27 identical.
    - LFSR families refuted everywhere else (BM = n/2 at every
      granularity); the other 15 lanes resist affine AND quadratic
      address models - shape suggests a halfword-wide address-mixing
      generator with one affine tap (repeat-delta fingerprint recorded
      for the next attacker).
    - A few hundred bytes of live raw-vs-descrambled capture (or any
      second same-PA image) would break per-address unfalsifiability for
      all 16 lanes at once - same capture ask as the 21% gap.
 5. Stock boot-MD5 2c09c86f... remains unreproduced (raw ac2ac9c5, dump
    window e8f426c4); consistent with the verifier hashing the DESCRAMBLED
    read-side view, whose plaintext is unavailable for 21% of the window.



## 2026-10-31 standing disclosure (external researcher confirmed; note written with Claude)

Every booting image in this project (the `digest-probe*` variants under
`build/firmware/nem4-factory/`) REPLACES the core's embedded expected MD5 so
the firmware self-check passes: original `2c09c86ff047484fdcc0e226f49c44a9`
is rewritten to the digest of the image as the board serves it
(`ac2ac9c5f124474da267441833e63c61` for the plain factory assembly;
`bc60db40d0c9ca752721b76cf30b07a1` with the synthetic NOS stub overlaid).
The Nokia/N-Gage logo milestones therefore do NOT demonstrate that the
original integrity check verifies authentic content - they demonstrate the
boot path beyond it. An independent researcher computed the same
`ac2ac9c5...` from their raw MCU image, confirming our factory assembly is
byte-identical to theirs AND that neither it nor the THC dump
(`1784c17a...`) matches the original embedded value. What input the real
check hashes to `2c09c86f...` is an open question (candidate hypotheses and
digest experiments: see the integrity-hunt notes below and
`scratch/nem440-flash-extract/`). Every run manifest records
`authenticity_verified: false` for this reason.

CORRECTIONS from the same researcher (2026-10-31), accepted:
 1. The status.md claim that "the 56-byte per-device hole sits inside the
    digest window via the 0x300000 mirror" is UNSOUND: the mirror was
    inferred from POST-REMAP phone-dump aliases (dump 0x300000..0x309fff ==
    dump 0x0..0x9fff), but the digest runs BEFORE the remap, and the stock
    factory MCU holds real, fully-supplied, distinct data at phys 0x300000+
    (0x30012C included). A later remapping cannot establish what the
    earlier verifier reads.
 2. "Provably unmatchable from the containers" is RETRACTED: ~90 failed
    candidate layouts show the digest is unmatched so far, not impossible.
    The factory file's own record addresses (not dump aliases) are the
    sound basis for reconstructing the verifier's view; the parallel
    investigation proceeded on that basis (findings in the untracked
    claudia-handoff/NGAGE_MISTER_FINDINGS.md; scripts in
    scratch/digest-authenticity/). OUTCOME: the IAT "plaintext in the
    scrambled window" was a DUPLICATE copy record-addressed to CS0
    0x3c86f0+ (inside XIP), not a descramble; 21 candidate assemblies all
    fail the stock digest; no plaintext source exists anywhere in the
    package for 584,944 bytes of the window ([0xa000,0x6e030) and
    [0x725c0,0x9d280)). The remaining paths are a pre-remap device capture
    or the read-side/programming transform - the same frontier as the
    external researcher's handoff. authenticity_verified stays false.

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
