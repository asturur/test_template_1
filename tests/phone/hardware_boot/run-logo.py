#!/usr/bin/env python3
"""Resumable actual-HDL phone boot with explicitly modeled backing memories."""
import argparse, glob, gzip, hashlib, json, shutil, subprocess, struct, zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
# Screenshot extraction is a separate, zero-clock reader of a completed pair.
# It links against that run's exact cached HDL, including frozen continuations.
import sys
sys.path.insert(0,str(ROOT/'tools'))
from capture_sim_checkpoint import capture as capture_checkpoint
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def png(ppm, dest):
    data=ppm.read_bytes(); head,wh,maxval,raw=data.split(b'\n',3);w,h=map(int,wh.split())
    assert head==b'P6' and maxval==b'255' and len(raw)==w*h*3
    def chunk(k,v):return struct.pack('>I',len(v))+k+v+struct.pack('>I',zlib.crc32(k+v)&0xffffffff)
    scan=b''.join(b'\0'+raw[y*w*3:(y+1)*w*3] for y in range(h))
    dest.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(scan))+chunk(b'IEND',b''))
def run_model(cmd,out):
    # Preserve the entire console losslessly, with bounded live diagnostics.
    head=bytearray();tail=bytearray();pending=b'';total=0;cap=256*1024
    interesting=(b'PROGRESS ',b'REACHED ',b'CHECKPOINT ',b'KEY_',b'BAD_POINTER ',b'FAULT_RF ',b'MEM_HISTORY ',b'R0_HISTORY ',b'BUS_FAULT ',b'LCD ',b'LCD_UNKNOWN ',b'ERROR ',b'FAIL ',b'PASS ',b'%Error',b'FATAL')
    with gzip.open(out/'run.log.gz','wb',compresslevel=1) as archive,(out/'run.log').open('w+b') as live,(out/'progress.log').open('wb') as progress:
        process=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        while chunk:=process.stdout.read1(65536):
            archive.write(chunk);total+=len(chunk)
            take=min(cap-len(head),len(chunk));head.extend(chunk[:take]);tail.extend(chunk[take:])
            if len(tail)>cap:del tail[:-cap]
            lines=(pending+chunk).split(b'\n');pending=lines.pop()
            for line in lines:
                if line.startswith(interesting):progress.write(line+b'\n')
                if line.startswith(b'CHECKPOINT ') and b' prefix=' in line:
                    prefix=Path(line.split(b' prefix=',1)[1].decode())
                    try:
                        capture_checkpoint(prefix)
                    except Exception as error:
                        # An observation failure must not terminate a phone run.
                        print(f'Screenshot failed for {prefix}: {error}',file=sys.stderr,flush=True)
            progress.flush()
            live.seek(0);live.write(head)
            omitted=total-len(head)-len(tail)
            if omitted:live.write(('\n[Live log omitted '+str(omitted)+' bytes; complete console in run.log.gz]\n').encode())
            live.write(tail);live.truncate();live.flush()
        if pending and pending.startswith(interesting):progress.write(pending+b'\n')
        result=process.wait()
        if result:raise subprocess.CalledProcessError(result,cmd)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--name',required=True);p.add_argument('--cycles',type=int,required=True)
    p.add_argument('--use-saved-build',action='store_true',help='resume the exact checkpoint executable, ignoring current workspace HDL; never applies new fixes')
    p.add_argument('--powerup',choices=('normal','alarm'),default='normal',help='reset cause; legacy checkpoints require alarm')
    p.add_argument('--restore',type=Path);p.add_argument('--pretest-fixes-fork',action='store_true',help='reviewed pre-self-test fork for NOS IRQ mask, routed GENIO1 and observer upgrade');p.add_argument('--driver-upgrade',action='store_true',help='resume identical HDL/host state layout across the reviewed 64-bit observer counter upgrade');p.add_argument('--diagnostic-irq-fork',action='store_true',help='diagnostic-only fork across the reviewed NOS IRQ-mask fix, with identical serialized layout');p.add_argument('--build-only',action='store_true')
    overlays=p.add_mutually_exclusive_group()
    overlays.add_argument('--bluetooth-overlay',type=Path,help='separate cold-run lineage: stage Bluetooth_Compatibility.ngo with real component-ID2 loader')
    p.add_argument('--stop-on-kernel-panic',action='store_true',help='stop/save after the known NEM-4 terminal panic fetch loop is stable')
    p.add_argument('--stop-after-lcd-words',type=int,default=0,help='bounded display diagnostic: stop after this many observed LCD data writes plus queue drain')
    overlays.add_argument('--nos-overlay',type=Path,help='separate cold-run lineage: stage NOS_Compatibility.ngo through real overlay loader before CPU release')
    p.add_argument('--cpu-reference-dir',type=Path,help='diagnostic cold run using matching-interface reference CPU sources by basename')
    p.add_argument('--build-jobs',type=int,default=4)
    p.add_argument('--checkpoint-before',type=int,default=1000000000,help='checkpoint period through switch cycle')
    p.add_argument('--checkpoint-after',type=int,default=100000000,help='checkpoint period after switch cycle')
    p.add_argument('--checkpoint-switch',type=int,default=10000000000,help='absolute cycle where checkpoint cadence changes')
    p.add_argument('--rom-cache-bits',type=int,choices=(64,128,256),default=64)
    p.add_argument('--rom-cache-bytes',type=int,choices=(1024,2048,4096),default=1024)
    p.add_argument('--timer-clock',choices=('cpu','26mhz'),default='cpu',help='counter clock; 26mhz is a separate experiment lineage')
    p.add_argument('--nos-tick-hz',type=int,choices=(1000,64),default=1000,help='NOS counter frequency, not a forced IRQ frequency')
    p.add_argument('--legacy-sdram-route',action='store_true',help='A/B baseline: keep SDRAM behind peripheral bridge')
    p.add_argument('--rom-cache',action='store_true',help='enable production 1KiB DDR ROM cache')
    p.add_argument('--refill-stats',action='store_true',help='passive per-segment refill, stall and memory-traffic counters')
    p.add_argument('--line-refill',action='store_true',help='32-byte refill transport; requires a matching cold build or audited diagnostic fork')
    p.add_argument('--production-ddr',action='store_true',help='Template D1 streaming/D2 8KiB cache/D3 engine; no HPS sector requests')
    p.add_argument('--fault-context',action='store_true',help='passively capture caller/register/memory history and stop on first Count abort; new lineage')
    p.add_argument('--key-at',type=int,default=0,help='single diagnostic key pulse start in CPU clocks')
    p.add_argument('--key-mask',type=lambda x:int(x,0),default=0,help='public phone key bits for diagnostic pulse')
    p.add_argument('--key-hold',type=int,default=0,help='diagnostic key hold in CPU clocks')
    p.add_argument('--early-boot-trace',action='store_true',help='bounded delay/caller observer for independent short investigations')
    p.add_argument('--sys-clk-hz',type=int,default=104000000,help='phone clock/timebase parameter; requires a new checkpoint lineage when changed')
    p.add_argument('--core',type=Path,default=Path('build/firmware/nem4-factory/core.bin'));p.add_argument('--extension',type=Path,default=Path('build/firmware/nem4-factory/extension.bin'));p.add_argument('--cdrive',type=Path,default=Path('scratch/overnight/cdrive-11b.img'))
    a=p.parse_args();assert Path.cwd()==ROOT and 0<a.cycles<2**63 and '/' not in a.name and a.name not in ('.','..')
    if not (0<a.checkpoint_before<2**63 and 0<a.checkpoint_after<2**63 and 0<=a.checkpoint_switch<2**63):
        p.error('checkpoint periods must be positive 64-bit cycle counts; switch must be nonnegative')
    overlay_path=a.bluetooth_overlay or a.nos_overlay
    overlay_id=2 if a.bluetooth_overlay else 1
    overlay_key='bluetooth_overlay' if a.bluetooth_overlay else 'nos_overlay'
    # Keep exactly the bounded harness's HDL sources; no software peripherals.
    script=Path('tests/phone/hardware_boot/run.sh').read_text();source_text=script.split('--Mdir build/sim/unit-hardware-boot/obj ',1)[1].split(' > build/',1)[0]
    sources=[f for token in source_text.split() for f in sorted(glob.glob(token))]
    sources+=['rtl/ngage_ddr_rom_cache.v','rtl/jtframe/ngage_jtframe_romrq_lcache.v','tests/phone/hardware_boot/key_input.v']
    if a.production_ddr:sources+=['rtl/ngage_ddr_flash_adapter.v','rtl/ngage_ddr_flash_cache.v']
    if overlay_path:sources+=['rtl/ngage_nos_overlay.v']
    if a.cpu_reference_dir:
        if a.restore:p.error('CPU reference selection requires a cold run')
        sources=[str(a.cpu_reference_dir/Path(f).name) if f.startswith('rtl/arm/') and (a.cpu_reference_dir/Path(f).name).is_file() else f for f in sources]
    assert sources and 'tests/phone/hardware_boot/tb.v' in sources
    cpp='tests/phone/hardware_boot/logo_main.cpp'
    headers=sorted(str(f) for f in Path('rtl').rglob('*') if f.suffix in ('.vh','.svh'))+['tests/phone/hardware_boot/fault_context_watch.vh']
    assets=['rtl/ngage_debug_font.hex','rtl/ngage_debug_font.mif']
    hashes={f:sha(f) for f in sources+headers+assets+[cpp,__file__]}
    saved=None
    if a.use_saved_build:
        if not a.restore or a.diagnostic_irq_fork or a.pretest_fixes_fork:
            raise ValueError('--use-saved-build requires --restore and forbids model upgrades')
        saved=json.loads((a.restore.parent/'manifest.json').read_text())
        if (a.stop_after_lcd_words or a.stop_on_kernel_panic) and not a.driver_upgrade and saved['sources'][cpp]!=sha(cpp):
            raise ValueError('frozen observer lacks diagnostic stop controls; use the reviewed driver upgrade')
        hashes=dict(saved['sources'])
        if a.driver_upgrade:
            hashes[cpp]=sha(cpp)
            hashes[__file__]=sha(__file__)
    overlay_sha=sha(overlay_path) if overlay_path else None
    if overlay_path:
        import sys
        sys.path.insert(0,str(ROOT/'tools'))
        import nos_overlay
        nos_overlay.inspect(overlay_path.read_bytes(),overlay_id=overlay_id)
    identity_fields={'sources':hashes,'powerup':a.powerup,'direct_sdram':not a.legacy_sdram_route}
    if overlay_sha:identity_fields[overlay_key+'_sha256']=overlay_sha
    if a.sys_clk_hz!=104000000:identity_fields['sys_clk_hz']=a.sys_clk_hz
    if a.timer_clock!='cpu':identity_fields['timer_clock']=a.timer_clock
    if a.nos_tick_hz!=1000:identity_fields['nos_tick_hz']=a.nos_tick_hz
    if a.timer_clock=='26mhz' and a.sys_clk_hz not in (78000000,104000000):raise ValueError('26MHz timers require 78/104MHz CPU')
    if a.refill_stats:identity_fields['refill_stats']=True
    if a.line_refill:identity_fields['line_refill']=True
    if a.early_boot_trace:identity_fields['early_boot_trace']=True
    if a.key_mask and (not a.fault_context or a.key_at<0 or a.key_hold<=0 or a.key_mask>=1<<27):
        raise ValueError('key pulse requires fault-context, valid 27-bit mask and positive hold')
    if a.production_ddr:identity_fields['production_ddr']=True
    if a.fault_context:identity_fields.update(fault_context=True,key_pulse=[a.key_at,a.key_mask,a.key_hold])
    if a.rom_cache:
        identity_fields.update(rom_cache=True,rom_cache_bits=a.rom_cache_bits,rom_cache_bytes=a.rom_cache_bytes)
    identity=hashlib.sha256(json.dumps(identity_fields,sort_keys=True).encode()).hexdigest()
    if saved is not None and not a.driver_upgrade:identity=saved['source_identity']
    build=Path('build/sim/logo-build')/identity[:16];build.mkdir(parents=True,exist_ok=True)
    image='jotego/simulator:arm64';docker=['docker','run','--rm','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint']
    image_id=subprocess.check_output(['docker','image','inspect',image,'--format','{{.Id}}'],text=True).strip()
    binary=build/'Vtb'
    if saved is not None:
        saved_build=Path('build/sim/logo-build')/saved['source_identity'][:16]
        saved_binary=saved_build/'Vtb'
        if not saved_binary.is_file() or sha(saved_binary)!=saved['binary_sha256'] or image_id!=saved['image']:
            raise ValueError('saved executable/container missing or changed; cannot use frozen build')
        if saved.get('powerup','alarm')!=a.powerup:
            raise ValueError('reset cause differs; restart from reset')
    if not binary.exists() and saved is not None and a.driver_upgrade:
        # Reuse the exact frozen HDL archive; current workspace RTL may differ.
        # Copy only generated headers/serialization sources for schema validation.
        for name in ('Vtb__ALL.a','verilated.o','verilated_save.o','verilated_threads.o'):
            if not (build/name).exists():shutil.copyfile(saved_build/name,build/name)
        for source in saved_build.iterdir():
            if source.suffix in ('.h','.cpp') and not (build/source.name).exists():
                shutil.copyfile(source,build/source.name)
        include='/usr/local/verilator/share/verilator/include'
        cmd=docker+['g++',image,'-O3',*(['-DNGAGE_REFILL_STATS'] if a.refill_stats else []),'-std=c++17','-I'+str(saved_build),'-I'+include,'-I'+include+'/vltstd',cpp,str(saved_build/'Vtb__ALL.a')]+[str(saved_build/name) for name in ('verilated.o','verilated_save.o','verilated_threads.o')]+['-pthread','-o',str(binary)]
        with (build/'build.log').open('w') as log:subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True)
    if not binary.exists():
        cmd=docker+['verilator',image,'--cc','--exe','--build','-j',str(a.build_jobs),'--savable','--assert','-DNGAGE_LOGO_RUN','-DNGAGE_RUNTIME_TRACE','-Wno-fatal','-Wno-lint','-Irtl/arm','--top-module','tb','--Mdir',str(build),'-CFLAGS','-O3'+(' -DNGAGE_REFILL_STATS' if a.refill_stats else ''),'-GLINE_REFILL='+str(int(a.line_refill)),'-GTIMER_CLK_DIV='+str(a.sys_clk_hz//26000000 if a.timer_clock=='26mhz' else 1),'-GNOS_TICK_HZ='+str(a.nos_tick_hz),'-GSYS_CLK_HZ='+str(a.sys_clk_hz),'-GDIRECT_SDRAM='+str(int(not a.legacy_sdram_route)),'-GROM_CACHE='+str(int(a.rom_cache)),'-GROM_CACHE_BITS='+str(a.rom_cache_bits),'-GROM_CACHE_BYTES='+str(a.rom_cache_bytes)]+(['-DNGAGE_NOS_OVERLAY_RUN','-GOVERLAY_COMPONENT='+str(overlay_id)] if overlay_path else [])+(['-DNGAGE_POWERUP_NORMAL'] if a.powerup=='normal' else [])+(['-DNGAGE_EARLY_BOOT_TRACE'] if a.early_boot_trace else [])+(['-DNGAGE_FAULT_CONTEXT'] if a.fault_context else [])+(['-DNGAGE_PRODUCTION_DDR'] if a.production_ddr else [])+sources+['/work/'+cpp]
        with (build/'build.log').open('w') as log:subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True)
    # Precompiled headers are large and unused once the executable exists.
    for cache in build.glob('*.gch'):cache.unlink()
    if a.build_only:print(binary);return
    out=Path('build/sim/runs')/a.name;out.mkdir(parents=True,exist_ok=False)
    inputs={k:{'path':str(getattr(a,k)),'sha256':sha(getattr(a,k))} for k in ('core','extension','cdrive')}
    manifest={'production_ddr':a.production_ddr,'fault_context':a.fault_context,'key_pulse':[a.key_at,a.key_mask,a.key_hold],'refill_stats':a.refill_stats,'line_refill':a.line_refill,'timer_clock':a.timer_clock,'nos_tick_hz':a.nos_tick_hz,'direct_sdram':not a.legacy_sdram_route,'rom_cache_bits':a.rom_cache_bits,'rom_cache_bytes':a.rom_cache_bytes,'rom_cache':a.rom_cache,'sys_clk_hz':a.sys_clk_hz,'powerup':a.powerup,'source_identity':identity,'sources':hashes,'binary_sha256':sha(binary),'image':image_id,'inputs':inputs,'cycles_target':a.cycles,'restore':str(a.restore) if a.restore else None,'profile':'no SIM/no ATR, erased PMM, phone video, HDL peripherals; preloaded DDR and zeroed 16MiB SDRAM; modeled backing memories, 100MHz system, fixed response delays from bounded harness'}
    if overlay_sha:manifest[overlay_key]={'sha256':overlay_sha,'path':str(overlay_path),'skip_primary_checksum':True}
    manifest['interactive_keys']=saved.get('interactive_keys',False) if saved is not None else True
    manifest['stop_after_lcd_words']=a.stop_after_lcd_words
    manifest['stop_on_kernel_panic']=a.stop_on_kernel_panic
    manifest['checkpoint_schedule']={'through_cycle':a.checkpoint_switch,'period_through':a.checkpoint_before,'period_after':a.checkpoint_after}
    if a.cpu_reference_dir:manifest['cpu_reference_dir']=str(a.cpu_reference_dir)
    if saved is not None:manifest['uses_saved_build']=True
    if a.restore:
        prior=json.loads((a.restore.parent/'manifest.json').read_text())
        if prior.get('cpu_reference_dir'):manifest['cpu_reference_dir']=prior['cpu_reference_dir']
        if prior.get('diagnostic_fork') or prior.get('inherited_diagnostic_fork'):
            manifest['inherited_diagnostic_fork']=prior.get('diagnostic_fork') or prior['inherited_diagnostic_fork']
        if prior.get(overlay_key,{}).get('sha256')!=overlay_sha or prior.get('bluetooth_overlay' if overlay_key=='nos_overlay' else 'nos_overlay'):raise ValueError('component overlay differs; restart from reset')
        if prior.get('line_refill',False)!=a.line_refill:raise ValueError('line refill mode differs; use only an explicitly audited fork')
        if prior.get('timer_clock','cpu')!=a.timer_clock or prior.get('nos_tick_hz',1000)!=a.nos_tick_hz:raise ValueError('timer experiment differs; restart from reset')
        if prior.get('production_ddr',False)!=a.production_ddr:raise ValueError('DDR backend differs; restart from reset')
        if prior.get('fault_context',False)!=a.fault_context or prior.get('key_pulse',[0,0,0])!=[a.key_at,a.key_mask,a.key_hold]:raise ValueError('fault observer/key pulse differs; restart from reset')
        if prior.get('powerup','alarm')!=a.powerup:raise ValueError('reset cause differs; restart from reset')
        if not a.use_saved_build and prior.get('direct_sdram',False)!=(not a.legacy_sdram_route):raise ValueError('SDRAM route differs; restart from reset')
        if prior.get('sys_clk_hz',104000000)!=a.sys_clk_hz:raise ValueError('clock parameter differs; restart from reset')
        if not a.use_saved_build and (prior.get('rom_cache',False),prior.get('rom_cache_bits',64),prior.get('rom_cache_bytes',1024))!=(a.rom_cache,a.rom_cache_bits,a.rom_cache_bytes):raise ValueError('cache configuration differs; restart from reset')
        for key in (('image','inputs') if (a.diagnostic_irq_fork or a.driver_upgrade or a.pretest_fixes_fork) else ('binary_sha256','image','inputs')):
            if prior[key]!=manifest[key]:raise ValueError('checkpoint lineage mismatch: '+key)
        if not (a.diagnostic_irq_fork or a.driver_upgrade or a.pretest_fixes_fork):
            for name,digest in prior['sources'].items():
                if not name.endswith('.py') and hashes.get(name)!=digest:
                    raise ValueError('compiled source mismatch: '+name)
        if a.diagnostic_irq_fork or a.driver_upgrade or a.pretest_fixes_fork:
            changed=[f for f,h in prior['sources'].items() if f.startswith('rtl/') and hashes.get(f)!=h]
            if (a.diagnostic_irq_fork and (changed!=['rtl/ngage_nos_io.v'] or prior['sources'][cpp]!=hashes[cpp])) or (a.driver_upgrade and changed) or (a.pretest_fixes_fork and set(changed)!=set(['rtl/ngage_nos_io.v','rtl/ngage_keypad.v','rtl/ngage_upp_peripherals.v'])):
                raise ValueError('unsupported state fork: HDL/driver changes exceed selected upgrade')
            previous=Path('build/sim/logo-build')/prior['source_identity'][:16]
            def schema(folder):
                return {f.name:[line.strip() for line in f.read_text().splitlines() if 'os<<' in line.replace(' ','') or '__Vcheckval =' in line or 'for (int __Vi' in line] for f in folder.glob('*.cpp') if '__Vserialize' in f.read_text()}
            if schema(previous)!=schema(build):raise ValueError('serialized model layout changed; restart from reset')
            if a.pretest_fixes_fork:manifest['diagnostic_fork']='Pre-self-test checkpoint: NOS IRQ-mask and UEM-routed GENIO1 fixes plus verified observer upgrade; MTC=0, CPSR IRQ/FIQ masked before fork. Not a cold final-model run.'
            if a.diagnostic_irq_fork:manifest['diagnostic_fork']='NOS IRQ mask correction; interrupted prior hardware profile, not a clean final-model boot'
            if a.driver_upgrade:manifest['driver_upgrade']='Observer-only upgrade; 64-bit cycle count and 100M checkpoint cadence; unchanged HDL serialization and Host layout'
            if prior.get('diagnostic_fork'):manifest['inherited_diagnostic_fork']=prior['diagnostic_fork']
            if prior.get('inherited_diagnostic_fork'):manifest['inherited_diagnostic_fork']=prior['inherited_diagnostic_fork']
            manifest['parent_source_identity']=prior['source_identity']
        for suffix in ('.cpu','.host'):
            if not Path(str(a.restore)+suffix).is_file() and not Path(str(a.restore)+suffix+'.gz').is_file():raise ValueError('missing checkpoint pair')
    (out/'inputs').mkdir();shutil.copyfile(a.cdrive,out/'inputs/cdrive.img')
    if overlay_path:
        overlay_hex=out/'inputs/nos-overlay.hex'
        data=overlay_path.read_bytes()
        shutil.copyfile(overlay_path,out/('inputs/Bluetooth_Compatibility.ngo' if overlay_id==2 else 'inputs/NOS_Compatibility.ngo'))
        overlay_hex.write_text(''.join(f'{w[0]:04x}\n' for w in struct.iter_unpack('<H',data.ljust(8192,b'\0'))))
    actual_restore=a.restore
    staging=None
    if a.restore and any(not Path(str(a.restore)+suffix).exists() for suffix in ('.cpu','.host')):
        staging=out/'restore-input';staging.mkdir()
        actual_restore=staging/a.restore.name
        metadata=Path(str(a.restore)+'.archive.json')
        expected=json.loads(metadata.read_text()) if metadata.exists() else {}
        for suffix in ('.cpu','.host'):
            original=Path(str(a.restore)+suffix);dest=Path(str(actual_restore)+suffix)
            if original.exists():shutil.copyfile(original,dest)
            else:
                with gzip.open(str(original)+'.gz','rb') as src,dest.open('xb') as dst:shutil.copyfileobj(src,dst)
            if suffix in expected and sha(dest)!=expected[suffix]['sha256']:raise ValueError('archived checkpoint hash mismatch')
        manifest['restore_from_archive']=True
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (out/'key-command.txt').write_text('0 0 0\n')
    cmd=docker+['/work/'+str(binary),image,str(a.cycles),str(out),str(actual_restore) if actual_restore else '-', '+ngage-compact-trace','+core='+str(a.core),'+extension='+str(a.extension),'+cdrive='+str(out/'inputs/cdrive.img')]
    if overlay_path:cmd+=['+nos-overlay='+str(overlay_hex)]
    if a.fault_context:cmd+=['+key-at='+str(a.key_at),'+key-mask='+format(a.key_mask,'x'),'+key-hold='+str(a.key_hold)]
    cmd+=['+checkpoint-before='+str(a.checkpoint_before),'+checkpoint-after='+str(a.checkpoint_after),'+checkpoint-switch='+str(a.checkpoint_switch),'+key-command='+str(out/'key-command.txt')]
    if a.stop_on_kernel_panic:cmd+=['+stop-kernel-panic']
    if a.stop_after_lcd_words:cmd+=['+stop-lcd-words='+str(a.stop_after_lcd_words)]
    print('Running',out,flush=True)
    try:
        run_model(cmd,out)
    finally:
        if staging is not None:shutil.rmtree(staging)
    screens=Path('build/sim/screens')/a.name;screens.mkdir(parents=True,exist_ok=False)
    for label in ('framebuffer','scanout'):png(out/(label+'.ppm'),screens/(label+'.png'))
    result=json.loads((out/'result.json').read_text());result['outputs']={str(f):sha(f) for f in [out/'framebuffer.bin',*screens.glob('*.png')]};(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    for k,v in inputs.items():assert sha(v['path'])==v['sha256'],k+' input mutated'
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
