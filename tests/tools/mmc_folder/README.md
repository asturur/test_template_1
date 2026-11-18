# Folder-card integration check

This synthetic check requires mtools and Python 3. It creates its temporary
fixtures and card under `build/mmc-tests/` and removes them after the check.
From the repository root with native mtools:

```sh
python3 tests/tools/mmc_folder/check.py
```

With the existing container and the cache prepared by
`tools/mmc-card/setup.command`:

```sh
docker run --rm --network none -v "$PWD:/repo" -w /repo \
  -e PYTHONDONTWRITEBYTECODE=1 \
  -e PATH=/repo/build/tools/mtools/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  --entrypoint python3 jotego/simulator:arm64 tests/tools/mmc_folder/check.py
```

The builder checks long-name preservation and source bytes; a separate auditor
checks allocation and file hashes, and the production MMC inspector validates
register CRCs/footer/full capacity. Summary: `build/mmc-tests/result.json`.
