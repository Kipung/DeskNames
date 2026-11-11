import json,sys
from pathlib import Path
r=json.loads(Path(sys.argv[1]).read_text())
checks=[]; expanded=0; hidden=0; latest={}; failures=[]
for s in r['samples']:
    panels={p['desktopID']:p for p in s['panels'] if p['visible']}
    if not s['missionControlOpen'] or not s['labelsEnabled'] or not s['accessibilityGranted']:
        if panels: failures.append('Labels remained visible when unavailable')
        hidden+=1
        continue
    for strip in s['strips']:
        screen=next((d for d in s['screens'] if d['displayID']==strip['displayID']),None)
        if not screen: continue
        slots=sorted([d for d in s['slots'] if d['display']==screen['uuid'] or (len(s['screens'])==1 and d['display']=='Main')],key=lambda d:d['position'])
        if strip['frame']['height']<=40:
            if any(d['desktopID'] in panels for d in slots): failures.append('Labels remained visible in compact strip')
            hidden+=1
            continue
        expanded+=1
        if len(slots)!=len(strip['buttons']): continue
        for d,b in zip(slots,strip['buttons']):
            p=panels.get(d['desktopID'])
            if d['isFullScreen']:
                if p: failures.append('Full-screen Space received custom label')
                continue
            if not p: continue
            f=p['frame'];q=screen['quartzFrame'];a=screen['appKitFrame']
            center=a['x']+b['x']-q['x']+b['width']/2
            top=a['y']+a['height']-(strip['frame']['y']+strip['frame']['height']-q['y'])-4
            error=abs(f['x']+f['width']/2-center); yerror=abs(f['y']+f['height']-top)
            c={'desktopID':d['desktopID'],'horizontalError':round(error,4),'verticalError':round(yerror,4)}
            checks.append(c);latest[d['desktopID']]=c
            if error>1 or yerror>1: failures.append(f'Panel misaligned: {c}')
for c in latest.values(): print(json.dumps(c))
print(f'Expanded samples: {expanded}; closed/compact checks: {hidden}; visible comparisons: {len(checks)}')
if not checks:
    print('INCONCLUSIVE: no expanded strip with visible labels was captured')
    sys.exit(2)
if failures:
    print('FAIL: '+str(len(failures))+' incorrect placements or visibility states')
    print('\n'.join(failures[:8]));sys.exit(1)
print(f'PASS: {len(checks)} actual label frames match native centers and strip edge within 1 pt')
