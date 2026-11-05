from pathlib import Path
import sys
root=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(root/'scratch/current-boot'))
from direct_lcd import DirectLCD
class Stub:
 def __init__(self):self.calls=[]
 def apply(self,cycle,src,data):self.calls.append((cycle,src,data));return 'frame'
def row(c,a,v):return f'{c}\tWRITE\t{a:#x}\t0xf\t{v:#x}\tdata\tlcd_probe_transport\n'
lcd=Stub();d=DirectLCD(lcd)
def command(c,v):d.feed(row(c,0x0c121200,0x09200000));return d.feed(row(c,0x0c121208,v))
def start(c):command(c,0x5c);d.feed(row(c,0x0c121200,d.HEADER))
start(1)
for i in range(d.WORDS):assert d.feed(row(2,0x0c121208,0xffffffff)) is None
assert not lcd.calls
assert command(3,0xaf)=='frame' and len(lcd.calls)==1
start(4)
for i in range(d.WORDS-1):assert d.feed(row(5,0x0c121208,i)) is None
assert len(lcd.calls)==1
assert d.feed(row(6,0x0c121208,0x12345678))=='frame'
assert len(lcd.calls)==2 and len(lcd.calls[1][2])==d.WORDS*4
print('PASS: complete direct frames update live; incomplete frames are not shown')
