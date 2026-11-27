import hashlib,importlib.util,subprocess,sys,tempfile
from pathlib import Path
root=Path.cwd(); spec=importlib.util.spec_from_file_location('save',root/'tools/prepare_mister_save.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
with tempfile.TemporaryDirectory(prefix='save-test-',dir=root/'scratch') as d:
 p=Path(d); bundle=p/'test.bundle'; save=p/'test.save'
 subprocess.run([sys.executable,'tools/prepare_mister_images.py','--profile','diagnostic-erased-pmm','--output',str(bundle)],check=True,stdout=subprocess.DEVNULL)
 subprocess.run([sys.executable,'tools/prepare_mister_save.py','create',str(bundle),str(save)],check=True,stdout=subprocess.DEVNULL)
 data,profile,core,ext=m.parse_save(save);bp,parts=m.parse_bundle(bundle)
 assert profile==bp and core==hashlib.sha256(parts[0]).digest() and ext==hashlib.sha256(parts[1]).digest()
 assert data[m.HEADER:m.HEADER+m.C_LEN]==parts[2] and data[-m.PMM_LEN:]==parts[3]
 old=hashlib.sha256(data).digest()
 assert subprocess.run([sys.executable,'tools/prepare_mister_save.py','create',str(bundle),str(save)],capture_output=True).returncode!=0
 assert hashlib.sha256(save.read_bytes()).digest()==old
 b=bytearray(data);b[16]^=1;bad=p/'bad.save';bad.write_bytes(b)
 try:m.parse_save(bad);raise AssertionError('bad header accepted')
 except ValueError:pass
 assert subprocess.run([sys.executable,'tools/prepare_mister_save.py','inspect',str(save),'--bundle',str(bundle)],capture_output=True).returncode==0
 print('PASS save image initialization, firmware binding, corruption and no-overwrite')
