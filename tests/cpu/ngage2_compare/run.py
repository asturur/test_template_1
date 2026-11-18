#!/usr/bin/env python3
"""Run unchanged checked payloads on ZAP, standalone ngage2, or the phone CPU."""
import argparse, hashlib, json, re, subprocess, sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
DONOR=Path('/Users/andreabogazzi/develop/ngage2')
REV='78d53d4c129e761d979794c38398aa72ecf87f87'
ARM9V2_FILES = ['rtl/ngage_cpu.sv', 'rtl/arm9v2/arm925t_phone.v'] + sorted(
    str(p.relative_to(ROOT)) for p in (ROOT/'rtl/arm9v2/upstream/sim/stubs').glob('*.sv'))
sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
import run as payload


def donor_tb(text, scalar=False):
    a=text.index('`ifdef BENCH_HAS_LINE')
    b=text.index('    function [31:0] load_word',a)
    text=text[:a]+'''    assign line_req=0;
    assign line_addr=0;
    wire dv,dcfail,last,pabt,und,swi,irq,fiq;
    wire [1:0] dabt;
    wire [31:0] dpc,cpsr;
    wire burst;
    arm925t dut (
        .clk(clk),.reset(reset),.irq(1'b0),.fiq(1'b0),
        .bus_req(cyc),.bus_we(we),.bus_addr(address),.bus_be(be),
        .bus_wdata(wdata),.bus_burst(burst),.bus_bte(bte),
        .bus_rdata(rdata),.bus_ack(ack),.bus_err(1'b0),
        .bus_no_late_error(1'b1),
        .dbg_wb_valid(dv),.dbg_wb_dvalid(dcfail),.dbg_wb_uop_last(last),
        .dbg_wb_dabt(dabt),.dbg_wb_pabt(pabt),.dbg_wb_und(und),
        .dbg_wb_swi(swi),.dbg_wb_irq(irq),.dbg_wb_fiq(fiq),
        .dbg_wb_pc(dpc),.dbg_wb_cpsr(cpsr)
    );
    assign stb=cyc;
    assign lock=0;
    wire code_region=address<32'h40000 ||
        (address>=32'h10000000 && address<32'h10100000) ||
        (address>=32'h50300000 && address<32'h50400000);
    assign code=code_region;
    // Read fills: four 32-bit wrap beats over a 16-bit/cycle backend.
    // Every write beat uses the original scalar32 per-word wait contract,
    // including burst writebacks; burst framing never discounts a write.
    // First word: initial profile wait + registered delivery of two halfwords.
    // Remaining words: two clocks each; no repeated transaction startup.
    reg in_burst=0;
    wire is_line=!we && (burst||in_burst);
    assign cti=burst?3'b010:3'b111;
''' +text[b:]
    a=text.index('    wire [31:0] retire_pc=')
    b=text.index('    assign rdata=',a)
    text=text[:a]+'''    // W completion, including condition-failed instructions. Last excludes
    // internal block-transfer beats and aborted-base restore. Exception
    // records cannot fire a marker. PC is canonical for ARM and Thumb.
    wire [31:0] retire_pc=dpc-(cpsr[5]?32'd4:32'd8);
    wire retire=(dv||dcfail)&&last&&!(|dabt)&&!pabt&&!und&&!swi&&!irq&&!fiq;
    assign ack=cyc&&stb&&waited>= (is_line ?
        (in_burst?1:(code_region?i_wait:d_wait)+3) : (code_region?i_wait:d_wait));
''' + text[b:]
    if scalar:
        text=text.replace('.bus_no_late_error(1\'b1)', '.bus_no_late_error(1\'b0)')
        text=text.replace('waited>= (is_line ?\n        (in_burst?1:(code_region?i_wait:d_wait)+3) : (code_region?i_wait:d_wait));',
                          'waited >= (code_region ? i_wait : d_wait);')
    text=text.replace('            if(ack) begin','''            if(retire && retire_pc==begin_pc) begin
                if(!dut.u_zap.cpu_mmu_en || !dut.u_zap.cpu_dc_en || !dut.u_zap.cpu_ic_en)
                    $fatal(1,"MMU/cache not enabled");
            end
            if(ack) begin
                in_burst<=burst;
                if(is_line) begin
                    if(!in_burst)line_requests=line_requests+1;
                    line_beats=line_beats+2;
                end''')
    # Scalar counters exclude cache-line beats; halfwords count all bursts.
    text=text.replace('scalar_writes=scalar_writes+1;', 'if(!is_line)scalar_writes=scalar_writes+1;')
    text=text.replace('scalar_reads=scalar_reads+1;', 'if(!is_line)scalar_reads=scalar_reads+1;')
    return text


def phone_tb(text, scalar):
    if scalar:
        text=text.replace('.LINE_REFILL(LINE_ENABLE)', '.LINE_REFILL(0)')
    start=text.index('    wire [31:0] retire_pc=')
    end=text.index('    assign ack=', start)
    return text[:start]+'''    wire dv=dut.u_arm925t.dbg_wb_valid;
    wire dcfail=dut.u_arm925t.dbg_wb_dvalid;
    wire last=dut.u_arm925t.dbg_wb_uop_last;
    wire [1:0] dabt=dut.u_arm925t.dbg_wb_dabt;
    wire pabt=dut.u_arm925t.dbg_wb_pabt;
    wire und=dut.u_arm925t.dbg_wb_und;
    wire swi=dut.u_arm925t.dbg_wb_swi;
    wire irq=dut.u_arm925t.dbg_wb_irq;
    wire fiq=dut.u_arm925t.dbg_wb_fiq;
    wire [31:0] dpc=dut.u_arm925t.dbg_wb_pc;
    wire [31:0] cpsr=dut.u_arm925t.dbg_wb_cpsr;
    wire [31:0] retire_pc=dpc-(cpsr[5]?32'd4:32'd8);
    wire retire=(dv||dcfail)&&last&&!(|dabt)&&!pabt&&!und&&!swi&&!irq&&!fiq;
''' + text[end:]


def observe_cpu(tb, cpu, scalar=False):
    from observe import observe
    if cpu=='ngage2':
        tb=donor_tb(tb, scalar=scalar)
    elif cpu=='arm9v2':
        tb=phone_tb(tb, scalar)
    tb=observe(tb, cpu in ('ngage2', 'arm9v2'))
    if cpu=='arm9v2':
        tb=tb.replace('dut.u_zap.', 'dut.u_arm925t.u_zap.').replace('dut.dbg_d_', 'dut.u_arm925t.dbg_d_')
    return tb


def integrated_snapshot(destination):
    hashes={}
    for name in ARM9V2_FILES:
        target=destination/name
        target.parent.mkdir(parents=True, exist_ok=True)
        data=(ROOT/name).read_bytes()
        target.write_bytes(data)
        hashes[name]=payload.sha(data)
    for directory in ('rtl/arm', 'rtl/arm920'):
        (destination/directory).mkdir()
    return dict(commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                kind='phone-arm9v2', files=hashes,
                source_id=payload.sha(json.dumps(hashes, sort_keys=True).encode()), has_line=True)


def main():
    p=argparse.ArgumentParser(add_help=False)
    p.add_argument('--trace',action='store_true')
    p.add_argument('--cpu',choices=['5c','base','ngage2','arm9v2'],required=True)
    p.add_argument('--scalar-refills',action='store_true',help='use per-word refills on the original donor or the enlarged phone CPU')
    a,rest=p.parse_known_args()
    original_support=payload.support
    def support():
        b=original_support()
        snap=b.snapshot
        if a.cpu=='5c':
            b.snapshot=lambda destination:snap(destination,revision=REV)
        elif a.cpu=='base':
            b.snapshot=lambda destination:snap(destination,revision='a2c5863')
        elif a.cpu=='arm9v2':
            b.snapshot=integrated_snapshot
        else:
            def donor_snapshot(destination):
                destination.mkdir(parents=True)
                for d in ['rtl/arm','rtl/arm920']:(destination/d).mkdir(parents=True)
                paths=['sim/stubs/altsyncram.sv','sim/stubs/altdpram.sv','files.qip','rtl/cpu/arm925t_gen.v','rtl/cpu/arm925t.sv','tools/gen_cpu.sh']
                paths+=sorted(str(x.relative_to(DONOR)) for sub in ['zap','arm9','arm9v2'] for x in (DONOR/'rtl/cpu'/sub).glob('*') if x.suffix in ['.sv','.svh'])
                hashes={x:payload.sha((DONOR/x).read_bytes()) for x in paths}
                assert 'rtl/cpu/arm925t_gen.v' in (DONOR/'files.qip').read_text()
                return dict(commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=DONOR).decode().strip(),
                    kind='read-only-external-QIP',files={},dependency_root=str(DONOR),dependencies=hashes,
                    source_id=payload.sha(json.dumps(hashes,sort_keys=True).encode()),has_line=False)
            b.snapshot=donor_snapshot
        return b
    payload.support=support
    command=payload.command
    tb_path=ROOT/'tests/cpu/spmark_payload/tb.v'
    # Base runner expects its fixture next to __file__; generate it only in
    # this run's build directory. The guest assembly function is untouched.
    name=rest[rest.index('--name')+1]
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,63}',name):raise ValueError('invalid output name')
    stage=ROOT/'build/sim/ngage2-compare-fixtures'/name
    stage.mkdir(parents=True,exist_ok=False)
    tb=observe_cpu(tb_path.read_text(), a.cpu, a.scalar_refills)
    (stage/'tb.v').write_text(tb)
    payload.__file__=str(stage/'run.py')
    def run_command(args,log):
        if args[0]=='docker' and a.cpu=='ngage2':
            args=list(args)
            args[args.index('-w'):args.index('-w')]=['-v',str(DONOR)+':/donor:ro']
            if 'verilator' in args:
                ix=args.index('--Mdir')+2
                # Replace the original CPU source closure and include path.
                args=args[:ix]+['/donor/rtl/cpu/arm925t_gen.v','/donor/sim/stubs/altsyncram.sv','/donor/sim/stubs/altdpram.sv',payload.cpath(log.parent/'tb.v')]
        if args[0]=='docker' and a.cpu=='arm9v2' and 'verilator' in args:
            ix=args.index('--Mdir')+2
            args=args[:ix]+['-DNGAGE_ARM9V2']+[payload.cpath(log.parent/'source'/f) for f in ARM9V2_FILES]+[payload.cpath(log.parent/'tb.v')]
        if a.trace and args[0]=='docker' and 'verilator' not in args:args=list(args)+['+compare_trace=1']
        command(args,log)
    payload.command=run_command
    sys.argv=[sys.argv[0]]+rest
    try:
        payload.main()
    except Exception as exc:
        if payload.RUN_OUTPUT:
            failed=json.loads((payload.RUN_OUTPUT/'result.json').read_text())
            failed.update(status='FAIL',error=str(exc))
            payload.save(payload.RUN_OUTPUT/'result.json',failed)
        raise
    out=ROOT/'build/sim/spmark-payload'/name
    result=json.loads((out/'result.json').read_text())
    if a.cpu=='ngage2':
        for f,h in result['manifest']['source']['dependencies'].items():
            assert payload.sha((DONOR/f).read_bytes())==h,'donor dependency changed during run'
    result['comparison_cpu']=a.cpu
    result['comparison_driver_sha256']=payload.sha(Path(__file__).read_bytes())
    payload.save(out/'result.json',result)

if __name__=='__main__':main()
