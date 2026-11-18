from pathlib import Path
import hashlib,os
assert hashlib.sha256(Path('/media/fat/_Console/ngage1.rbf').read_bytes()).hexdigest()=='ef4a22c75fb81ec9b2743e4ec64f8ea1bfb2b3c6b1e72b1947e991fb4f75c266'
assert hashlib.sha256(Path('/media/fat/games/ngage/spmark04.mmc').read_bytes()).hexdigest()=='60d7c4aa989b2393cbeb8f2bbd563cbce0bad5b33d8bb9dac28d89660a772919'
assert Path('/media/fat/config/ngage1.CFG').read_bytes()==bytes.fromhex('00002100000000000000000000000000')
p=Path('/tmp/ngage1-spmark04-delayed.mgl');p.write_text('''<mistergamedescription>
    <rbf>_Console/ngage1</rbf>
    <file delay="200" type="s" index="2" path="/media/fat/games/ngage/spmark04.mmc"/>
</mistergamedescription>
''')
fd=os.open('/dev/MiSTer_cmd',os.O_WRONLY|os.O_NONBLOCK)
try:os.write(fd,('load_core '+str(p)+'\n').encode())
finally:os.close(fd)
print('Submitted original ngage1 RBF + SPMark04 slot2 MGL with 200-second delayed insertion once')
