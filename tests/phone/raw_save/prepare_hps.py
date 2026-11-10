"""Create the protocol-identical, PS/2-scope compatibility copy for Verilator."""
from pathlib import Path
import re
s=Path('sys/hps_io.sv').read_text()
a,b=s.split('///////////////////////////////   PS2   ///////////////////////////////',1)
for name in 'kbd_rd kbd_we kbd_data kbd_data_host mouse_rd mouse_we mouse_data mouse_data_host'.split():
 a=re.sub(r'(?<![\w.])'+name+r'\b','ps2_model.'+name,a)
b=b.replace('if(PS2DIV) begin','if(PS2DIV) begin: ps2_model',1)
Path('build/sim/unit-raw-save-hps/hps-compat.sv').write_text(a+'///////////////////////////////   PS2   ///////////////////////////////'+b)
