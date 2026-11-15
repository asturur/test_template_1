#!/usr/bin/env python3
"""Exhaust the FIFO flag equations over every reachable pointer/control state."""
import json

checks = 0
for depth in (2, 4, 8, 16, 32, 64, 128, 256):
    mask = 2 * depth - 1
    for read_pointer in range(2 * depth):
        for count in range(depth + 1):
            write_pointer = (read_pointer + count) & mask
            empty, full = count == 0, count == depth
            for controls in range(16):
                wr, rd, clear, reset = [bool(controls & (1 << bit)) for bit in range(4)]
                write_ok, read_ok = wr and not full, rd and not empty
                # Prior implementation: accepted increments then equality.
                next_w = (write_pointer + write_ok) & mask
                next_r = (read_pointer + read_ok) & mask
                old = (next_w == next_r, next_w == (next_r ^ depth))
                # Candidate: the transfer selector arrives after comparisons.
                new = (empty, full)
                if write_ok and not read_ok:
                    new = (False, ((write_pointer + 1) & mask) == (read_pointer ^ depth))
                elif read_ok and not write_ok:
                    new = (write_pointer == ((read_pointer + 1) & mask), False)
                if clear or reset:
                    old = new = (True, False)
                assert old == new, (depth, read_pointer, count, controls, old, new)
                checks += 1
print(json.dumps(dict(status="PASS", reachable_pointer_control_states=checks,
                      depths=[2, 4, 8, 16, 32, 64, 128, 256])))
