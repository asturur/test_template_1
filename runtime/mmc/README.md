# Durable local MMC inputs

These folders hold useful runtime data, not disposable experiments:

- `files/`: installer card contents; currently the unchanged `SPMARK.SIS`.
- `extracted-files/`: extracted SPMark application/help tree.
- `empty-files/`: add files here for a custom FAT12 card.
- `installer-text/`: preserved installer notices, outside the card filesystem.
- `extraction.json`: original SIS and payload hashes.

Private payloads are ignored by Git. Preserve any files you add here; they are
not generated build output. The original installer remains at the user-supplied
location recorded in `extraction.json`.

Run `tools/mmc-card/rebuild.command` from the repository to regenerate the cards
under `build/mmc/`. See [the tool instructions](../../tools/mmc-card/README.md).
