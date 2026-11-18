from pathlib import Path
import struct,subprocess
p=Path(__file__).parent; src=p.parent
rom=Path("build/firmware/nem4-factory/core.bin").read_bytes()
syms={a[2]:int(a[0],16) for l in (src/"symbols.txt").read_text().splitlines() if len(a:=l.split())==3}
native=bytearray(rom[0x559000:0x55a000]);native[0x8a4:0x8b0]=bytes.fromhex("08b4014b1847c046")+struct.pack("<I",syms["scan_trace"])
for name,data in [("native",native),("payload",(src/"trace.bin").read_bytes())]:
 data=bytes(data).ljust(4096,b"\0");(p/(name+".hex")).write_text("\n".join(f"{w:08x}" for w in struct.unpack("<1024I",data))+"\n")
subprocess.run(["arm-none-eabi-as","-march=armv4t","-o",str(p/"program.o"),str(p/"program.S")],check=True)
subprocess.run(["arm-none-eabi-ld","-Ttext=0","-o",str(p/"program.elf"),str(p/"program.o")],check=True)
subprocess.run(["arm-none-eabi-objcopy","-O","binary",str(p/"program.elf"),str(p/"program.bin")],check=True)
data=(p/"program.bin").read_bytes().ljust(4096,b"\0");(p/"program.hex").write_text("\n".join(f"{w:08x}" for w in struct.unpack("<1024I",data))+"\n")
