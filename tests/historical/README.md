# Historical N-Gage investigations

The dated directories preserve the source of earlier one-off experiments. Some scripts address the original checkout layout, retired checkpoints, or a live target. For the maintained offline benchmarks, start with the [SPMark runner](../cpu/spmark_payload/README.md). The phone test runners use [board reference models](../phone/reference/), the [SDRAM model](../phone/sdram/model/) and local captured fixtures under `tests/phone/fixtures/local/`. The boot and PMM inputs shared with the image builder live in `runtime/boot/`.

## Finding a recorded experiment

The pre-migration source layout is available at commit `fae40167654949f9530e75eecd6d58c4fc74d013`. For example, `git show fae4016:scratch/variant-table-trace/build.py` retrieves the original script. To replay an old investigation, stage its original paths and dependencies in an isolated directory. Historical receipts describe the inputs available when the run was made.

Two Git-ignored local archives preserve data associated with the old paths. Each uses the original `scratch/...` member names. List them with `tar -tzf`. Extract into an empty directory when a particular investigation is needed. Some byte-identical files share a tar hard link with an earlier member.

- `tests/historical/local/investigations-20261117.tar.gz` holds local historical test material and supporting observations.
- `docs/evidence/local/observations-20261117.tar.gz` holds other local working notes, captures and data.
- `docs/evidence/local/reference-checkouts/` records the origin and revision of the former reference checkouts, their local patches, and a Git bundle for the locally committed timing experiment.

The archive payloads were checked against the original files before removal. Simulation checkpoints, compiler objects and checkout MMC images were retired. Build the tools and test outputs again when needed.
