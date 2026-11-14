from pathlib import Path
import struct,json
from PIL import Image,ImageDraw
p=Path(__file__).parent;b=Path('firmware/disk_dump/Z/System/Data/Avkon.mbm').read_bytes();n=struct.unpack_from('<I',b,4)[0];offs=struct.unpack_from('<%dI'%n,b,8);out=[]
for idx,o in enumerate(offs):
 size,header,w,h,tw,th,depth,colour,palette,comp=struct.unpack_from('<10I',b,o+20)
 if (w,h) not in [(30,40),(120,10)] or depth!=8:continue
 stride=((w*depth+31)//32)*4;source=b[o+68:o+68+size-40];data=bytearray();i=0
 if comp==0:data=bytearray(source[:stride*h])
 elif comp==51:
  while i<len(source) and len(data)<stride*h:
   c=struct.unpack('b',source[i:i+1])[0];i+=1
   if c>=0:data+=source[i:i+1]*(c+1);i+=1
   else:data+=source[i:i-c];i-=c
 else:continue
 if len(data)<stride*h:continue
 im=Image.frombytes('L',(stride,h),bytes(data[:stride*h])).crop((0,0,w,h));out.append((idx,im))
cols=8;cw,ch=130,100;canvas=Image.new('RGB',(cols*cw,((len(out)+cols-1)//cols)*ch),'white');d=ImageDraw.Draw(canvas)
for z,(idx,im) in enumerate(out):
 x=z%cols*cw;y=z//cols*ch;d.text((x+2,y+1),str(idx),fill='black');scale=2 if im.width==30 else 1;canvas.paste(im.resize((im.width*scale,im.height*scale),Image.Resampling.NEAREST),(x+2,y+15))
canvas.save(p/'avkon-candidate-shapes.png');print('decoded',len(out),'shape previews; grayscale index values, not original palette colours')
