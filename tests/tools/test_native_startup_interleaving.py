"""Native LPRF/ADSP shared waiter contract, with explicit fixture scheduling.

The fixture supplies the timeout-state transition and chooses message order.
Original client/pointer-setter/assertion instructions execute unchanged. This
reproduces the consequence of a late result, not the real timer, RTOS schedule,
Bluetooth producer, physical interface or proof of the board race's trigger.
"""
from pathlib import Path
import hashlib,json,runpy,struct
from unicorn import UC_HOOK_CODE
from unicorn.arm_const import *
ROOT=Path(__file__).resolve().parents[2]
n=runpy.run_path(str(ROOT/'tests/tools/test_native_startup_contracts.py'))
u,sent,timers,freed,lengths=n['fixture']();out=n['OUT'];state=n['STATE'];message=n['MESSAGE'];response=n['RESPONSE']
assert n['call'](u,0x516a5be4)==2
assert timers==[1000] and sent[0][:2]==(0x59,0x80009d20) and sent[0][2][:3]==bytes.fromhex('080103')
u.mem_write(state,b'\xff')
assert n['call'](u,0x516a5be4)==0 and bytes(u.mem_read(out,1))==b'\x0d'
# Explicit fixture scheduling of the next native test; no executable changed.
u.mem_write(state,b'\0');assert n['call'](u,0x516a6218)==2
assert timers==[1000,3000] and sent[-1][0]==0x82
# Execute original common response-pointer setter used by dispatcher5159192E.
# The late payload is exactly the captured BT result, not a fabricated8B.
u.mem_write(message,bytes.fromhex('08020100'));u.reg_write(UC_ARM_REG_R0,message);u.reg_write(UC_ARM_REG_LR,n['STOP']|1)
u.emu_start(0x5164ab1d,0,count=100);assert u.reg_read(UC_ARM_REG_PC)==n['STOP']
assert struct.unpack('<I',u.mem_read(response,4))[0]==message
assert bytes(u.mem_read(state,1))==b'\1'
assertions=[]
def trace(c,a,size,d):
 if a==0x516c74e4:
  assertions.append(dict(file=hex(c.reg_read(UC_ARM_REG_R0)),line=c.reg_read(UC_ARM_REG_R1),expr=hex(c.reg_read(UC_ARM_REG_R2)),lr=hex(c.reg_read(UC_ARM_REG_LR))))
  c.emu_stop()
u.hook_add(UC_HOOK_CODE,trace);u.reg_write(UC_ARM_REG_R0,out);u.reg_write(UC_ARM_REG_LR,n['STOP']|1)
u.emu_start(0x516a6219,0,count=1000)
assert len(assertions)==1 and assertions[0]['line']==0xdf2 and assertions[0]['lr']=='0x516a629b'
assert not freed
assert bytes(u.mem_read(n['BASE'],len(n['BODY'])))==n['BODY']
report=dict(scope='Original LPRF timeout then late59/02 during ADSP shared waiter; explicit fixture scheduling, not full RTOS/hardware proof',lprf_timeout=1000,adsp_timeout=3000,late_bt_payload='08020100',assertions=assertions,rom_unchanged=True)
output=ROOT/'build/sim/unit-native-startup-interleaving'
output.mkdir(parents=True,exist_ok=True)
(output/'result.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS reproduced original St_product/DF2 from late BT result after1000 timeout while ADSP3000 pending; original code unchanged')
