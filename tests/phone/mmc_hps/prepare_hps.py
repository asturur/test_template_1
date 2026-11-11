"""Copy actual hps_io, changing only its existing PS/2 generated-scope names."""
from pathlib import Path
import os,re
source=Path('sys/hps_io.sv').read_text()
a,b=source.split('///////////////////////////////   PS2   ///////////////////////////////',1)
for name in 'kbd_rd kbd_we kbd_data kbd_data_host mouse_rd mouse_we mouse_data mouse_data_host'.split():
    a=re.sub(r'(?<![\w.])'+name+r'\b','ps2_model.'+name,a)
b=b.replace('if(PS2DIV) begin','if(PS2DIV) begin: ps2_model',1)
out=Path(os.environ.get('MMC_HPS_OUT','build/sim/unit-mmc-hps'))
out.mkdir(parents=True,exist_ok=True)
(out/'hps-compat.sv').write_text(a+'///////////////////////////////   PS2   ///////////////////////////////'+b)
