#!/usr/bin/env python3
"""Execute Nokia startup with a separate ARM engine and the shared bounded board model."""
import argparse
import csv
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

from inspect_boot import EXPECTED
from rom_extension import DEFAULT as DEFAULT_EXTENSION, validate as validate_extension
from adc_inputs import parse_inputs, encode_inputs, case_suffix
from digest_probe import build as build_digest_probe

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "oracle"
IO_DEVICES = {"flash_command", "flash_identify", "observed_boot_latch", "ideal_clock_status", "ideal_pll_status", "lcd_probe_transport", "reconstructed_flash_tail", "ideal_boot_cbus_status", "boot_cbus_latched_data", "assumed_uem_adc_data", "timer_setup_write"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bridge():
    compiler = shutil.which(os.environ.get("CXX", "clang++")) or shutil.which("g++")
    if not compiler:
        raise RuntimeError("a native C++17 compiler is required for the shared board model")
    sources = [ROOT / "sim" / x for x in ("boot_profile.cpp", "boot_profile.h", "oracle_bridge.cpp")]
    compiler_version = subprocess.check_output([compiler, "--version"], text=True).splitlines()[0]
    provenance = {"compiler": compiler_version, "machine": platform.machine(),
                  "sources": {str(p.relative_to(ROOT)): sha(p) for p in sources}}
    key = json.dumps(provenance, sort_keys=True)
    binary = BUILD / ("libngage_board.dylib" if sys.platform == "darwin" else "libngage_board.so")
    stamp = BUILD / "bridge-key.json"
    if not binary.exists() or not stamp.exists() or stamp.read_text() != key:
        flags = ["-dynamiclib"] if sys.platform == "darwin" else ["-shared"]
        command = [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-fPIC", "-O2", *flags,
                   sources[0], sources[2], "-o", binary]
        with (BUILD / "bridge-build.log").open("w") as log:
            subprocess.run(list(map(str,command)), check=True, stdout=log, stderr=subprocess.STDOUT)
        stamp.write_text(key)
    lib = C.CDLL(str(binary))
    lib.ngage_model_create.argtypes = [C.c_char_p,C.c_char_p,C.c_int,C.c_int,C.c_char_p,C.c_int,C.c_char_p]
    lib.ngage_model_create.restype = C.c_void_p
    lib.ngage_model_destroy.argtypes = [C.c_void_p]
    lib.ngage_model_destroy.restype = None
    lib.ngage_model_access.argtypes = [C.c_void_p,C.c_uint32,C.c_uint8,C.c_int,C.c_uint32,C.POINTER(C.c_uint32)]
    lib.ngage_model_access.restype = C.c_int
    for name in ("ngage_model_device","ngage_model_report"):
        getattr(lib,name).argtypes = [C.c_void_p]
        getattr(lib,name).restype = C.c_char_p
    lib.ngage_model_error.restype = C.c_char_p
    return lib, provenance


def mask(select):
    return sum(255 << (8*i) for i in range(4) if select & (1 << i))


class Oracle:
    def __init__(self, args, library, directory):
        import unicorn as U
        from unicorn import arm_const as A
        self.U, self.A, self.lib = U, A, library
        extension = getattr(args,"rom_extension",None)
        self.board = library.ngage_model_create(os.fsencode(args.firmware),args.profile.encode(),args.ideal_clocks,args.lcd_probe,
                                                 os.fsencode(extension) if extension else None,getattr(args,"boot_io_probe",False),encode_inputs(getattr(args,"adc_inputs",{})).encode())
        if not self.board:
            raise RuntimeError(library.ngage_model_error().decode())
        self.uc = U.Uc(U.UC_ARCH_ARM,U.UC_MODE_ARM)
        self.uc.ctl_set_cpu_model(A.UC_CPU_ARM_TI925T)
        self.uc.reg_write(A.UC_ARM_REG_CPSR,0xd3)
        self.count = 0
        self.pending_mmu_check = False
        self.mmu_reference = getattr(args,"mmu_reference",False)
        self.mmu_active = False
        self.mmu_transitions = []
        self.fetch_translations = {}
        self.fetch_descriptor_words = set()
        self.compact_bus = getattr(args,"compact_bus",False)
        self.fast_requested = getattr(args,"fast_rom_reference",False)
        self.fast_active = False
        self.fast_switch_pending = False
        self.fast_clear_next = False
        self.fast_blocks = {}
        self.fast_known_rom = []
        self.self_branch_pc = None
        self.self_branch_repeats = 0
        self.stop = None
        self.restore = []
        self.io = []
        self.bus = (directory / "bus.tsv").open("w")
        self.instructions = (directory / "instructions.tsv").open("w") if not args.no_instruction_trace else None
        self.bus.write("instruction\tpc\toperation\taddress\tbyte_enable\tdata\tdevice\n")
        if self.instructions:
            self.instructions.write("instruction\tpc\tsize\tencoding\n")
        state = self.report()
        for chip in state["flash_chips"]:
            self.uc.mem_map(chip["address"],0x1000000)
        self.uc.mem_map(state["ram_base"],state["ram_size"])
        self.uc.mem_map(0x08000000,0x1000)
        self.uc.mem_map(0x0c000000,0x200000)
        payload = args.firmware.read_bytes() + (extension.read_bytes() if extension else b"")
        self.payload_bytes = len(payload)
        self.core_bytes = args.firmware.stat().st_size
        for bank in state["rom_banks"]:
            data = payload[bank["file_offset"]:bank["file_offset"]+bank["size"]]
            if data:
                self.uc.mem_write(bank["address"],data)
        self.code_hook = self.uc.hook_add(U.UC_HOOK_CODE,self.code)
        self.memory_hook = self.uc.hook_add(U.UC_HOOK_MEM_READ | U.UC_HOOK_MEM_WRITE,self.memory)
        self.uc.hook_add(U.UC_HOOK_MEM_UNMAPPED,self.unmapped)

    def report(self):
        return json.loads(self.lib.ngage_model_report(self.board))

    def finish(self,status,address,reason,operation="",select=0):
        if self.stop is None:
            self.stop = dict(status=status,blocked_address=address,blocked_reason=reason,
                             operation=operation,byte_enable=select,pc=self.uc.reg_read(self.A.UC_ARM_REG_PC))
        self.uc.emu_stop()

    def access(self,address,select,write,value,fetch=False):
        data = C.c_uint32()
        accepted = self.lib.ngage_model_access(self.board,address,select,write,value,C.byref(data))
        device = self.lib.ngage_model_device(self.board).decode()
        if accepted < 0:
            raise RuntimeError(self.lib.ngage_model_error().decode())
        if not accepted:
            self.finish("unmapped_access",address,self.lib.ngage_model_error().decode(),
                        "fetch" if fetch else "write" if write else "read",select)
            return None
        if not fetch:
            operation = "WRITE" if write else "READ"
            value = (value if write else data.value) & mask(select)
            pc = self.uc.reg_read(self.A.UC_ARM_REG_PC)
            if not self.compact_bus or device in IO_DEVICES:
                self.bus.write(f"{self.count}\t0x{pc:08x}\t{operation}\t0x{address:08x}\t0x{select:x}\t0x{value:08x}\t{device}\n")
            if device in IO_DEVICES:
                self.io.append([operation,address,select,value,device])
        return data.value

    def check_self_branch(self,address,is_self):
        self.self_branch_repeats = self.self_branch_repeats+1 if is_self and address==self.self_branch_pc else int(is_self)
        self.self_branch_pc = address if is_self else None
        if self.self_branch_repeats >= 32:
            masked = self.uc.reg_read(self.A.UC_ARM_REG_CPSR)&0xc0 == 0xc0
            self.finish("firmware_loop" if masked else "quiescent_loop",address,
                        "unconditional self-branch with IRQ/FIQ masked" if masked else
                        "unconditional self-branch with an interrupt unmasked; no modeled asynchronous event source")
            return True
        return False

    def activate_fast_rom(self):
        # Native RAM and C++ RAM began zeroed and every preceding write was
        # mirrored. Future writes remain mirrored; ordinary native RAM reads
        # and immutable array reads need no per-access Python callback.
        state = self.report()
        payload_bytes = self.payload_bytes
        known = [(state["ram_base"],state["ram_base"]+state["ram_size"])]
        for chip in state["flash_chips"]:
            probe = next((bank["address"] for bank in state["rom_banks"]
                          if chip["address"] <= bank["address"] < chip["address"]+0x1000000
                          and bank["file_offset"] < payload_bytes),None)
            if probe is None:
                continue
            data = self.access(probe,15,False,0,fetch=True)
            if data is None:
                return
            if self.lib.ngage_model_device(self.board).decode() != "physical_flash_array":
                self.finish("scope_limit",chip["address"],"fast ROM reference requires array-mode flash")
                return
        for bank in state["rom_banks"]:
            backed = max(0,min(bank["size"],payload_bytes-bank["file_offset"]))
            if not backed:
                continue
            span = (bank["address"],bank["address"]+backed)
            self.fast_known_rom.append(span)
            core_backed = max(0,min(bank["size"],self.core_bytes-bank["file_offset"]))
            if core_backed:
                known.append((bank["address"],bank["address"]+core_backed))
        for at,previous in reversed(self.restore):
            self.uc.mem_write(at,previous)
        self.restore.clear()
        self.uc.hook_del(self.code_hook)
        self.uc.hook_del(self.memory_hook)
        self.uc.hook_add(self.U.UC_HOOK_BLOCK,self.fast_block)
        self.uc.hook_add(self.U.UC_HOOK_MEM_WRITE,self.memory)
        # Keep read checks for every hole/peripheral in the broad native maps.
        # Only proven array backing and synchronized RAM avoid read callbacks.
        windows = [(c["address"],c["address"]+0x1000000) for c in state["flash_chips"]]
        windows += [(state["ram_base"],state["ram_base"]+state["ram_size"]),
                    (0x08000000,0x08001000),(0x0c000000,0x0c200000)]
        for start,end in windows:
            cursor = start
            for lo,hi in sorted(known):
                if hi <= cursor or lo >= end:
                    continue
                if lo > cursor:
                    self.uc.hook_add(self.U.UC_HOOK_MEM_READ,self.memory,begin=cursor,end=min(lo,end)-1)
                cursor = max(cursor,min(hi,end))
            if cursor < end:
                self.uc.hook_add(self.U.UC_HOOK_MEM_READ,self.memory,begin=cursor,end=end-1)
        self.fast_active = True

    def fast_block(self,uc,address,size,_):
        if self.stop:
            return
        try:
            if self.fast_clear_next:
                self.fetch_translations.clear()
                self.fetch_descriptor_words.clear()
                self.fast_blocks.clear()
                self.fast_clear_next = False
            control = uc.cpr_read(15,0,1,0,0,0,False)
            if not control & 1 or not control & 2:
                self.finish("scope_limit",address,"fast ROM reference requires MMU and alignment checks enabled")
                return
            self.mmu_active = True
            physical = self.code_physical_address(address)
            if physical is None:
                return
            immutable = any(lo <= physical and physical+size <= hi for lo,hi in self.fast_known_rom)
            key = (address,physical,size)
            cached = self.fast_blocks.get(key) if immutable else None
            if cached is None:
                encoding = bytearray()
                offset = 0
                while offset < size:
                    at = address+offset
                    pa = self.code_physical_address(at)
                    if pa is None:
                        return
                    count = min(4-(pa&3),size-offset)
                    selected = ((1<<count)-1) << (pa&3)
                    value = self.access(pa&~3,selected,False,0,fetch=True)
                    if value is None:
                        return
                    expected = ((value>>(8*(pa&3)))&((1<<(8*count))-1)).to_bytes(count,"little")
                    if bytes(uc.mem_read(pa,count)) != expected:
                        self.finish("backing_mismatch",at,"native block differs from physical board bytes","fetch",selected)
                        return
                    encoding += expected
                    offset += count
                thumb = bool(uc.reg_read(self.A.UC_ARM_REG_CPSR)&0x20)
                step = 2 if thumb else 4
                cp15 = [] if thumb else [i for i in range(0,len(encoding)-3,4)
                    if (int.from_bytes(encoding[i:i+4],"little")&0x0f100f10)==0x0e000f10]
                if cp15 and cp15 != [size-4]:
                    self.finish("scope_limit",address,"fast ROM reference requires CP15 writes at a block boundary")
                    return
                self_branch = bytes(encoding) == (b"\xfe\xe7" if thumb else b"\xfe\xff\xff\xea")
                cached = (size//step,bool(cp15),self_branch)
                if immutable:
                    self.fast_blocks[key] = cached
            if self.check_self_branch(address,cached[2]):
                return
            self.count += cached[0]
            self.fast_clear_next = cached[1]
        except Exception as error:
            self.finish("oracle_error",address,str(error))

    def code_physical_address(self,address):
        # Unicorn TI925T executes its own MMU and reports physical data hooks,
        # but its code hooks carry the virtual PC. Resolve only that fetch for
        # board validation; this walker does not drive native translation or
        # replace the native CPU's permissions/fault handling.
        if not self.mmu_active:
            return address
        page_key = address >> 10
        if page_key in self.fetch_translations:
            return self.fetch_translations[page_key] | (address & 0x3ff)
        def remember(physical):
            self.fetch_translations[page_key] = physical & ~0x3ff
            return physical
        pid = self.uc.cpr_read(15,0,13,0,0,0,False)
        modified = address | (pid & 0xfe000000) if address < 0x02000000 else address
        table = self.uc.cpr_read(15,0,2,0,0,0,False) & 0xffffc000
        first_address = table | ((modified >> 18) & 0x3ffc)
        self.fetch_descriptor_words.add(first_address)
        first = self.access(first_address,15,False,0,fetch=True)
        if first is None:
            return None
        kind = first & 3
        if kind == 2:
            return remember((first & 0xfff00000) | (modified & 0xfffff))
        if kind == 1:
            at = (first & 0xfffffc00) | ((modified >> 10) & 0x3fc)
        elif kind == 3:
            at = (first & 0xfffff000) | ((modified >> 8) & 0xffc)
        else:
            self.finish("scope_limit",address,"software fetch checker encountered a first-level translation fault")
            return None
        self.fetch_descriptor_words.add(at)
        second = self.access(at,15,False,0,fetch=True)
        if second is None:
            return None
        page = second & 3
        if page == 1:
            return remember((second & 0xffff0000) | (modified & 0xffff))
        if page == 2:
            return remember((second & 0xfffff000) | (modified & 0xfff))
        if page == 3 and kind == 3:
            return remember((second & 0xfffffc00) | (modified & 0x3ff))
        self.finish("scope_limit",address,"software fetch checker encountered an unsupported second-level descriptor")
        return None

    def code(self,uc,address,size,_):
        if self.stop:
            return
        try:
            if self.pending_mmu_check:
                self.pending_mmu_check = False
                control = uc.cpr_read(15,0,1,0,0,0,False)
                self.mmu_active = bool(control & 1)
                self.mmu_transitions.append(dict(pc=address,control=control))
                if self.mmu_active and self.fast_requested:
                    # Restart at this PC with block/read-range hooks installed
                    # outside the active emulation callback.
                    self.fast_switch_pending = True
                    uc.emu_stop()
                    return
                if self.mmu_active and not self.mmu_reference:
                    self.finish("scope_limit",address,"software oracle stops before executing with the ARM MMU enabled")
                    return
            for at,previous in reversed(self.restore):
                uc.mem_write(at,previous)
            self.restore.clear()
            physical = self.code_physical_address(address)
            if physical is None:
                return
            word_address = physical & ~3
            select = ((1 << size)-1) << (address & 3)
            value = self.access(word_address,select,False,0,fetch=True)
            if value is None:
                return
            encoding = bytes(uc.mem_read(physical,size))
            expected = ((value >> (8*(address&3))) & ((1 << (size*8))-1)).to_bytes(size,"little")
            if encoding != expected:
                self.finish("backing_mismatch",address,"native code bytes differ from the board model","fetch",select)
                return
            is_self = encoding == (b"\xfe\xe7" if size==2 else b"\xfe\xff\xff\xea")
            if self.check_self_branch(address,is_self):
                return
            # Cached fetch checks are valid only while their descriptor words
            # and guest CP15 state stay unchanged. Native Unicorn still runs
            # its own MMU/TLB; this only avoids repeated host-side lookups.
            if size == 4 and (int.from_bytes(encoding,"little") & 0x0f100f10) == 0x0e000f10:
                self.fetch_translations.clear()
                self.fetch_descriptor_words.clear()
            self.pending_mmu_check = size == 4 and (int.from_bytes(encoding,"little") & 0x0fff0fff) == 0x0e010f10
            self.count += 1
            if self.instructions:
                self.instructions.write(f"{self.count}\t0x{address:08x}\t{size}\t{encoding.hex()}\n")
        except Exception as error:
            self.finish("oracle_error",address,str(error))

    def memory(self,uc,kind,address,size,value,_):
        if self.stop:
            return
        try:
            write = kind == self.U.UC_MEM_WRITE
            if self.fast_active and write and any(base <= address < base+0x1000000 for base in (0,0x02000000,0x04000000)):
                self.finish("scope_limit",address,"fast ROM reference stops before a flash write or command","write")
                return
            previous = bytes(uc.mem_read(address,size))
            offset = 0
            payload = bytearray()
            while offset < size and not self.stop:
                at = address + offset
                count = min(size-offset,4-(at&3))
                select = ((1 << count)-1) << (at&3)
                part = ((value >> (8*offset)) & ((1 << (8*count))-1)) << (8*(at&3))
                if write and at&~3 in self.fetch_descriptor_words:
                    self.fetch_translations.clear()
                    self.fast_blocks.clear()
                result = self.access(at&~3,select,write,part)
                if result is None:
                    return
                payload += ((result >> (8*(at&3))) & ((1 << (8*count))-1)).to_bytes(count,"little")
                offset += count
            # Native Unicorn memory backs instruction execution. Flash commands
            # and ID reads are temporary overlays, never changes to ROM bytes.
            flash = any(base <= address < base+0x1000000 for base in (0,0x02000000,0x04000000))
            if flash:
                self.restore.append((address,previous))
            if not write and payload != previous:
                uc.mem_write(address,bytes(payload))
        except Exception as error:
            self.finish("oracle_error",address,str(error))

    def unmapped(self,uc,kind,address,size,value,_):
        self.finish("unmapped_access",address,"native software-engine address is outside the configured physical windows")
        return False

    def run(self,limit):
        try:
            start = 0
            while True:
                self.uc.emu_start(start,0xffffffff,count=max(1,limit-self.count))
                if not self.fast_switch_pending:
                    break
                self.fast_switch_pending = False
                self.activate_fast_rom()
                if self.stop:
                    break
                start = self.uc.reg_read(self.A.UC_ARM_REG_PC)
        except self.U.UcError as error:
            if self.stop is None:
                # Unicorn may fault on the first translated fetch before the
                # next code hook. This is the same physical-only scope boundary.
                if not self.mmu_reference and self.pending_mmu_check and self.uc.cpr_read(15,0,1,0,0,0,False) & 1:
                    self.finish("scope_limit",self.uc.reg_read(self.A.UC_ARM_REG_PC),
                                "software oracle stops before executing with the ARM MMU enabled")
                else:
                    self.finish("software_cpu_exception",self.uc.reg_read(self.A.UC_ARM_REG_PC),str(error))
        if self.stop is None:
            self.stop = dict(status="instruction_limit",blocked_address=0,blocked_reason="instruction limit reached",
                             pc=self.uc.reg_read(self.A.UC_ARM_REG_PC))
        self.bus.close()
        if self.instructions:
            self.instructions.close()
        result = dict(self.stop,instructions=self.count,boot_profile=self.report(),
                      cpu_model="Unicorn TI925T (ARMv4T software reference)",unicorn_version=self.U.__version__,
                      scope=("Native MMU; immutable ROM block checks; synchronized RAM; checked MMIO and writes; no hardware timing" if self.fast_active else
                             "MMU-aware native execution; virtual code hooks checked against physical board; shared provisional devices" if self.mmu_reference else
                             "pre-MMU bootstrap; shared provisional device model; no hardware timing"),
                      mmu_reference=self.mmu_reference,mmu_transitions=self.mmu_transitions,compact_bus=self.compact_bus,
                      fast_rom_reference=self.fast_active,
                      instruction_count_kind="basic-block upper bound after MMU" if self.fast_active else "code-hook count")
        result["registers"] = {name:self.uc.reg_read(getattr(self.A,"UC_ARM_REG_"+name.upper()))
                               for name in [*[f"r{i}" for i in range(13)],"sp","lr","pc","cpsr"]}
        result["cp15_control"] = self.uc.cpr_read(15,0,1,0,0,0,False)
        self.lib.ngage_model_destroy(self.board)
        self.board = None
        return result


def compare(path,events,frontier):
    metadata = json.loads(path.with_name("result.json").read_text())
    if metadata.get("rom_sha256") != frontier["rom_sha256"]:
        raise RuntimeError("HDL comparison firmware hash differs or is missing; rerun the HDL trace")
    expected_sources = {key:value for key,value in frontier["bridge"]["sources"].items() if key in ("sim/boot_profile.cpp", "sim/boot_profile.h")}
    if metadata.get("board_model_sources") != expected_sources:
        raise RuntimeError("HDL comparison used a different or unrecorded board-model version; rerun the HDL trace")
    if metadata.get("digest_probe") != frontier.get("digest_probe"):
        raise RuntimeError("HDL comparison used a different digest-metadata probe")
    if metadata.get("rom_extension_sha256") != frontier.get("rom_extension_sha256"):
        raise RuntimeError("HDL comparison used different reconstructed ROM bytes")
    for setting in ("name", "ideal_clocks", "lcd_probe", "boot_io_probe"):
        if metadata["boot_profile"].get(setting,False) != frontier["boot_profile"].get(setting,False):
            raise RuntimeError(f"HDL comparison board setting differs: {setting}")
    if metadata["boot_profile"].get("timer_irq_delay", 0) != frontier["boot_profile"].get("timer_irq_delay", 0):
        raise RuntimeError("HDL comparison timer IRQ assumptions differ")
    if metadata["boot_profile"].get("uem_adc_inputs",[]) != frontier["boot_profile"].get("uem_adc_inputs",[]):
        raise RuntimeError("HDL comparison ADC input assumptions differ")
    boundary = None
    if frontier.get("status") == "scope_limit" and frontier.get("cp15_control",0)&1 and not frontier.get("mmu_reference",False):
        with path.with_name("cp15.tsv").open() as stream:
            for row in csv.DictReader(stream,delimiter="\t"):
                if row["operation"] == "MCR" and int(row["crn"]) == 1 and int(row["value"],16)&1:
                    boundary = dict(cycle=int(row["cycle"]),value=int(row["value"],16))
                    break
        if boundary is None:
            raise RuntimeError("HDL trace has no recorded MMU enable boundary")
    reference = []
    last = None
    with path.open() as stream:
        for row in csv.DictReader(stream,delimiter="\t"):
            if boundary is not None and int(row["cycle"]) > boundary["cycle"]:
                continue
            if row["operation"].startswith("UNMODELED"):
                last = [row["operation"],int(row["address"],16),int(row["byte_enable"],16)]
            if row.get("channel") == "code" or row.get("device") not in IO_DEVICES or row["operation"] not in ("READ","WRITE"):
                continue
            select = int(row["byte_enable"],16)
            reference.append([row["operation"],int(row["address"],16),select,
                              int(row["data"],16)&mask(select),row["device"]])
    mismatch = next((i for i,(a,b) in enumerate(zip(reference,events)) if a != b),None)
    same = mismatch is None and len(reference)==len(events)
    expected_frontier = ["UNMODELED_"+frontier.get("operation","").upper(),frontier["blocked_address"],frontier.get("byte_enable",0)]
    loop_at_limit = False
    loop_matches = None
    if frontier.get("status") == "quiescent_loop":
        loop_matches = metadata.get("status") == "quiescent_loop" and metadata.get("blocked_address") == frontier["blocked_address"]
        if metadata.get("status") == "timeout":
            with path.with_name("instructions.tsv").open() as stream:
                tail = list(csv.DictReader(stream,delimiter="\t"))[-32:]
            expected_pc = f"{frontier['blocked_address']:08x}"
            loop_at_limit = len(tail)==32 and all(
                row["retired_instruction"].startswith(expected_pc+":") and "BAL -2>" in row["retired_instruction"]
                and int(row["retired_instruction"][-8:],16)&0xc0 == frontier["registers"]["cpsr"]&0xc0 for row in tail)
            loop_at_limit &= bool(tail) and metadata["cycles"]-int(tail[-1]["cycle"]) < 1000
            loop_matches = bool(loop_at_limit)
    return dict(reference=str(path),io_events_match=same,reference_io_events=len(reference),oracle_io_events=len(events),
                first_difference=None if same else dict(index=mismatch if mismatch is not None else min(len(reference),len(events)),
                    reference=reference[mismatch] if mismatch is not None else None,
                    oracle=events[mismatch] if mismatch is not None else None),
                frontier_matches=(loop_matches if loop_matches is not None else boundary["value"]==frontier["cp15_control"] if boundary else last==expected_frontier),
                comparison_scope=("through quiescent self-branch at HDL cycle limit" if loop_at_limit else
                                  "through quiescent self-branch" if loop_matches is not None else
                                  "pre-MMU prefix" if boundary else "through first unknown access"),
                mmu_enable_boundary=boundary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--firmware",type=Path,default=Path(os.environ.get("FIRMWARE") or ROOT/"firmware"/"SYM.ROM"))
    parser.add_argument("--profile",choices=("intel8","amd8","amd16"),default=os.environ.get("BOOT_PROFILE") or "amd16")
    parser.add_argument("--ideal-clocks",action="store_true")
    parser.add_argument("--lcd-probe",action="store_true")
    parser.add_argument("--boot-io-probe",action="store_true",help="explicit cold-boot GPIO/reset/scratch and two immediate control-bus transactions")
    parser.add_argument("--rom-extension",type=Path,nargs="?",const=DEFAULT_EXTENSION,help="use a separately reconstructed ROM tail and its manifest")
    parser.add_argument("--fast-rom-reference",action="store_true",help="opt-in immutable-ROM block checks after MMU; original native CPU execution, restricted read fast path")
    parser.add_argument("--compact-bus",action="store_true",help="omit ordinary RAM/ROM data logging; all accesses remain checked")
    parser.add_argument("--mmu-reference",action="store_true",help="opt-in native MMU execution with physical code-fetch validation; default stops at MMU enable")
    parser.add_argument("--no-instruction-trace",action="store_true",help="omit the large per-instruction log; all memory accesses are still checked")
    parser.add_argument("--max-instructions",type=int,default=500000)
    parser.add_argument("--compare",type=Path,action="append",default=[],help="compare modeled I/O and the frontier against this HDL bus.tsv; repeat for several runs")
    parser.add_argument("--digest-probe",choices=("core","both"),help="explicit non-authentic digest-metadata probe on a derived image")
    parser.add_argument("--uem-adc",action="append",default=[],metavar="CHANNEL=VALUE",help="explicit assumed 10-bit UEM ADC input; repeat for other channels")
    args = parser.parse_args()
    try:
        args.adc_inputs = parse_inputs(args.uem_adc)
    except ValueError as error:
        parser.error(str(error))
    if args.digest_probe and not (args.boot_io_probe and args.rom_extension):
        parser.error("--digest-probe requires --boot-io-probe and --rom-extension")
    if args.adc_inputs and not args.boot_io_probe:
        parser.error("--uem-adc requires --boot-io-probe")
    if args.fast_rom_reference and not (args.mmu_reference and args.compact_bus and args.no_instruction_trace):
        parser.error("--fast-rom-reference requires --mmu-reference --compact-bus --no-instruction-trace")
    args.firmware = args.firmware.expanduser().resolve()
    if sha(args.firmware) != EXPECTED:
        raise RuntimeError("the software oracle only supports the inspected N-Gage 4.03 firmware")
    if args.max_instructions < 1:
        parser.error("--max-instructions must be positive")
    if args.lcd_probe and not args.ideal_clocks:
        parser.error("--lcd-probe requires --ideal-clocks")
    if args.boot_io_probe and not args.rom_extension:
        parser.error("--boot-io-probe requires --rom-extension")
    extension_manifest = None
    if args.rom_extension:
        args.rom_extension = args.rom_extension.resolve()
        if args.profile != "amd16" or not args.lcd_probe:
            parser.error("--rom-extension requires the amd16 ideal-clock/LCD experiment")
        extension_manifest = validate_extension(args.firmware,args.rom_extension)
    digest_manifest = None
    if args.digest_probe:
        args.firmware,digest_manifest = build_digest_probe(args.firmware,args.rom_extension,args.digest_probe)
        print("EXPERIMENT: derived ROM replaces digest metadata only; original input is unchanged and authenticity is unverified.")
    BUILD.mkdir(parents=True,exist_ok=True)
    lib,provenance = bridge()
    name = args.profile + ("-ideal-clocks" if args.ideal_clocks else "") + ("-lcd-probe" if args.lcd_probe else "") + ("-extension" if args.rom_extension else "") + ("-boot-io" if args.boot_io_probe else "") + case_suffix(args.adc_inputs) + ("-digest-"+args.digest_probe if args.digest_probe else "") + ("-mmu" if args.mmu_reference else "") + ("-fast" if args.fast_rom_reference else "")
    directory = BUILD/name
    directory.mkdir(parents=True,exist_ok=True)
    result_path = directory/"result.json"
    result_path.unlink(missing_ok=True)
    if args.no_instruction_trace:
        (directory/"instructions.tsv").unlink(missing_ok=True)
    oracle = Oracle(args,lib,directory)
    result = oracle.run(args.max_instructions)
    result.update(rom_sha256=sha(args.firmware),bridge=provenance,oracle_source_sha256=sha(Path(__file__)))
    result.update(rom_extension_sha256=sha(args.rom_extension) if args.rom_extension else None,
                  rom_extension=extension_manifest)
    if digest_manifest:
        if result['rom_sha256'] != digest_manifest['derived_sha256']:
            raise RuntimeError('derived digest-probe ROM changed during simulation')
        result.update(original_rom_sha256=digest_manifest["source_core_sha256"],digest_probe=digest_manifest)
    if args.compare:
        result["comparisons"] = [compare(path,oracle.io,result) for path in args.compare]
    result_path.write_text(json.dumps(result,indent=2)+"\n")
    count_label = "software instruction upper bound" if result.get("fast_rom_reference") else "software ARM instructions"
    print(f"{result['status'].upper()}: {result['instructions']} {count_label}; address 0x{result['blocked_address']:08x}")
    print(result["blocked_reason"])
    if args.compare:
        print(json.dumps(result["comparisons"],indent=2))
    print(f"Report: {result_path}")
    comparison_ok = all(item["io_events_match"] and item["frontier_matches"] for item in result.get("comparisons",[]))
    return 0 if result["status"] in ("unmapped_access","scope_limit","quiescent_loop") and comparison_ok else 1


if __name__=="__main__":
    try:
        raise SystemExit(main())
    except (OSError,ValueError,RuntimeError,subprocess.CalledProcessError,ImportError) as error:
        raise SystemExit(str(error))
