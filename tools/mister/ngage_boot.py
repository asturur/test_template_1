#!/usr/bin/env python3
"""Reload ngage1 once, wait for its setup prompt, and confirm time/date twice."""
import argparse
import datetime
import json
import subprocess
import time
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CONTROL = Path.home()/'.codex/skills/mister-control/scripts/mister.py'
REFERENCE = Path.home()/'.codex/skills/mister-control/references/ngage-time-header.png'
HISTORY = ROOT/'build/mister/ngage1-boot-timing.json'
BOX = (60, 700, 350, 810)
SIZE = (1056, 1248)

def prompt_score(path):
    with Image.open(path) as frame, Image.open(REFERENCE) as reference:
        box = tuple(round(v*frame.size[i%2]/SIZE[i%2]) for i,v in enumerate(BOX))
        crop = frame.convert('RGB').crop(box).resize(reference.size)
        a = [max(p)<90 for p in crop.getdata()]
        b = [max(p)<90 for p in reference.convert('RGB').getdata()]
        union = sum(x or y for x,y in zip(a,b))
        return sum(x and y for x,y in zip(a,b))/union if union else 0.0

def control(*args):
    result = subprocess.run(['python3',str(CONTROL),*args],cwd=ROOT,text=True,
                            stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True)
    return result.stdout.strip()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--launch',default='/media/fat/_Console/ngage1.rbf')
    p.add_argument('--wait-only',action='store_true',help='Core already reloaded; never reload again')
    p.add_argument('--elapsed',type=float,default=0,help='Seconds since that existing reload')
    p.add_argument('--initial-wait',type=float)
    p.add_argument('--safety',type=float,default=10)
    p.add_argument('--deadline',type=float,default=180)
    p.add_argument('--out',type=Path)
    p.add_argument('--dry-run',action='store_true')
    args=p.parse_args()
    history=json.loads(HISTORY.read_text()) if HISTORY.exists() else {'runs':[]}
    prior=[r['prompt_observed_seconds'] for r in history['runs'][-5:]]
    initial=args.initial_wait if args.initial_wait is not None else (max(prior) if prior else 60)
    macro='{hold:enter:180ms}{delay:1500ms}{hold:enter:180ms}'
    if args.dry_run:
        print(json.dumps(dict(reload=None if args.wait_only else args.launch,first_check_seconds=initial,
                              safety_seconds=args.safety,deadline_seconds=args.deadline,keys=macro,
                              prompt_match_required=True,automatic_reload_retries=0)))
        return
    out=args.out or ROOT/'build/sim/screens'/('ngage1-boot-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
    out.mkdir(parents=True,exist_ok=False)
    started=time.monotonic()-args.elapsed
    report={'status':'INCOMPLETE','launch':args.launch,'reload_sent':False,'confirmations':0,'checks':[]}
    def save(): (out/'result.json').write_text(json.dumps(report,indent=2)+'\n')
    save()
    try:
        if not args.wait_only:
            # A timeout may mean the launch already started. Never repeat it.
            report['reload_sent']=True;save();control('reload',args.launch)
        delay=initial-(time.monotonic()-started)
        if delay>0:time.sleep(delay)
        while time.monotonic()-started<=args.deadline:
            check_at=time.monotonic()-started
            shot=out/'setup-check.png';control('screenshot',str(shot));score=prompt_score(shot)
            elapsed=time.monotonic()-started;report['checks'].append(dict(seconds=elapsed,time_prompt_iou=score));save()
            if score>=0.92:
                report['prompt_observed_seconds']=check_at
                time.sleep(args.safety)
                control('keys',macro);report['confirmations']=2
                time.sleep(5);control('screenshot',str(out/'after-confirm.png'))
                if prompt_score(out/'after-confirm.png')>=0.92:
                    raise RuntimeError('Time prompt remained after the two confirmations; no blind retry')
                report.update(status='CONFIRMATIONS_SENT',finished_seconds=time.monotonic()-started)
                history['runs'].append({k:report[k] for k in ['prompt_observed_seconds','finished_seconds']})
                HISTORY.parent.mkdir(parents=True,exist_ok=True);HISTORY.write_text(json.dumps(history,indent=2)+'\n')
                save();print(json.dumps(dict(status=report['status'],seconds=report['finished_seconds'],output=str(out))));return
            time.sleep(10)
        raise RuntimeError('Time setup prompt not detected by deadline; no keys or second reload sent')
    except Exception as error:
        report.update(status='FAILED',error=str(error));save();raise

if __name__=='__main__':main()
