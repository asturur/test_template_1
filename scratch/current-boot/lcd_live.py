"""Render completed DMA records; screen geometry matches composite_lcd_updates."""
from pathlib import Path
import os, struct, sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from composite_lcd_updates import png,px,W,H,FB
class LCD:
 def __init__(self,out):
  self.out=Path(out);self.out.mkdir(parents=True,exist_ok=True)
  self.pixels=bytearray(W*H*3);self.valid=bytearray(W*H);self.seq=0
 def apply(self,cycle,src,data):
  base=src-FB
  if base<0 or base%2 or base>=W*H*2 or len(data)%4:return None
  first=base//2
  for i,(word,) in enumerate(struct.iter_unpack('<I',data)):
   for j,v in enumerate((word&0xffff,word>>16)):
    pos=first+i*2+j
    if pos>=W*H:break
    self.pixels[pos*3:pos*3+3]=px(v);self.valid[pos]=1
  if not all(self.valid):return None
  self.seq+=1;frame=self.out/f'frame{self.seq:04d}_cycle{cycle}.png';tmp=self.out/'.latest.tmp'
  png(self.pixels,frame);png(self.pixels,tmp);os.replace(tmp,self.out/'latest.png')
  return frame
