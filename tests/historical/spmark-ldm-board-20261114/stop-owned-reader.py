import os,signal
matches=[]
for entry in os.listdir('/proc'):
 if entry.isdigit():
  try:
   args=open('/proc/'+entry+'/cmdline','rb').read().split(b'\0')
   if len(args)>3 and args[1]==b'-c' and args[3]==b'--follow' and b'signal.alarm(600);exec(compile(sys.stdin.read(),"ngage_runtime_diag.py","exec"))' in args[2]:matches.append(int(entry))
  except (FileNotFoundError,PermissionError):pass
assert len(matches)<=1, 'Ambiguous readers; none stopped'
for pid in matches:os.kill(pid,signal.SIGINT);print('Stopped owned capture',pid)
