#!/usr/bin/env python3
"""Build and run the first N-Gage CPU evaluation, without changing upstream RTL."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import struct
import subprocess
import sys

from rom_extension import DEFAULT as DEFAULT_EXTENSION, validate as validate_extension
from adc_inputs import parse_inputs, encode_inputs, case_suffix
from digest_probe import build as build_digest_probe

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "sim"
ARM = ROOT / "rtl" / "arm"
IMAGE = os.environ.get("SIM_IMAGE", "jotego/simulator:arm64")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def execute(command, log, cwd=ROOT, allowed=(0,)):
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w") as output:
        output.write(shlex.join(map(str, command)) + "\n")
        output.flush()
        result = subprocess.run(list(map(str, command)), cwd=cwd, stdout=output,
                                stderr=subprocess.STDOUT, check=False)
    if result.returncode not in allowed:
        print("\n".join(log.read_text(errors="replace").splitlines()[-20:]), file=sys.stderr)
        raise RuntimeError(f"command failed ({result.returncode}); see {log}")


def docker(command, extra_mounts=()):
    args = ["docker", "run", "--rm", "--network", "none", "--mount",
            f"type=bind,src={ROOT},dst=/work", "--workdir", "/work", "--platform", "linux/arm64"]
    for mount in extra_mounts:
        args += ["--mount", mount]
    return args + ["--entrypoint", str(command[0]), IMAGE] + list(map(str, command[1:]))


def container_path(path):
    return "/work/" + str(path.relative_to(ROOT))


def environment():
    for tool in ("docker", "arm-none-eabi-gcc", "arm-none-eabi-ld", "arm-none-eabi-objcopy",
                 "arm-none-eabi-objdump"):
        if shutil.which(tool) is None:
            raise RuntimeError(f"required tool not found: {tool}")
    metadata = json.loads((ARM / "UPSTREAM.json").read_text())
    result = subprocess.run(["docker", "image", "inspect", IMAGE, "--format", "{{.Id}}"],
                            capture_output=True, text=True, check=False)
    if result.returncode:
        raise RuntimeError(f"simulator image unavailable: {IMAGE}; set SIM_IMAGE to a prepared image")
    return {"zap_commit": metadata["commit"], "simulator_image": IMAGE,
            "simulator_image_id": result.stdout.strip(), "zap_rtl": "rtl/arm"}


# rtl/arm is the patched CPU (upstream + patches/zap, checked by
# patches/zap/verify.sh). The original upstream is only downloaded, to
# scratch/zap-upstream (shared with verify.sh), for the unmodified comparison
# and for the upstream regression bench (Makefile, testbench, test programs).
def pristine_zap():
    metadata = json.loads((ARM / "UPSTREAM.json").read_text())
    target = ROOT / "scratch" / "zap-upstream"
    stamp = target / ".commit"
    if not stamp.exists() or stamp.read_text().strip() != metadata["commit"]:
        shutil.rmtree(target, ignore_errors=True)
        target.mkdir(parents=True)
        url = f"https://github.com/krevanth/ZAP/archive/{metadata['commit']}.tar.gz"
        archive = subprocess.run(["curl", "-sfL", url], capture_output=True, check=True).stdout
        subprocess.run(["tar", "-xz", "--strip-components=1", "-C", target], input=archive, check=True)
        stamp.write_text(metadata["commit"] + "\n")
    for name, expected in metadata["files"].items():
        if digest(target / name) != expected:
            raise RuntimeError(f"downloaded upstream differs from the pin: {name}")
    return target


def prepare_zap(info, variant, destination=None):
    """Return the CPU RTL directory, or with `destination` a full upstream-layout
    tree (for the upstream bench) whose src/rtl is the selected variant."""
    patches = sorted((ROOT / "patches" / "zap").glob("*.patch")) if variant == "ngage" else []
    info["zap_variant"] = variant
    info["zap_patches"] = [{"path": str(p.relative_to(ROOT)), "sha256": digest(p)} for p in patches]
    if destination is None:
        return (ARM if variant == "ngage" else pristine_zap() / "src" / "rtl"), patches
    shutil.copytree(pristine_zap(), destination, dirs_exist_ok=True)
    if variant == "ngage":
        for source in list(ARM.glob("*.sv")) + list(ARM.glob("*.svh")):
            shutil.copy2(source, destination / "src" / "rtl" / source.name)
    return destination, patches


def build_simulator(info, variant):
    rtl, patches = prepare_zap(info, variant)
    source = sorted(rtl.glob("*.sv"))
    inputs = source + sorted(rtl.glob("*.svh")) + patches + [
        ROOT / "rtl" / "ngage_cpu.sv", ROOT / "sim" / "ngage_cpu_sim.sv", ROOT / "sim" / "main.cpp",
        ROOT / "sim" / "boot_profile.cpp", ROOT / "sim" / "boot_profile.h", Path(__file__)]
    key = hashlib.sha256((info["simulator_image_id"] + "".join(digest(p) for p in inputs)).encode()).hexdigest()
    stamp = BUILD / f"build-key-{variant}"
    objdir = BUILD / f"obj-{variant}"
    binary = objdir / "Vngage_cpu_sim"
    if not (binary.exists() and stamp.exists() and stamp.read_text() == key):
        print("Building the standalone ZAP simulator...", flush=True)
        command = ["verilator", "--cc", "--exe", "--build", "-j", "4", "--assert", "-DNGAGE_RUNTIME_TRACE",
                   "-Wno-fatal", "-Wno-lint", "--x-initial", "0", "--x-assign", "0",
                   "--top-module", "ngage_cpu_sim", "--Mdir", str(objdir.relative_to(ROOT)),
                   "-I" + str(rtl.relative_to(ROOT)), "rtl/ngage_cpu.sv", "sim/ngage_cpu_sim.sv"]
        command += [str(p.relative_to(ROOT)) for p in source]
        command += ["/work/sim/main.cpp", "/work/sim/boot_profile.cpp"]
        execute(docker(command), BUILD / "build.log")
        stamp.write_text(key)
    manifest = dict(build_key=key, simulator_image=info["simulator_image"],
                    simulator_image_id=info["simulator_image_id"], binary_sha256=digest(binary),
                    inputs={str(path.relative_to(ROOT)):digest(path) for path in inputs})
    (objdir / "ngage-build-manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    return binary


def assemble(name, source=None, defines=()):
    directory = BUILD / "programs"
    directory.mkdir(parents=True, exist_ok=True)
    obj, elf, binary = (directory / f"{name}.{ext}" for ext in ("o", "elf", "bin"))
    execute(["arm-none-eabi-gcc", "-c", "-mcpu=arm920t", "-marm", *defines,
             ROOT / "sim" / "programs" / f"{source or name}.S", "-o", obj], directory / f"{name}-assemble.log")
    execute(["arm-none-eabi-ld", "-T", ROOT / "sim" / "programs" / "link.ld",
             obj, "-o", elf], directory / f"{name}-link.log")
    execute(["arm-none-eabi-objcopy", "-O", "binary", elf, binary], directory / f"{name}-objcopy.log")
    execute(["arm-none-eabi-objdump", "-d", elf], directory / f"{name}.disasm")
    return binary


def run_case(binary, name, rom, latency=0, firmware=False, limit=500000, probe=False, boot_profile="none", ideal_clocks=False, lcd_probe=False, compact_trace=False, rom_extension=None, boot_io_probe=False, expected_status=None, adc_inputs=None, timer_irq_delay=0):
    if binary.parent.name == "obj-upstream":
        name = "unmodified-" + name
    directory = BUILD / "runs" / name
    directory.mkdir(parents=True, exist_ok=True)
    result_path = directory / "result.json"
    # Discard old contents before launch, but retain a host-created inode for
    # Docker Desktop bind mounts. Unlink/recreate has intermittently returned
    # ENOENT inside the container despite the host directory being present.
    # Empty output is still rejected, so a failed run cannot reuse old results.
    result_path.write_text("")
    board_sources = {f"sim/{file}": digest(ROOT / "sim" / file) for file in ("boot_profile.cpp", "boot_profile.h")}
    mounts = []
    if firmware:
        rom_argument = "/input/SYM.ROM"
        mounts.append(f"type=bind,src={rom},dst={rom_argument},readonly")
    else:
        rom_argument = container_path(rom)
    command = [container_path(binary), rom_argument, str(limit), str(latency),
               container_path(directory / "instructions.tsv"),
               container_path(directory / "bus.tsv"),
               container_path(directory / "cp15.tsv"), container_path(result_path)]
    if boot_profile != "none":
        command.append(boot_profile)
        if ideal_clocks:
            command.append("ideal-clocks")
        if lcd_probe:
            command.append("lcd-probe")
        if boot_io_probe:
            command.append("boot-io-probe")
        if compact_trace:
            command.append("+ngage-compact-trace")
    if timer_irq_delay:
        command.append("timer-irq-delay=" + str(timer_irq_delay))
    if adc_inputs:
        command.append("uem-adc=" + encode_inputs(adc_inputs))
    if rom_extension:
        mounts.append(f"type=bind,src={rom_extension},dst=/input/extension.bin,readonly")
        command.append("rom-extension=/input/extension.bin")
    execute(docker(command, mounts), directory / "simulator.log", allowed=(0, 1, 2) if expected_status or firmware else (0, 2) if probe else (0,))
    if not result_path.exists() or result_path.stat().st_size == 0:
        raise RuntimeError(f"simulator did not produce a result: {name}")
    result = json.loads(result_path.read_text())
    manifest_path = binary.parent / "ngage-build-manifest.json"
    if not manifest_path.exists():
        raise RuntimeError("simulator build provenance is missing")
    manifest = json.loads(manifest_path.read_text())
    if manifest["binary_sha256"] != digest(binary):
        raise RuntimeError("simulator binary differs from recorded provenance")
    result["simulator_build"] = manifest
    result.update(name=name, latency=latency, rom_sha256=digest(rom),
                  rom_extension_sha256=digest(rom_extension) if rom_extension else None,
                  board_model_sources=board_sources)
    result_path.write_text(json.dumps(result, indent=2) + "\n")
    if expected_status and result["status"] != expected_status:
        raise RuntimeError(f"expected {expected_status}, got {result['status']}: {name}")
    if name.startswith("prefetch_fault") and not result.get("fetch_bus_faults"):
        raise RuntimeError("prefetch diagnostic did not exercise bus errors")
    outcome = "PASS expected " + expected_status if expected_status else result['status'].upper()
    print(f"{outcome} {name}: {result['cycles']} cycles", flush=True)
    return result


def profile_unit_tests():
    log = BUILD / "boot-profile-tests.log"
    execute(docker(["g++", "-std=c++17", "-Wall", "-Wextra", "-Werror",
                    "sim/boot_profile.cpp", "sim/test_boot_profile.cpp",
                    "-o", "build/sim/test_boot_profile"]), BUILD / "boot-profile-build.log")
    execute(docker(["/work/build/sim/test_boot_profile"]), log)
    print(log.read_text().split("\n", 1)[1].rstrip(), flush=True)
    return {"status": "pass", "profiles": ["intel8", "amd8", "amd16"], "malformed_table_rejected": True, "missing_payload_rejected": True}


def rtl_lint(info, variant):
    rtl, _ = prepare_zap(info, variant)
    command = ["verilator", "--lint-only", "-DSYNTHESIS", "-Wno-fatal", "-Wno-lint",
               "--top-module", "ngage_cpu", "-I" + str(rtl.relative_to(ROOT)), "rtl/ngage_cpu.sv"]
    command += [str(p.relative_to(ROOT)) for p in sorted(rtl.glob("*.sv"))]
    execute(docker(command), BUILD / "rtl-synthesis-path-lint.log")
    info.update(status="pass", method="verilator-lint-only", synthesis_macro=True, quartus_used=False)
    (BUILD / "rtl-lint-results.json").write_text(json.dumps(info, indent=2) + "\n")
    print("PASS shared RTL syntax with SYNTHESIS defined (ARM64 Verilator only)", flush=True)


def upstream(info, variant):
    work, _ = prepare_zap(info, variant, ROOT / "build" / f"upstream-{variant}")
    results = []
    for name in ("mode32_test", "mode16_test_onlycore"):
        print(f"Running upstream {name}...", flush=True)
        execute(["make", f"TC={name}", "dirs", f"obj/ts/{name}/{name}.bin"],
                BUILD / f"upstream-{name}-assemble.log", cwd=work)
        # Upstream binaries are built on the host; HDL/C++ compilation runs in the image.
        command = ["make", "-C", str(work.relative_to(ROOT)), "runsim", f"TC={name}", "SEED=1", "HT=1"]
        log = BUILD / f"upstream-{name}.log"
        execute(docker(command), log)
        if "Simulation passed!" not in log.read_text(errors="replace"):
            raise RuntimeError(f"upstream simulator did not report success: {name}")
        # The upstream bench always enables a large VCD. Keep failed-run waves;
        # passing runs are reproducible from the recorded seed and text logs.
        (work / "obj" / "ts" / name / "zap.vcd").unlink(missing_ok=True)
        print(f"PASS upstream {name}", flush=True)
        results.append({"name": name, "status": "pass", "seed": 1})
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", action="store_true")
    parser.add_argument("--rtl-lint", action="store_true")
    parser.add_argument("--cpu-variant", choices=("ngage", "upstream"), default="ngage",
                        help="use the local ARM920T fixes, or reproduce the unmodified CPU gaps")
    parser.add_argument("--require-compatible", action="store_true")
    parser.add_argument("--firmware", help="trace this ROM using an experimental reset alias")
    parser.add_argument("--boot-profile", choices=("none", "intel8", "amd8", "amd16"), default="none",
                        help="opt-in provisional physical model for N-Gage 4.03")
    parser.add_argument("--ideal-clocks", action="store_true",
                        help="explicit experiment: clock status acknowledges the observed startup commands immediately")
    parser.add_argument("--lcd-probe", action="store_true",
                        help="explicit LCD experiment: three zero-reset halfwords and an immediate transport sink")
    parser.add_argument("--compact-trace", action="store_true",help="record device I/O and faults, omitting ordinary memory and instruction logs")
    parser.add_argument("--boot-io-probe",action="store_true",help="opt-in exact cold-boot GPIO/reset and control-bus hypotheses")
    parser.add_argument("--rom-extension",type=Path,nargs="?",const=DEFAULT_EXTENSION,help="load a separately reconstructed NEM-4 tail with its manifest")
    parser.add_argument("--max-cycles", type=int)
    parser.add_argument("--latency", type=int, default=0)
    parser.add_argument("--timer-irq-delay",type=int,default=0,metavar="CYCLES",help="opt-in assumed CPU cycles from timer reload to IRQ")
    parser.add_argument("--digest-probe",choices=("core","both"),help="explicit non-authentic digest-metadata probe on a derived image")
    parser.add_argument("--uem-adc",action="append",default=[],metavar="CHANNEL=VALUE",help="explicit assumed 10-bit UEM ADC input; repeat for other channels")
    args = parser.parse_args()
    try:
        args.adc_inputs = parse_inputs(args.uem_adc)
    except ValueError as error:
        parser.error(str(error))
    if args.timer_irq_delay and (not args.boot_io_probe or not 1 <= args.timer_irq_delay <= 1000000000):
        parser.error("--timer-irq-delay requires --boot-io-probe and 1..1000000000 cycles")
    if args.digest_probe and not (args.boot_io_probe and args.rom_extension):
        parser.error("--digest-probe requires --boot-io-probe and --rom-extension")
    if args.adc_inputs and not args.boot_io_probe:
        parser.error("--uem-adc requires --boot-io-probe")
    if args.boot_profile != "none" and args.firmware is None:
        parser.error("--boot-profile requires --firmware")
    if args.ideal_clocks and args.boot_profile == "none":
        parser.error("--ideal-clocks requires an exploratory --boot-profile")
    if args.compact_trace and args.boot_profile == "none":
        parser.error("--compact-trace requires an exploratory --boot-profile")
    if args.lcd_probe and not args.ideal_clocks:
        parser.error("--lcd-probe requires --ideal-clocks and an exploratory --boot-profile")
    if args.boot_io_probe and not args.rom_extension:
        parser.error("--boot-io-probe requires --rom-extension")
    if args.rom_extension and (args.boot_profile != "amd16" or not args.lcd_probe):
        parser.error("--rom-extension requires the amd16 ideal-clock/LCD experiment")
    BUILD.mkdir(parents=True, exist_ok=True)
    info = environment()
    if args.upstream:
        info["upstream_tests"] = upstream(info, args.cpu_variant)
        (BUILD / f"upstream-{args.cpu_variant}-results.json").write_text(json.dumps(info, indent=2) + "\n")
        return 0
    if args.rtl_lint:
        rtl_lint(info, args.cpu_variant)
        return 0
    binary = build_simulator(info, args.cpu_variant)
    if args.firmware is not None:
        firmware = Path(args.firmware).expanduser().resolve() if args.firmware else ROOT / "firmware" / "SYM.ROM"
        if not firmware.is_file():
            raise RuntimeError(f"firmware file not found: {firmware}")
        profile = args.boot_profile
        if profile != "none" and digest(firmware) != "afc1cc8b693f2b68d23ca203aa4d4eb4266baad4ab718f013a33b915d39574ef":
            raise RuntimeError("the provisional bank-table profile only supports the inspected N-Gage 4.03 ROM")
        if args.rom_extension:
            args.rom_extension = args.rom_extension.resolve()
            info["rom_extension"] = validate_extension(firmware,args.rom_extension)
        digest_manifest = None
        if args.digest_probe:
            firmware,digest_manifest = build_digest_probe(firmware,args.rom_extension,args.digest_probe)
            info["digest_probe"] = digest_manifest
            print("EXPERIMENT: derived ROM replaces digest metadata only; original input is unchanged and authenticity is unverified.", flush=True)
        case = "firmware" if profile == "none" and args.latency == 0 else f"firmware-{profile}-latency{args.latency}"
        if args.ideal_clocks:
            case += "-ideal-clocks"
            print("ASSUMPTION: observed clock handshake completes immediately; all other status combinations remain unknown.", flush=True)
        if args.lcd_probe:
            case += "-lcd-probe"
            print("ASSUMPTION: exact LCD setup halfwords reset to zero; observed transport accepts data immediately.", flush=True)
        if args.rom_extension:
            case += "-extension"
            print("RECONSTRUCTION: preserved ROOT payload, synthesized extension metadata, explicit erased padding.", flush=True)
        if args.boot_io_probe:
            case += "-boot-io"
            print("ASSUMPTION: narrow cold-boot GPIO/reset values and immediate completion on the bounded control-bus transport.", flush=True)
        if args.adc_inputs:
            case += case_suffix(args.adc_inputs)
            print("ASSUMPTION: explicit UEM ADC inputs " + encode_inputs(args.adc_inputs) + "; not measured on hardware.", flush=True)
        if args.digest_probe:
            case += "-digest-"+args.digest_probe
        if args.timer_irq_delay:
            case += "-timer-irq-"+str(args.timer_irq_delay)
            print(f"ASSUMPTION: timer IRQ after {args.timer_irq_delay} CPU cycles; timing and acknowledge semantics are unverified.", flush=True)
        if profile == "none":
            print("Experimental firmware trace: ROM is aliased at 0 and 0x50000000; Nokia's reset mapping is unverified.", flush=True)
        else:
            print(f"PROVISIONAL boot profile {profile}: observed startup latches, hypothesized flash ID and physical bank map.", flush=True)
        limit = args.max_cycles or (2000000 if profile != "none" else 100000)
        result = run_case(binary, case, firmware, firmware=True, limit=limit,
                          latency=args.latency, boot_profile=profile, ideal_clocks=args.ideal_clocks, lcd_probe=args.lcd_probe, compact_trace=args.compact_trace, rom_extension=args.rom_extension, boot_io_probe=args.boot_io_probe, adc_inputs=args.adc_inputs, timer_irq_delay=args.timer_irq_delay)
        if digest_manifest:
            if result['rom_sha256'] != digest_manifest['derived_sha256']:
                raise RuntimeError('derived digest-probe ROM changed during simulation')
            result.update(original_rom_sha256=digest_manifest["source_core_sha256"],digest_probe=digest_manifest)
            result_path = BUILD/"runs"/result["name"]/"result.json"
            result_path.write_text(json.dumps(result,indent=2)+"\n")
        header = firmware.read_bytes()[:0x94]
        info.update(firmware=result, reset_mapping_verified=False)
        if len(header) >= 0x94:
            info["header_rom_base"], info["header_rom_size"] = struct.unpack_from("<II", header, 0x8c)
        (BUILD / f"{result['name']}-results.json").write_text(json.dumps(info, indent=2) + "\n")
        if result["status"] == "unmapped_access":
            print(f"Stopped at first unmodeled address 0x{result['blocked_address']:08x}; see build/sim/runs/{result['name']}/.")
            if result.get("blocked_reason"):
                print(result["blocked_reason"])
        return 0 if result["status"] in ("pass", "unmapped_access", "quiescent_loop") else 1
    info["boot_profile_unit_tests"] = profile_unit_tests()
    results = []
    diagnostics = ["smoke", "mmu_fcse", "prefetch_fault", "ldm_base_in_list", "ldm_base_mmu", "ldm_base_smallpage", "ldm_base_undmode", "ldm_cold_base_not_loaded", "ldm_cold_base_last", "ldm_fault_far", "ldm_fault_status_first", "ldm_fault_status_immediate", "ldm_fault_status_probe", "ldr_fault_status_probe", "ldm_fault_status_delay", "ldm_fault_status_load", "ldm_fault_status_load_far"]
    if args.cpu_variant == "ngage":
        diagnostics += ["alignment_cases", "mmu_fetch", "cache_load_widths"]
    for name in diagnostics:
        rom = assemble(name)
        for latency in (0, 3):
            results.append(run_case(binary, f"{name}-latency{latency}", rom, latency=latency))
    if args.cpu_variant == "ngage":
        flash_return = assemble("flash_return")
        info["flash_return_guards"] = []
        for latency in (0, 3, 7):
            result = run_case(binary, f"flash_return-latency{latency}", flash_return,
                              boot_profile="amd16", expected_status="unmapped_access",
                              latency=latency, limit=10000)
            if result["blocked_address"] != 0x0bad0000:
                raise RuntimeError("flash-return guard failed to reach the expected completion stop")
            info["flash_return_guards"].append(result)
    if args.cpu_variant == "ngage":
        rom = assemble("btb_return")
        info["branch_prediction_guards"] = []
        for latency in (0,3):
            result = run_case(binary,f"btb_return-latency{latency}",rom,latency=latency,
                              boot_profile="amd16",boot_io_probe=True,
                              expected_status="unmapped_access")
            if result["blocked_address"] != 0x0bad0000:
                raise RuntimeError("BTB collision corrupted the cached function return")
            info["branch_prediction_guards"].append(result)
    info["board_fetch_guard"] = run_case(binary, "board_fetch_guard", assemble("board_fetch_guard"),
                                        boot_profile="amd16", expected_status="instruction_abort", limit=5000)
    if info["board_fetch_guard"]["blocked_address"] != 0x90000000:
        raise RuntimeError("board instruction abort stopped at an unexpected address")
    info["firmware_loop_guards"] = []
    for enabled in (False,True):
        name = "firmware_loop_irq_enabled" if enabled else "firmware_loop_masked"
        program = assemble(name,"firmware_loop",("-DIRQ_ENABLED=1",) if enabled else ())
        info["firmware_loop_guards"].append(run_case(binary,name,program,boot_profile="amd16",
             expected_status="quiescent_loop" if enabled else "firmware_loop",limit=1000))
    info["timer_irq_guards"] = []
    for masked in (False, True):
        name = "timer_irq_masked" if masked else "timer_irq_enabled"
        program = assemble(name, "timer_irq", ("-DMASK_IRQ",) if masked else ())
        for latency in (0, 3):
            case = f"{name}-latency{latency}"
            result = run_case(binary, case, program, latency=latency, boot_profile="amd16",
                              boot_io_probe=True, timer_irq_delay=2000, limit=10000,
                              expected_status="quiescent_loop" if masked else "unmapped_access")
            if masked:
                if result["cycles"] >= 2000:
                    raise RuntimeError("masked IRQ prevented quiescent-loop detection")
            else:
                import csv
                if result["blocked_address"] != 0x0bad0000 or result["boot_profile"]["timer_irq_pending"]:
                    raise RuntimeError("timer IRQ did not reach the expected acknowledged terminal write")
                directory = BUILD / "runs" / case
                with (directory / "bus.tsv").open() as stream:
                    rows = list(csv.DictReader(stream, delimiter="\t"))
                def has_write(operation, address, value):
                    return any(row["operation"] == operation and int(row["address"],16) == address and
                               int(row["data"],16) == value for row in rows)
                if not has_write("WRITE",0x0c120a08,1) or not has_write("UNMODELED_WRITE",0x0bad0000,42):
                    raise RuntimeError("timer IRQ acknowledgement or terminal value missing")
                trace = (directory / "instructions.tsv").read_text()
                if "00000018:<" not in trace or not any("0000005c:<" in line and line.rstrip().endswith("00000053") for line in trace.splitlines()):
                    raise RuntimeError("timer IRQ vector entry or restored CPSR missing")
            info["timer_irq_guards"].append(result)
    print("PASS scheduled IRQ, exception return, and masked IRQ guard at both latencies")
    probe = run_case(binary, "alignment_probe", assemble("alignment_probe"))
    words = probe["mailbox"]
    compatible = bool(words[2] & 2) and words[3] == 1 and words[5] == 0x80000001 and (words[4] & 15) == 1
    mmu_probe = run_case(binary, "mmu_cache_disabled_probe",
                         assemble("mmu_cache_disabled_probe", "mmu_fcse", ("-DDISABLE_CACHES",)), probe=True)
    if mmu_probe["status"] == "unmapped_access" and mmu_probe["blocked_address"] != 0x20000000:
        raise RuntimeError("MMU probe stopped at an unexpected unmapped address")
    mmu_compatible = mmu_probe["status"] == "pass"
    gaps = []
    if not compatible:
        gaps.append("ARM920T alignment control and data abort behavior")
    if not mmu_compatible:
        gaps.append("MMU translation when the data cache is disabled")
    info.update(baseline_tests=results, alignment_probe=probe,
                alignment_compatible=compatible,
                mmu_cache_disabled_probe=mmu_probe, mmu_cache_disabled_compatible=mmu_compatible,
                known_gaps=gaps)
    results_path = BUILD / ("results.json" if args.cpu_variant == "ngage" else "results-unmodified.json")
    results_path.write_text(json.dumps(info, indent=2) + "\n")
    print(f"Alignment probe: requested c1=0x{words[1]:08x}, observed c1=0x{words[2]:08x}, data abort={words[3]}.")
    print("PASS ARM920T alignment requirement" if compatible else "GAP ARM920T alignment requirement is not implemented by this ZAP revision.")
    print("PASS MMU translation with caches disabled" if mmu_compatible else
          "GAP MMU access with data cache disabled reached virtual address 0x20000000 on the physical bus.")
    print(f"Results: {results_path}")
    return 1 if args.require_compatible and gaps else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
