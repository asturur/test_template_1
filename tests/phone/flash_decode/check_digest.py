import hashlib, subprocess
cmd=['docker','run','--rm','--network','none','--platform','linux/arm64','-v',__import__('os').getcwd()+':/work','-w','/work','--entrypoint','/work/build/sim/unit-flash-decode/obj/Vngage_flash_read_decode','jotego/simulator:arm64','/work/build/firmware/nem4-factory/core.bin']
h=hashlib.md5(); count=0
p=subprocess.Popen(cmd,stdout=subprocess.PIPE)
while True:
 b=p.stdout.read(65536)
 if not b:break
 count+=len(b);h.update(b)
if p.wait() or count!=0x11b5000-0x9000 or h.hexdigest()!='2c09c86ff047484fdcc0e226f49c44a9':raise SystemExit('RTL core digest mismatch')
print('PASS stock core digest through RTL:',h.hexdigest(),f'({count} bytes)')
