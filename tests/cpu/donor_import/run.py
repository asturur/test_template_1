#!/usr/bin/env python3
"""Freeze CPU source variants and run identical benchmarks without checkouts.

prepare NAME: snapshot both user-pinned commits, current work and its saved
old-controller control; assemble each benchmark ONCE for all variants.
run NAME: execute selected cases in the existing simulator image.
compare NAME ATTEMPT: compare successful, identically configured observations.
"""
import argparse
import hashlib
import json
import re
import shutil
import statistics
import subprocess
import sys
from pathlib import Path

from benchmarks import assembly, cases

ROOT = Path(__file__).resolve().parents[3]
IMAGE = "jotego/simulator:arm64"
REFERENCES = {
    "h0": "ce8d2c902724a59e7537b845bc841dbd82d5bbf7",
    "h1": "3f5e8aeae3260562a814eacdd8d8aa505c044af8",
}
PREVIOUS = {
    "Template.sv": "Template.sv",
    "rtl/ngage_sdram_adapter.v": "ngage_sdram_adapter.v",
    "rtl/ngage_dma_ram_mux.v": "ngage_dma_ram_mux.v",
    "rtl/sdram/jtframe_sdram64.v": "jtframe_sdram64.v",
    "rtl/sdram/jtframe_sdram64_bank.v": "jtframe_sdram64_bank.v",
    "rtl/sdram/jtframe_sdram64_init.v": "jtframe_sdram64_init.v",
}
METRICS = ("cycles", "retire_proxy", "reads", "writes", "lines", "halfwords")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def git(*args, root=ROOT):
    return subprocess.check_output(["git", *args], cwd=root)


def source_path(name):
    """Explicit project-only closure: exclude personal configs/media/secrets."""
    return (name.startswith(("rtl/arm/", "rtl/arm920/", "rtl/sdram/", "patches/zap/"))
            or name in {"rtl/ngage_cpu.sv", "rtl/ngage_bram.v", "Template.sv", "files.qip"}
            or re.fullmatch(r"rtl/ngage_sdram\w*\.v", name) is not None
            or name == "rtl/ngage_dma_ram_mux.v")


def snapshot(destination, revision=None, root=ROOT):
    destination.mkdir(parents=True)
    if revision:
        commit = git("rev-parse", "--verify", revision + "^{commit}", root=root).decode().strip()
        names = git("ls-tree", "-r", "--name-only", "-z", commit, root=root).decode().split("\0")
        files = {name: git("show", f"{commit}:{name}", root=root)
                 for name in names if source_path(name)}
        kind = "git"
    else:
        commit = git("rev-parse", "HEAD", root=root).decode().strip()
        names = git("ls-files", "-z", "--cached", "--others", "--exclude-standard", root=root).decode().split("\0")
        files = {name: (root / name).read_bytes()
                 for name in set(names) if source_path(name) and (root / name).is_file()}
        # Refuse a mixed snapshot if concurrent work changes any captured file.
        if any((root / name).read_bytes() != data for name, data in files.items()):
            raise RuntimeError("source changed while freezing working tree; retry preparation")
        kind = "working-tree"
    required = {"rtl/ngage_cpu.sv", "rtl/arm/zap_core.sv", "rtl/arm920/cache_access.sv"}
    if not required <= files.keys():
        raise RuntimeError(f"incomplete source snapshot: {sorted(required - files.keys())}")
    for name, data in files.items():
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    return source_manifest(destination, commit, kind)


def source_manifest(directory, commit, kind):
    hashes = {str(p.relative_to(directory)): digest(p.read_bytes())
              for p in sorted(directory.rglob("*")) if p.is_file()}
    wrapper = (directory / "rtl/ngage_cpu.sv").read_text()
    return dict(commit=commit, kind=kind, files=hashes,
                source_id=digest(json.dumps(hashes, sort_keys=True).encode()),
                has_line="parameter LINE_REFILL" in wrapper)


def old_controller_control(working, destination, previous):
    missing = [str(previous / name) for name in PREVIOUS.values()
               if not (previous / name).is_file()]
    if missing:
        return dict(status="BLOCKED", reason="saved controller sources missing", missing=missing)
    shutil.copytree(working, destination)
    for target, name in PREVIOUS.items():
        (destination / target).write_bytes((previous / name).read_bytes())
    return dict(overrides=list(PREVIOUS), status="PREPARED")


def command(command_line, log, cwd=ROOT):
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w") as output:
        output.write(json.dumps(command_line) + "\n")
        output.flush()
        result = subprocess.run(command_line, cwd=cwd, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {log}")


def symbols(nm_output):
    found = {}
    for line in nm_output.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[2] in {"body_begin", "body_end"}:
            found[parts[2]] = int(parts[0], 16)
    if set(found) != {"body_begin", "body_end"} or found["body_end"] <= found["body_begin"]:
        raise ValueError("missing or invalid ELF window markers")
    return found


def parse_log(log, case):
    """Reject incomplete/duplicated counters even when a process exits zero."""
    if re.search(r"(?im)(?:^|\s)(?:fatal|error|%error)(?::|\b)", log):
        raise ValueError("simulator diagnostic in output")
    windows = []
    for line in log.splitlines():
        if not line.startswith("WINDOW "):
            continue
        fields = dict(re.findall(r"(\w+)=(-?\d+)", line))
        if set(fields) != {"index", *METRICS}:
            raise ValueError("incomplete window metrics")
        value = {k: int(v) for k, v in fields.items()}
        if value["index"] != len(windows) or any(value[k] < 0 for k in METRICS) or value["cycles"] == 0:
            raise ValueError("invalid, duplicated or out-of-order window")
        windows.append(value)
    terminal = [line for line in log.splitlines() if line.startswith("RESULT ")]
    if len(terminal) != 1:
        raise ValueError("expected exactly one checked guest completion")
    total = {k: int(v) for k, v in re.findall(r"(\w+)=(-?\d+)", terminal[0])}
    expected = case["warmups"] + case["samples"]
    if len(windows) != expected or total.get("windows") != expected:
        raise ValueError("missing window or completion count")
    if set(total) != {"windows", "cycles", "reads", "writes", "lines", "halfwords"}:
        raise ValueError("incomplete terminal metrics")
    for key in ("cycles", "reads", "writes", "lines", "halfwords"):
        if total[key] < sum(w[key] for w in windows):
            raise ValueError("window accounting exceeds whole run")
    measured = windows[case["warmups"]:]
    return dict(status="PASS", windows=windows, total=total,
                body_cycles_median=statistics.median(w["cycles"] for w in measured),
                cycles_per_operation=statistics.median(w["cycles"] for w in measured) / case["operations"])


def compare_rows(rows, reference, candidate):
    def key(row):
        return tuple(row[k] for k in ("case", "mode", "profile", "seed", "jitter"))
    indexed = {}
    for row in rows:
        identity = (row["variant"], key(row))
        if identity in indexed:
            raise ValueError("duplicate comparison observation")
        indexed[identity] = row
    output = []
    for (variant, identity), old in sorted(indexed.items()):
        if variant != reference:
            continue
        new = indexed.get((candidate, identity))
        if not new or old["status"] != "PASS" or new["status"] != "PASS":
            output.append(dict(case=identity[0], mode=identity[1], profile=identity[2],
                               seed=identity[3], jitter=identity[4], status="BLOCKED"))
            continue
        for field in ("binary_sha256", "harness_sha256", "operations", "warmups", "samples", "memory_model", "image_id"):
            if old[field] != new[field]:
                raise ValueError(f"incomparable {field}: {identity}")
        a, b = old["body_cycles_median"], new["body_cycles_median"]
        output.append(dict(case=identity[0], mode=identity[1], profile=identity[2],
                           seed=identity[3], jitter=identity[4], status="PASS",
                           reference_cycles=a, candidate_cycles=b,
                           cycles_saved=1-b/a, throughput_gain=a/b-1))
    return output


def locations(name):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}", name) or name in {".", ".."}:
        raise ValueError("invalid experiment name")
    return (ROOT / "scratch/cpu-donor-import" / name,
            ROOT / "build/sim/cpu-donor-import" / name)


def prepare(args):
    scratch, output = locations(args.name)
    if scratch.exists() or output.exists():
        raise ValueError("experiment name already exists; use a new name")
    for tool in ("arm-none-eabi-gcc", "arm-none-eabi-ld", "arm-none-eabi-objcopy", "arm-none-eabi-nm"):
        if not shutil.which(tool):
            raise RuntimeError(f"missing {tool}")
    output.mkdir(parents=True)
    variants = {}
    for name, revision in REFERENCES.items():
        directory = scratch / name
        variants[name] = snapshot(directory, revision)
        variants[name]["directory"] = str(directory.relative_to(ROOT))
    working = scratch / "working"
    variants["working"] = snapshot(working)
    variants["working"]["directory"] = str(working.relative_to(ROOT))
    control = scratch / "working_previous_sdram"
    previous = ROOT / "scratch/sdram-specialize-20261112/before"
    details = old_controller_control(working, control, previous)
    if details["status"] == "PREPARED":
        variants["working_previous_sdram"] = source_manifest(control, variants["working"]["commit"], "matched-override")
        variants["working_previous_sdram"].update(details, directory=str(control.relative_to(ROOT)))
        # CPU/cache files must be identical in the controller attribution pair.
        for name, sha in variants["working"]["files"].items():
            if name not in PREVIOUS and sha != variants["working_previous_sdram"]["files"][name]:
                raise ValueError("matched controller control changed another source")
    else:
        variants["working_previous_sdram"] = details
    benchmarks = []
    linker = output / "link.ld"
    linker.write_text("ENTRY(_start)\nSECTIONS { . = 0; .text : { *(.vectors) *(.text*) *(.rodata*) } .data : { *(.data*) } .bss : { *(.bss*) *(COMMON) } }\n")
    harness = output / "tb.sv"
    harness.write_bytes(Path(__file__).with_name("tb.sv").read_bytes())
    for case in cases():
        directory = output / "programs" / case["id"]
        directory.mkdir(parents=True)
        source = directory / "program.S"
        source.write_text(assembly(case))
        obj, elf, binary = [directory / ("program." + suffix) for suffix in ("o", "elf", "bin")]
        command(["arm-none-eabi-gcc", "-c", "-mcpu=arm920t", "-marm", str(source), "-o", str(obj)], directory / "assemble.log")
        command(["arm-none-eabi-ld", "-T", str(linker), str(obj), "-o", str(elf)], directory / "link.log")
        command(["arm-none-eabi-objcopy", "-O", "binary", str(elf), str(binary)], directory / "objcopy.log")
        data = binary.read_bytes()
        if len(data) > 65536:
            raise ValueError("program exceeds test ROM")
        padded = data + bytes((-len(data)) % 4)
        hexdump = directory / "program.hex"
        # Pad the ROM explicitly so readmemh never relies on uninitialized words.
        padded += bytes(65536-len(padded))
        hexdump.write_text("".join(f"{int.from_bytes(padded[n:n+4], 'little'):08x}\n" for n in range(0, len(padded), 4)))
        nm = subprocess.check_output(["arm-none-eabi-nm", str(elf)], text=True)
        benchmarks.append({**case, **symbols(nm), "binary_sha256": digest(data),
                           "hex_sha256": digest(hexdump.read_bytes()), "hex": str(hexdump.relative_to(ROOT))})
    manifest = dict(schema=1, status="PREPARED_NOT_SIMULATED", image=IMAGE,
                    memory_model="synthetic-scalar-line-v1-not-physical-sdram",
                    harness=str(harness.relative_to(ROOT)), harness_sha256=digest(harness.read_bytes()),
                    variants=variants, benchmarks=benchmarks,
                    scope="First ARM kernel batch B/C/D/E/F/G; architectural Thumb/IRQ, compiled C and gameplay remain unimplemented.",
                    controller_warning="These CPU tests do not instantiate SDRAM RTL; the matched controller pair is a negative control here, not a controller speed measurement.")
    manifest["preparation"] = dict(
        gcc=subprocess.check_output(["arm-none-eabi-gcc", "--version"], text=True).splitlines()[0],
        linker_sha256=digest(linker.read_bytes()),
        runner_sha256=digest(Path(__file__).read_bytes()),
        generator_sha256=digest(Path(__file__).with_name("benchmarks.py").read_bytes()))
    write_json(output / "manifest.json", manifest)
    print(f"Prepared {len(benchmarks)} shared binaries and {len(variants)} source variants: {output / 'manifest.json'}")


def container_path(path):
    return "/work/" + str(Path(path).resolve().relative_to(ROOT))


def validate_frozen(manifest):
    harness = ROOT / manifest["harness"]
    if digest(harness.read_bytes()) != manifest["harness_sha256"]:
        raise ValueError("frozen harness changed")
    for variant in manifest["variants"].values():
        if "directory" not in variant:
            continue
        for name, sha in variant["files"].items():
            if digest((ROOT / variant["directory"] / name).read_bytes()) != sha:
                raise ValueError(f"frozen source changed: {name}")
    for case in manifest["benchmarks"]:
        if digest((ROOT / case["hex"]).read_bytes()) != case["hex_sha256"]:
            raise ValueError(f"frozen program changed: {case['id']}")


def run(args):
    _, output = locations(args.name)
    manifest = json.loads((output / "manifest.json").read_text())
    validate_frozen(manifest)
    attempts = output / "attempts"
    attempts.mkdir(exist_ok=True)
    index = 1
    while (attempts / f"{index:04d}").exists():
        index += 1
    attempt = attempts / f"{index:04d}"
    attempt.mkdir()
    try:
        probe = subprocess.run(["docker", "image", "inspect", IMAGE, "--format", "{{.Id}}"], capture_output=True, text=True)
    except FileNotFoundError:
        write_json(attempt / "result.json", dict(status="BLOCKED", reason="Docker executable unavailable", rows=[]))
        print(f"BLOCKED: Docker executable unavailable: {attempt / 'result.json'}")
        return 2
    if probe.returncode:
        write_json(attempt / "result.json", dict(status="BLOCKED", reason=probe.stderr.strip(), rows=[]))
        print(f"BLOCKED: Docker/image access; details: {attempt / 'result.json'}")
        return 2
    image_id = probe.stdout.strip()
    rows = []
    selected = args.variant or list(manifest["variants"])
    unknown = set(selected)-set(manifest["variants"])
    requested = set(args.case or [])
    if unknown or requested-{c["id"] for c in manifest["benchmarks"]}:
        raise ValueError("unknown variant or benchmark")
    profiles = args.profile or ["0:0", "0:3", "2:9"]
    if any(not re.fullmatch(r"\d+:\d+", p) for p in profiles):
        raise ValueError("profiles must be nonnegative I:D waits")
    seeds = args.seed or [1]
    if args.jitter < 0 or any(s < 0 or s > 0x7fffffff for s in seeds):
        raise ValueError("invalid jitter or seed")
    for values in (selected, profiles, seeds, args.mode or ["scalar", "line"]):
        if len(values) != len(set(values)):
            raise ValueError("duplicate variants/profiles/seeds/modes would overwrite run logs")
    if args.jobs < 1:
        raise ValueError("jobs must be positive")
    docker = ["docker", "run", "--rm", "--pull=never", "--network", "none", "--platform", "linux/arm64",
              "-v", str(ROOT) + ":/work", "-w", "/work", "--entrypoint"]
    for name in selected:
        variant = manifest["variants"][name]
        if "directory" not in variant:
            rows.append(dict(variant=name, status="BLOCKED", reason=variant.get("reason")))
            continue
        source = ROOT / variant["directory"]
        rtl = [source / "rtl/ngage_cpu.sv", source / "rtl/ngage_bram.v"]
        for directory in ("rtl/arm", "rtl/arm920"):
            rtl += sorted(p for p in (source / directory).iterdir() if p.suffix in {".sv", ".v"})
        for mode in args.mode or ["scalar", "line"]:
            build = attempt / name / mode / "obj"
            build.parent.mkdir(parents=True)
            compiler = ["verilator", IMAGE, "--binary", "--timing", "--assert", "-j", str(args.jobs),
                        "-Wno-fatal", "-Wno-lint", "-DNGAGE_RUNTIME_TRACE", "--top-module", "bench",
                        "--Mdir", container_path(build), "-I" + container_path(source / "rtl/arm"),
                        "-GLINE_ENABLE=" + str(int(mode == "line" and variant["has_line"]))]
            if variant["has_line"]:
                compiler.append("-DBENCH_HAS_LINE")
            try:
                command(docker + compiler + [container_path(p) for p in rtl] + [container_path(ROOT / manifest["harness"])], build.parent / "build.log")
            except RuntimeError as exc:
                rows.append(dict(variant=name, mode=mode, status="FAIL", reason=str(exc)))
                continue
            for case in manifest["benchmarks"]:
                if requested and case["id"] not in requested:
                    continue
                for profile in profiles:
                    iw, dw = profile.split(":")
                    for seed in seeds:
                        directory = build.parent / case["id"] / profile.replace(":", "-") / str(seed)
                        log = directory / "run.log"
                        row = dict(variant=name, source_id=variant["source_id"], case=case["id"],
                                   mode=mode, line_enabled=mode == "line" and variant["has_line"],
                                   profile=profile, seed=seed, jitter=args.jitter, image_id=image_id,
                                   binary_sha256=case["binary_sha256"], harness_sha256=manifest["harness_sha256"],
                                   memory_model=manifest["memory_model"], operations=case["operations"],
                                   warmups=case["warmups"], samples=case["samples"], log=str(log.relative_to(ROOT)))
                        try:
                            command(docker + [container_path(build / "Vbench"), IMAGE,
                                    "+program=" + container_path(ROOT / case["hex"]),
                                    f"+begin_pc={case['body_begin']:x}", f"+end_pc={case['body_end']:x}",
                                    f"+i_wait={iw}", f"+d_wait={dw}", f"+seed={seed}", f"+jitter={args.jitter}",
                                    "+ngage-compact-trace"], log)
                            row.update(parse_log(log.read_text(), case))
                        except (RuntimeError, ValueError) as exc:
                            row.update(status="FAIL", reason=str(exc))
                        rows.append(row)
                        write_json(directory / "result.json", row)
                        print(name, mode, case["id"], profile, seed, row["status"], flush=True)
    state = "PASS" if rows and all(row["status"] == "PASS" for row in rows) else "FAIL"
    write_json(attempt / "result.json", dict(status=state, rows=rows, image_id=image_id))
    return 0 if state == "PASS" else 1


def compare(args):
    _, output = locations(args.name)
    result = json.loads((output / "attempts" / args.attempt / "result.json").read_text())
    rows = [r for r in result["rows"] if "case" in r]
    comparisons = {}
    for a, b in (("h0", "h1"), ("h1", "working"), ("h0", "working"),
                 ("working_previous_sdram", "working")):
        paired = compare_rows(rows, a, b)
        if a == "working_previous_sdram":
            for row in paired:
                if row["status"] == "PASS" and row["reference_cycles"] != row["candidate_cycles"]:
                    row.update(status="FAIL", reason="controller-only changes affected a synthetic model that does not instantiate the controller")
        state = ("NOT_RUN" if not paired else "FAIL" if any(r["status"] == "FAIL" for r in paired)
                 else "PASS" if all(r["status"] == "PASS" for r in paired) else "BLOCKED")
        comparisons[a + "__" + b] = dict(status=state, rows=paired)
    write_json(output / "attempts" / args.attempt / "comparison.json", comparisons)
    print(json.dumps(comparisons, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("prepare", "run", "compare"):
        sub = commands.add_parser(name)
        sub.add_argument("name")
        if name == "compare":
            sub.add_argument("attempt")
        if name == "run":
            sub.add_argument("--variant", action="append")
            sub.add_argument("--case", action="append")
            sub.add_argument("--mode", choices=("scalar", "line"), action="append")
            sub.add_argument("--profile", action="append")
            sub.add_argument("--seed", action="append", type=int)
            sub.add_argument("--jitter", type=int, default=0)
            sub.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    try:
        return {"prepare": prepare, "run": run, "compare": compare}[args.command](args) or 0
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
