#!/usr/bin/env python3
"""Resumable actual-HDL phone boot with explicitly modeled backing memories."""
import argparse, glob, gzip, hashlib, json, shutil, subprocess, struct, zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
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
    interesting=(b'PROGRESS ',b'REACHED ',b'CHECKPOINT ',b'BUS_FAULT ',b'LCD ',b'LCD_UNKNOWN ',b'ERROR ',b'FAIL ',b'PASS ',b'%Error',b'FATAL')
    with gzip.open(out/'run.log.gz','wb',compresslevel=1) as archive,(out/'run.log').open('w+b') as live,(out/'progress.log').open('wb') as progress:
        process=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        while chunk:=process.stdout.read1(65536):
            archive.write(chunk);total+=len(chunk)
            take=min(cap-len(head),len(chunk));head.extend(chunk[:take]);tail.extend(chunk[take:])
            if len(tail)>cap:del tail[:-cap]
            lines=(pending+chunk).split(b'\n');pending=lines.pop()
            for line in lines:
                if line.startswith(interesting):progress.write(line+b'\n')
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
    p.add_argument('--nos-overlay',type=Path,help='separate cold-run lineage: stage NOS_Compatibility.ngo through real overlay loader before CPU release')
    p.add_argument('--build-jobs',type=int,default=4)
    p.add_argument('--rom-cache-bits',type=int,choices=(64,128,256),default=64)
    p.add_argument('--rom-cache-bytes',type=int,choices=(1024,2048,4096),default=1024)
    p.add_argument('--timer-clock',choices=('cpu','26mhz'),default='cpu',help='counter clock; 26mhz is a separate experiment lineage')
    p.add_argument('--nos-tick-hz',type=int,choices=(1000,64),default=1000,help='NOS counter frequency, not a forced IRQ frequency')
    p.add_argument('--legacy-sdram-route',action='store_true',help='A/B baseline: keep SDRAM behind peripheral bridge')
    p.add_argument('--rom-cache',action='store_true',help='enable production 1KiB DDR ROM cache')
    p.add_argument('--early-boot-trace',action='store_true',help='bounded delay/caller observer for independent short investigations')
    p.add_argument('--sys-clk-hz',type=int,default=104000000,help='phone clock/timebase parameter; requires a new checkpoint lineage when changed')
    p.add_argument('--core',type=Path,default=Path('build/firmware/nem4-factory/core.bin'));p.add_argument('--extension',type=Path,default=Path('build/firmware/nem4-factory/extension.bin'));p.add_argument('--cdrive',type=Path,default=Path('scratch/overnight/cdrive-11b.img'))
    a=p.parse_args();assert Path.cwd()==ROOT and 0<a.cycles<2**63 and '/' not in a.name and a.name not in ('.','..')
    # Keep exactly the bounded harness's HDL sources; no software peripherals.
    script=Path('tests/phone/hardware_boot/run.sh').read_text();source_text=script.split('--Mdir build/sim/unit-hardware-boot/obj ',1)[1].split(' > build/',1)[0]
    sources=[f for token in source_text.split() for f in sorted(glob.glob(token))]
    sources+=['rtl/ngage_ddr_rom_cache.v','rtl/jtframe/ngage_jtframe_romrq_lcache.v']
    if a.nos_overlay:sources+=['rtl/ngage_nos_overlay.v']
    assert sources and 'tests/phone/hardware_boot/tb.v' in sources
    cpp='tests/phone/hardware_boot/logo_main.cpp'
    headers=sorted(str(f) for f in Path('rtl').rglob('*') if f.suffix in ('.vh','.svh'))
    assets=['rtl/ngage_debug_font.hex','rtl/ngage_debug_font.mif']
    hashes={f:sha(f) for f in sources+headers+assets+[cpp,__file__]}
    saved=None
    if a.use_saved_build:
        if not a.restore or a.diagnostic_irq_fork or a.pretest_fixes_fork:
            raise ValueError('--use-saved-build requires --restore and forbids model upgrades')
        saved=json.loads((a.restore.parent/'manifest.json').read_text())
        hashes=dict(saved['sources'])
        if a.driver_upgrade:
            hashes[cpp]=sha(cpp)
            hashes[__file__]=sha(__file__)
    overlay_sha=sha(a.nos_overlay) if a.nos_overlay else None
    if a.nos_overlay:
        import sys
        sys.path.insert(0,str(ROOT/'tools'))
        import nos_overlay
        nos_overlay.inspect(a.nos_overlay.read_bytes())
    identity_fields={'sources':hashes,'powerup':a.powerup,'direct_sdram':not a.legacy_sdram_route}
    if overlay_sha:identity_fields['nos_overlay_sha256']=overlay_sha
    if a.sys_clk_hz!=104000000:identity_fields['sys_clk_hz']=a.sys_clk_hz
    if a.timer_clock!='cpu':identity_fields['timer_clock']=a.timer_clock
    if a.nos_tick_hz!=1000:identity_fields['nos_tick_hz']=a.nos_tick_hz
    if a.timer_clock=='26mhz' and a.sys_clk_hz not in (78000000,104000000):raise ValueError('26MHz timers require 78/104MHz CPU')
    if a.early_boot_trace:identity_fields['early_boot_trace']=True
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
        for source in saved_build.iterdir():
            if source.suffix in ('.h','.cpp') and not (build/source.name).exists():
                shutil.copyfile(source,build/source.name)
        include='/usr/local/verilator/share/verilator/include'
        cmd=docker+['g++',image,'-O3','-std=c++17','-I'+str(saved_build),'-I'+include,'-I'+include+'/vltstd',cpp,str(saved_build/'Vtb__ALL.a')]+[str(saved_build/name) for name in ('verilated.o','verilated_save.o','verilated_threads.o')]+['-pthread','-o',str(binary)]
        with (build/'build.log').open('w') as log:subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True)
    if not binary.exists():
        cmd=docker+['verilator',image,'--cc','--exe','--build','-j',str(a.build_jobs),'--savable','--assert','-DNGAGE_LOGO_RUN','-DNGAGE_ASSOC_EXPERIMENT','-DNGAGE_RUNTIME_TRACE','-Wno-fatal','-Wno-lint','-Irtl/arm','--top-module','tb','--Mdir',str(build),'-CFLAGS','-O3','-GTIMER_CLK_DIV='+str(a.sys_clk_hz//26000000 if a.timer_clock=='26mhz' else 1),'-GNOS_TICK_HZ='+str(a.nos_tick_hz),'-GSYS_CLK_HZ='+str(a.sys_clk_hz),'-GDIRECT_SDRAM='+str(int(not a.legacy_sdram_route)),'-GROM_CACHE='+str(int(a.rom_cache)),'-GROM_CACHE_BITS='+str(a.rom_cache_bits),'-GROM_CACHE_BYTES='+str(a.rom_cache_bytes)]+(['-DNGAGE_NOS_OVERLAY_RUN'] if a.nos_overlay else [])+(['-DNGAGE_POWERUP_NORMAL'] if a.powerup=='normal' else [])+(['-DNGAGE_EARLY_BOOT_TRACE'] if a.early_boot_trace else [])+sources+['/work/'+cpp]
        with (build/'build.log').open('w') as log:subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True)
    # Precompiled headers are large and unused once the executable exists.
    for cache in build.glob('*.gch'):cache.unlink()
    if a.build_only:print(binary);return
    out=Path('build/sim/runs')/a.name;out.mkdir(parents=True,exist_ok=False)
    inputs={k:{'path':str(getattr(a,k)),'sha256':sha(getattr(a,k))} for k in ('core','extension','cdrive')}
    manifest={'timer_clock':a.timer_clock,'nos_tick_hz':a.nos_tick_hz,'direct_sdram':not a.legacy_sdram_route,'rom_cache_bits':a.rom_cache_bits,'rom_cache_bytes':a.rom_cache_bytes,'rom_cache':a.rom_cache,'sys_clk_hz':a.sys_clk_hz,'powerup':a.powerup,'source_identity':identity,'sources':hashes,'binary_sha256':sha(binary),'image':image_id,'inputs':inputs,'cycles_target':a.cycles,'restore':str(a.restore) if a.restore else None,'profile':'no SIM/no ATR, erased PMM, phone video, HDL peripherals; preloaded DDR and zeroed 16MiB SDRAM; modeled backing memories, 100MHz system, fixed response delays from bounded harness'}
    if overlay_sha:manifest['nos_overlay']={'sha256':overlay_sha,'path':str(a.nos_overlay),'skip_primary_checksum':True}
    if saved is not None:manifest['uses_saved_build']=True
    if a.restore:
        prior=json.loads((a.restore.parent/'manifest.json').read_text())
        if prior.get('diagnostic_fork') or prior.get('inherited_diagnostic_fork'):
            manifest['inherited_diagnostic_fork']=prior.get('diagnostic_fork') or prior['inherited_diagnostic_fork']
        if prior.get('nos_overlay',{}).get('sha256')!=overlay_sha:raise ValueError('NOS overlay differs; restart from reset')
        if prior.get('timer_clock','cpu')!=a.timer_clock or prior.get('nos_tick_hz',1000)!=a.nos_tick_hz:raise ValueError('timer experiment differs; restart from reset')
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
    if a.nos_overlay:
        overlay_hex=out/'inputs/nos-overlay.hex'
        data=a.nos_overlay.read_bytes()
        shutil.copyfile(a.nos_overlay,out/'inputs/NOS_Compatibility.ngo')
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
    cmd=docker+['/work/'+str(binary),image,str(a.cycles),str(out),str(actual_restore) if actual_restore else '-', '+ngage-compact-trace','+core='+str(a.core),'+extension='+str(a.extension),'+cdrive='+str(out/'inputs/cdrive.img')]
    if a.nos_overlay:cmd+=['+nos-overlay='+str(overlay_hex)]
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
