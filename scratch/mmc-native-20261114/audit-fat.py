"""Read-only structural FAT12/16 audit of the exact SPMark04 card on MiSTer."""
from pathlib import Path
import hashlib,json,struct
p=Path('/media/fat/games/ngage/spmark04.mmc')
raw=p.read_bytes();sha=hashlib.sha256(raw).hexdigest()
assert sha=='60d7c4aa989b2393cbeb8f2bbd563cbce0bad5b33d8bb9dac28d89660a772919'
assert raw[-512:-504]==b'NGAGEMMC'
payload=raw[:-512];errors=[];warnings=[];files=[];owners={};visited=set()
u16=lambda b,o:struct.unpack_from('<H',b,o)[0]
u32=lambda b,o:struct.unpack_from('<I',b,o)[0]
assert payload[510:512]==b'\x55\xaa'
partitions=[]
for n in range(4):
 e=payload[446+n*16:462+n*16]
 if e[4]:partitions.append(dict(index=n,type=hex(e[4]),start=u32(e,8),sectors=u32(e,12)))
assert partitions,'Expected the inspected partitioned image'
part=partitions[0];base=part['start'];boot=payload[base*512:(base+1)*512]
assert boot[510:512]==b'\x55\xaa' and u16(boot,11)==512
spc=boot[13];reserved=u16(boot,14);nf=boot[16];roots=u16(boot,17);spf=u16(boot,22);total=u16(boot,19) or u32(boot,32)
assert spc and spc&(spc-1)==0 and reserved and nf and roots and spf
root_sectors=(roots*32+511)//512;overhead=reserved+nf*spf+root_sectors;clusters=(total-overhead)//spc;bits=12 if clusters<4085 else 16 if clusters<65525 else 32
assert bits in (12,16)
if base+part['sectors']>len(payload)//512:errors.append('Partition exceeds payload')
if total>part['sectors']:errors.append('BPB total exceeds partition')
if u32(boot,28)!=base:warnings.append('BPB hidden-sector count differs from partition start')
fat_start=base+reserved;fat=payload[fat_start*512:(fat_start+spf)*512]
fat_mirrors=[fat==payload[(fat_start+i*spf)*512:(fat_start+(i+1)*spf)*512] for i in range(nf)]
if not all(fat_mirrors):errors.append('FAT copies differ')
if len(fat)*8//bits<clusters+2:errors.append('FAT cannot address all data clusters')
root_start=fat_start+nf*spf;data_start=root_start+root_sectors;cluster_bytes=spc*512
maxcluster=clusters+1;eoc=0xff8 if bits==12 else 0xfff8;bad=0xff7 if bits==12 else 0xfff7

def next_cluster(c):
 if bits==16:return u16(fat,c*2)
 v=u16(fat,c+c//2);return (v>>4 if c&1 else v)&0xfff

def chain(start,name):
 out=[];seen=set();c=start
 while c:
  if c<2 or c>maxcluster:errors.append(f'{name}: invalid cluster {c}');break
  if c in seen:errors.append(f'{name}: FAT loop at {c}');break
  seen.add(c);out.append(c)
  if c in owners and owners[c]!=name:errors.append(f'{name}: cross-link with {owners[c]} at {c}')
  owners[c]=name;v=next_cluster(c)
  if v>=eoc:break
  if v in (0,1,bad):errors.append(f'{name}: free/reserved/bad chain link {v:x} at {c}');break
  c=v
 return out

def cluster_data(cs):
 return b''.join(payload[(data_start+(c-2)*spc)*512:(data_start+(c-1)*spc)*512] for c in cs)

def directory(name,start=None,parent=0):
 if start is None:data=payload[root_start*512:(root_start+root_sectors)*512]
 else:
  if start in visited:errors.append(f'{name}: directory cycle');return
  visited.add(start);data=cluster_data(chain(start,name))
 for i in range(0,len(data),32):
  e=data[i:i+32]
  if len(e)<32 or e[0]==0:break
  if e[0]==0xe5 or e[11]==15 or e[11]&8:continue
  stem=e[:8].decode('ascii','replace').rstrip();ext=e[8:11].decode('ascii','replace').rstrip();short=stem+('.'+ext if ext else '');first=u16(e,26);size=u32(e,28)
  if stem in ('.','..'):
   expected=start if stem=='.' else parent
   if first!=expected:errors.append(f'{name}/{stem}: wrong parent/self cluster {first}, expected{expected}')
   continue
  path=name.rstrip('/')+'/'+short
  if e[11]&16:directory(path,first,start or 0);continue
  cs=chain(first,path) if first else []
  needed=(size+cluster_bytes-1)//cluster_bytes
  if len(cs)<needed:errors.append(f'{path}: file truncated: {len(cs)} clusters for {size} bytes')
  if len(cs)>needed:warnings.append(f'{path}: allocated chain exceeds file size')
  content=cluster_data(cs)[:size]
  files.append(dict(path=path,bytes=size,clusters=len(cs),sha256=hashlib.sha256(content).hexdigest()))
directory('/')
allocated={c for c in range(2,maxcluster+1) if next_cluster(c)!=0}
orphans=sorted(allocated-set(owners))
if orphans:errors.append(f'{len(orphans)} allocated clusters unreachable from directories')
report=dict(scope='Read-only FAT12/16 structure and all reachable file allocation chains; no execution or native mount claim',path=str(p),image_sha256=sha,payload_sectors=len(payload)//512,partition=part,geometry=dict(fat_bits=bits,bytes_per_sector=512,sectors_per_cluster=spc,reserved=reserved,fats=nf,root_entries=roots,sectors_per_fat=spf,total_sectors=total,data_clusters=clusters),fat_mirrors_equal=all(fat_mirrors),file_count=len(files),owned_clusters=len(owners),allocated_clusters=len(allocated),orphan_clusters=orphans,files=files,errors=errors,warnings=warnings)
assert hashlib.sha256(p.read_bytes()).hexdigest()==sha,'Source changed during read-only audit'
print(json.dumps(report,indent=2))
