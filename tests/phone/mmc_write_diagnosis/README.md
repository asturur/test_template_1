# MMC write diagnosis

`card/` contains the two nonprivate source files for the operator's128MB
FAT16 write-test card. Build with the existing card tools:

```sh
python3 tools/mmc-card/build-card.py --size 128 \
  tests/phone/mmc_write_diagnosis/card build/mmc/write-test-128mb
```

Run this inside the documented mtools container environment. The prepared
card has class4/512-byte writes and no CSD write protection. Its image is not
committed. The operator, rather than this test, mounts it on the phone.

This extends the existing authored-ARM `mmc_mister` fixture without editing it
or production RTL. See `docs/mmc-write-diagnosis.md` for the evidence boundary,
commands, measured result and hardware diagnostic sequence.

Prepare on the host (ARM assembler), then run `run.py --sim` inside the existing
offline simulator image. The container lacks the ARM cross compiler. Each run
copies/hashes all compiled HDL inputs before building; `--sim` requires a fresh
prepared program. Output is confined to
`build/sim/mmc-write-diagnosis-20261117/`; do not overlap copies of this runner.

Generated writable card/data only: no user image or phone access. Authored ARM
CMD24 drives TX2 DMA through the actual board/host/card/adapter. A synthetic HPS
peer checks outgoing data and stores it in an independent image; the final
oracle checks stored bytes plus surrounding/footer guards. A negative case
corrupts the last stored halfword and must fail, independently of card-cache
PIO readback. This does not test actual hps_io and Linux Main together, original
EPBUS, filesystem writes, CMD25, or physical persistence.

Measured normal:297511clocks/4reads/1write,512 bytes pass. Negative: persisted
halfword1023 rejected. No production bug fix or MMC area rewrite is included.
