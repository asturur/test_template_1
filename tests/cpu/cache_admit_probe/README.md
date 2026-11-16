# Admission-edge data pre-read

Run from the project root:

```sh
sh tests/cpu/cache_admit_probe/sim.sh
```

An ordinary, permission-checked cacheable read may consume the synchronous
RAM-B read completed on its demand-admission edge. The test deliberately clears
the older completed probe token, so the preexisting immediate-hit path cannot
satisfy the request. It checks the admission edge and the later consumer edge,
exactly one response, and no backing traffic for resident reads.

Coverage: 256 short reads over eight segments, every word, two resident ways
and all byte masks; natural mismatched-line fallback; isolated full-line and
way mismatches injected into the pending probe owner; changed next-address
input; fresh post-store bytes; maintenance offered after admission; permission,
alignment and translation waits; SWP, uncached accesses and reset cancellation.
The isolated injected mismatches ensure one guard cannot hide another.

The optional `CACHE_ACCESS_RTL` environment variable selects an isolated cache
controller candidate for experiments. An optional first argument selects a new
output directory. These are simulation controls, not core compilation options.
Existing cache_probe and cache_dirty_packed tests cover RAM-port collisions and
ordered dirty writeback; CPU tests cover load formatting and abort context.
