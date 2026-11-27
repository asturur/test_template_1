"""Generate the 32-byte early-restart trial for the error-free phone line peer."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
BASE = '8546db1'


def swap(source, before, after):
    if source.count(before) != 1:
        raise ValueError(f'Expected a unique v5 anchor: {before!r}')
    return source.replace(before, after)


def original(path):
    return subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT, text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True)
    wrapper = original('rtl/ngage_cpu.sv')
    wrapper = swap(wrapper, '    wire [31:0] donor_read_data;',
                   '    wire [31:0] donor_read_data;\n    wire donor_restart_safe;')
    wrapper = swap(wrapper, '        .cpu_error  (donor_error),',
                   '        .cpu_error  (donor_error),\n        .cpu_restart_safe(donor_restart_safe),')
    wrapper = swap(wrapper, ".bus_no_late_error(1'b0)", '.bus_no_late_error(donor_restart_safe)')
    wrapper = swap(wrapper, '    output wire        cpu_error,',
                   '    output wire        cpu_error,\n    output wire        cpu_restart_safe,')
    wrapper = swap(wrapper, '    assign cpu_data = state == LINE ? words[consumed] : wb_data;', '''
    // This trial wrapper is compiled only against ngage_mister's accepted
    // SDRAM/NOR line peer, which has no error return channel. Scalar peers
    // and rejected offers retain their original late-abort handling.
    assign cpu_restart_safe = state == LINE && cpu_ack && consumed == 0 && !line_reject;
    assign cpu_data = state == LINE ? words[consumed] : wb_data;'''.lstrip('\n'))
    netlist = original('rtl/arm9v2/arm925t_phone.v')
    netlist = swap(netlist, '(((CACHE_LINE == 16) && fetch_wrap_ff) && i_wb_no_late_error) && !i_wb_err',
                   '((((CACHE_LINE == 16) && fetch_wrap_ff) || ((CACHE_LINE == 32) && !fetch_wrap_ff)) && i_wb_no_late_error) && !i_wb_err')
    (args.out / 'ngage_cpu.sv').write_text(wrapper)
    (args.out / 'arm925t_phone.v').write_text(netlist)


if __name__ == '__main__':
    main()
