"""Check third-slot revocation at the committed banked controller's delayed fill."""
import argparse
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'tlb_three_mapping'))
from build import DOCKER, IMAGE, OUT, ROOT, command, cpath, replace, save, sha

COMMIT = '1928aeef68cbd65699014854326c38101f5249a7'


def main(build, out):
    out.mkdir(parents=True,exist_ok=False)
    rtl=build/'source/rtl'
    tlb=rtl/'arm920/tlb.sv'
    published=subprocess.check_output(['git','show',f'{COMMIT}:rtl/arm920/tlb.sv'],cwd=ROOT)
    assert tlb.read_bytes()==published
    fixture=subprocess.check_output(['git','show',f'{COMMIT}:tests/cpu/tlb_two_mapping/test.sv'],
                                    cwd=ROOT,text=True)
    sample = '''module test;
  integer delayed_edges=0;
  always @(posedge clk)
    if (!reset && dut.state==7 && dut.bank_busy) delayed_edges++;
  final begin
    if (delayed_edges==0) $fatal(1,"no delayed commit edges");
    $display("DELAYED_FILL edges=%0d",delayed_edges);
  end'''
    (out/'test.sv').write_text(replace(fixture,'module test;',sample))
    base=[rtl/'ngage_bram.v',rtl/'arm920/tlb_bank.sv']
    command(DOCKER+['iverilog',IMAGE,'-g2001','-s','arm920_tlb','-tnull','-P','arm920_tlb.THIRD_MAPPING=1']
            +[cpath(p) for p in base+[tlb]],out/'strict.log')
    mutant=out/'tlb-stale.sv'
    mutant.write_text(replace(tlb.read_text(),'        third_valid <= 0;\n      end else if (token_valid',
                             '        if (state!=INSTALL_WAIT) third_valid <= 0;\n      end else if (token_valid'))
    rows={}
    for name,source in [('published',tlb),('stale',mutant)]:
        obj=out/name
        command(DOCKER+['verilator',IMAGE,'--binary','--timing','--assert','-j','2','-Wno-fatal',
                        '-Wno-lint','--top-module','test','-DTEST_THIRD_MAPPING','--Mdir',cpath(obj)]
                +[cpath(p) for p in base+[source,out/'test.sv']],out/(name+'-build.log'))
        log=out/(name+'.log')
        rc=command(DOCKER+[cpath(obj/'Vtest'),IMAGE],log,negative=name=='stale')
        lines=log.read_text().splitlines()
        if name=='stale':
            assert rc and any('stale third-slot grant after main-table replacement' in l for l in lines)
        else:
            assert any(l.startswith('PASS: third slot') for l in lines)
        rows[name]=[l for l in lines if l.startswith(('PASS','DELAYED_FILL')) or 'stale third-slot grant' in l]
        print(name,rows[name],flush=True)
    save(out/'result.json',dict(status='PASS',commit=COMMIT,controller_sha256=sha(tlb),rows=rows))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('name')
    parser.add_argument('--build',required=True)
    args=parser.parse_args()
    main(OUT/args.build,OUT/args.name)
