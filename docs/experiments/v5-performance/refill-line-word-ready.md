# Register the native refill word-ready flag

The [design patch](patches/refill-line-word-ready.patch) changes only the refill module in `rtl/ngage_cpu.sv` on exact timer base `9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e`, tree `0ccd13d8cd502bc14d3b89c6431ff0ebe4745612`. It replaces the LINE response's live received-versus-consumed comparison with the low bit of an eight-bit thermometer occupancy register. The pinned Verible formatting check passed.

## Routed witness

Timer seed 31337 hot rank 3 starts at `refill.received[4]`, passes through `cpu_ack~2`, `cpu_ack~3`, cache `take` and its next-packet logic, and ends at the Wishbone merger's `o_wb_adr[17]` at −2.214 ns. This start belongs to native LINE. Timer seed 43 hot rank 1 traverses the same two ACK cells and a cache `take` before reaching merger `o_wb_adr[6]` at −2.403 ns. Its start is the fitter's retimed `cpu_ack~1_OTERM10890`. The latter report names a retimed ACK term, while seed 31337 directly identifies the received counter as a launch. The candidate changes the LINE arm of the merged ACK feedback. The scalar reply path continues to use its original same-edge or registered-owner protocol.

The earlier Wishbone completion experiment coupled a registered line magnitude comparison to an added scalar reply stage. This candidate keeps the scalar protocol and evaluates occupancy with a shift instead of a next-count adder and comparator. The new ready register defines the start of the LINE ACK cone. Its own input can still depend on line valid, width, assembly phase, and CPU CYC. Routed timing and area require measurement.

## Invariant and capture contract

For every healthy active LINE after admission, let `n = floor(received / 2) - consumed`. The stored bit at index `i` equals `n > i`. Both counters and the occupancy start at zero. The existing accepted beat condition is `line_valid && received < 16` while LINE owns the port. An aligned wide beat adds four halfwords and two complete words. A narrow beat adds one word exactly when the held low bit of received was one, which is the edge that writes the existing assembled word. The zero-bit ready flag is evaluated before that edge, so a simultaneous pop retires a previously assembled word. Net shifts of −1, 0, +1 or +2 preserve the invariant. The final consumption exits LINE, and the next admission starts with an empty register.

The original framing assertions remain active. A wide beat requires `received[1:0] == 0`, and every visible beat requires `received < 16`. For a beat without error, `line_last` must agree with the resulting halfword count being 16. A rejection requires `received == 0`, and a line that promised no late error cannot issue an error beat. In healthy LINE, assembly and retirement therefore keep the occupancy in the range 0 through 8. A simulation assertion checks the old versus new ready predicate on every healthy active edge, and the directed fixture checks all eight bits on its comparison points.

The original active-owner assertion requires CYC high, a read packet, the address offset equal to `consumed * 4`, and the appropriate burst or end CTI at each non-reset LINE clock. The combinational ACK and ERR outputs still follow CYC immediately. The fixture withdraws and restores CYC between edges, then resets active assembled, half-assembled, and failed transfers. Scalar cancellation also crosses an edge, including a discarded response after withdrawal. Error retirement advances the original consumed counter with the original priority. The occupancy is ignored while failed because ERR owns the response, and the next admission clears it. The original line buffers, scalar ownership, parameters, defaults, and reset and fallback state transitions remain in use.

## Qualification

- The exact dual-adapter fixture passed all four combinations of native LINE enable and scalar peer registration. Each enabled mode completed 105 native lines and 53 error sequences, plus 29 simultaneous narrow push/pop and 110 wide push/pop edges. It also checked three LINE withdrawals and resets, rejected-burst handoff, scalar reads and writes, two scalar errors, and dropped-CYC behavior. The four logs recorded 6,886 interface comparisons.
- All four ARM9v2 board burst/wait combinations, 105 fixed windows, 15 repeat cases, all 15 expected wrong-output failures, and all four native frames matched the timer baseline. The frame clocks were 14,391,395, 14,467,552, 14,346,201, and 14,303,223 with the same guest output and architectural and valid-write digests.
- The normal physical SDRAM trace matched 171,496 records over 1,201,547 clocks. Timer/MMC/LCD overlap matched 171,497 records over 1,201,528 clocks. The candidate wrapper was the sole difference among 114 physical source hashes and compiled with the same fingerprint in board, fixed, native, and physical replays.

[Qualification receipt](../../evidence/v5-104-refill-line-word-ready.json)

The [stack with the SDRAM payload change](refill-payload-combined.md)
uses the same qualified wrapper and matches the exact payload control
in the native refill workload decks and all three pin replays.

## 104 MHz fit

The SDRAM payload trial was parked. Standalone native refill candidate
`9929983` builds above exact timer restore `85b21a4`, with physical 104 MHz
and DDR debug off. The matched control is timer-only `9f16d1a`. [Seed 13](https://github.com/asturur/test_template_1/actions/runs/45863520207) · [Seed 43](https://github.com/asturur/test_template_1/actions/runs/45863524825) · [Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45863528948)

## Routed decision

Park `9929983` for mix-and-match. All three fits pass native hold,
recovery, removal, minimum pulse width and SDRAM pin register packing,
and all three fail 104 MHz setup. Seed 31337 improves by 0.190 ns.

| Seed | Worst setup, timer → word-ready | Core TNS delta | Occupied ALM delta | Estimated ALMs needed delta |
| ---: | ---: | ---: | ---: | ---: |
| 13 | −2.214 → −2.764 ns | −3,292.695 ns | −165 | −161 |
| 43 | −2.403 → −2.594 ns | −1,321.134 ns | −59 | −184 |
| 31337 | −2.452 → −2.262 ns | −1,169.901 ns | −29 | −18 |

The old refill-to-merger family leaves all four corner samples across
all three seeds. It had appeared in both slow samples on seeds 43 and
31337. No new `ready_words` destination enters those samples. Median setup
falls by 0.191 ns and median core TNS worsens by 1,350.926 ns. The paired
median TNS delta is −1,321.134 ns. Occupancy falls on each seed, with a
paired median reduction of 59 ALMs. M10Ks remain at 321. The new limiting
paths end in predictor validity, the invalid-UPP response, and the SDRAM
command address. [Matched fits and route sample](../../evidence/v5-104-refill-line-word-ready-fits.json)

## Reproduction

Run from the repository root with the archived design and fixture patches, the private timer object chain, the existing timer and prepared Wishbone replay decks, the ARM GNU tools, and the cached Jotego ARM64 image. The design and [replay patch](patches/refill-line-word-ready-replay.patch) are in the experiment archive.

```sh
area=scratch/v5-fit-loop/refill-line-word-ready
patches=docs/experiments/v5-performance/patches
timer=scratch/v5-fit-loop/timer-live-trust-combined/dispatch-20261126
out=build/sim/v5-104-refill-line-word-ready
for leg in reference source; do
  mkdir -p "$area/$leg"
  env GIT_OBJECT_DIRECTORY="$PWD/$timer/objects" \
    GIT_ALTERNATE_OBJECT_DIRECTORIES="$(cat "$timer/alternate-objects.txt")" \
    git archive 9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e rtl tools .rules.verible_format \
      tests/cpu/arm9v2_board tests/cpu/spmark_payload tests/phone/upp_ddr_ram/peer.v \
      sim/programs/link.ld | tar -x -C "$area/$leg"
done
git apply "$patches/refill-line-word-ready-replay.patch"
git apply --directory="$area/source" "$patches/refill-line-word-ready.patch"
cp "$patches/refill-line-word-ready.patch" "$patches/refill-line-word-ready-replay.patch" "$area"
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"

python3 -B "$area/prepare-miter.py"
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$out/miter:/work" -w /work --entrypoint sh jotego/simulator:arm64 -ec '
  for enable in 0 1; do
    for registered in 0 1; do
      tag=$enable-$registered
      iverilog -g2012 -s tb -Ptb.ENABLE="$enable" -Ptb.REGISTERED="$registered" \
        -o "$tag" tb.sv retained.v trial.v
      vvp "$tag" > "$tag.log"
      grep "^PASS " "$tag.log"
    done
  done'
sh "$area/board.sh"
for kind in fixed native; do
  python3 -B "$area/replay.py" "$kind" --output qualification
done
python3 -B "$area/mixed.py"
mixed="$out/mixed"
docker image inspect -f '{{.Id}} {{.Os}}/{{.Architecture}}' jotego/simulator:arm64 > "$out/image.id"
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 \
  -ec "sh '$mixed/build.sh'
'$mixed/obj/Vtb' +upp_stress '+compare_trace=$mixed/traffic.log' > '$mixed/replay.log'"
sh "$area/coexistence.sh"
python3 -B "$area/record.py"
```
