import csv, datetime as dt, collections, math, gzip, sys, os
rows=collections.defaultdict(dict)
path = sys.argv[1] if len(sys.argv) > 1 else 'baseline-prefan.csv.gz'
opener = gzip.open if path.endswith('.gz') else open
with opener(path, 'rt') as f:
    for r in csv.DictReader(f):
        try: v=float(r['value'])
        except: continue
        rows[int(float(r['ts']))][(r['metric'],r['device'])]=v
ts=sorted(rows)
def g(t,m,d): return rows[t].get((m,d))
drives=['sda','sdb','sdc','sdd']
print(f"samples={len(ts)}  {dt.datetime.utcfromtimestamp(ts[0])}Z -> {dt.datetime.utcfromtimestamp(ts[-1])}Z")

print("\n== per-drive temp summary (C) ==")
print(f"{'drive':6} {'n':>5} {'min':>5} {'p05':>5} {'p50':>5} {'p95':>5} {'max':>5} {'>55h':>6} {'>60h':>6}")
for d in drives:
    v=[g(t,'drive_temp_c',d) for t in ts]; v=[x for x in v if x is not None]
    q=sorted(v); n=len(q)
    p=lambda f:q[int(f*(n-1))]
    h=lambda th: sum(1 for x in v if x>th)*300/3600
    print(f"{d:6} {n:>5} {min(v):>5.0f} {p(.05):>5.0f} {p(.5):>5.0f} {p(.95):>5.0f} {max(v):>5.0f} {h(55):>6.1f} {h(60):>6.1f}")

soc=[(t,g(t,'soc_temp_c','thermal_thermal_zone0/temp0')) for t in ts]
sv=[x for _,x in soc if x is not None]
print(f"\nSoC temp: min={min(sv):.0f} p50={sorted(sv)[len(sv)//2]:.0f} max={max(sv):.0f}")

def pool(t,m):
    xs=[g(t,m,d) for d in drives]; xs=[x for x in xs if x is not None]
    return sum(xs) if xs else None

print("\n== mean drive temp vs pool READ throughput ==")
print(f"{'read MB/s':>14} {'n':>5} {'meanT':>6} {'p95T':>6} {'meanSoC':>8}")
bins=[(0,1),(1,3),(3,10),(10,30),(30,1e9)]
for lo,hi in bins:
    T=[];S=[]
    for t in ts:
        r=pool(t,'read_mbps'); s=g(t,'soc_temp_c','thermal_thermal_zone0/temp0')
        if r is None or not(lo<=r<hi): continue
        dv=[g(t,'drive_temp_c',d) for d in drives]; dv=[x for x in dv if x is not None]
        if dv: T.append(sum(dv)/len(dv))
        if s is not None: S.append(s)
    if T:
        T.sort()
        print(f"{lo:>6}-{hi if hi<1e9 else 'inf':<7} {len(T):>5} {sum(T)/len(T):>6.1f} {T[int(.95*(len(T)-1))]:>6.1f} {sum(S)/len(S) if S else 0:>8.1f}")

print("\n== mean drive temp vs SoC temp ==")
print(f"{'SoC C':>10} {'n':>5} {'meanDriveT':>11}")
for lo,hi in [(0,58),(58,62),(62,66),(66,70),(70,200)]:
    T=[]
    for t in ts:
        s=g(t,'soc_temp_c','thermal_thermal_zone0/temp0')
        if s is None or not(lo<=s<hi): continue
        dv=[g(t,'drive_temp_c',d) for d in drives]; dv=[x for x in dv if x is not None]
        if dv: T.append(sum(dv)/len(dv))
    if T: print(f"{lo:>4}-{hi:<5} {len(T):>5} {sum(T)/len(T):>11.1f}")

def corr(a,b):
    n=len(a); ma=sum(a)/n; mb=sum(b)/n
    num=sum((x-ma)*(y-mb) for x,y in zip(a,b))
    da=math.sqrt(sum((x-ma)**2 for x in a)); db=math.sqrt(sum((y-mb)**2 for y in b))
    return num/(da*db) if da and db else float('nan')
A=[];B=[];C=[];D=[]
for t in ts:
    s=g(t,'soc_temp_c','thermal_thermal_zone0/temp0'); r=pool(t,'read_mbps'); c=g(t,'cpu_busy_frac','/')
    dv=[g(t,'drive_temp_c',d) for d in drives]; dv=[x for x in dv if x is not None]
    if s is None or r is None or c is None or not dv: continue
    A.append(sum(dv)/len(dv)); B.append(s); C.append(r); D.append(c)
print(f"\ncorr(driveT, SoC)      = {corr(A,B):.3f}   (n={len(A)})")
print(f"corr(driveT, readMBps) = {corr(A,C):.3f}")
print(f"corr(driveT, cpuBusy)  = {corr(A,D):.3f}")
print(f"corr(SoC, cpuBusy)     = {corr(B,D):.3f}")

print("\n== nightly idle floor (03:00-06:00 UTC daily min) ==")
byday=collections.defaultdict(list)
for t in ts:
    u=dt.datetime.utcfromtimestamp(t)
    if 3<=u.hour<6:
        dv=[g(t,'drive_temp_c',d) for d in drives]; dv=[x for x in dv if x is not None]
        s=g(t,'soc_temp_c','thermal_thermal_zone0/temp0')
        if dv: byday[u.date()].append((sum(dv)/len(dv), s))
for k in sorted(byday):
    v=byday[k]; print(f"  {k}  driveT_min={min(x[0] for x in v):.1f}  SoC_min={min(x[1] for x in v if x[1] is not None):.1f}")

print("\n== SoC throttle exposure ==")
sv2=[(t,g(t,'soc_temp_c','thermal_thermal_zone0/temp0')) for t in ts]
sv2=[(t,x) for t,x in sv2 if x is not None]
for th in (70,75,80,85):
    n=sum(1 for _,x in sv2 if x>th)
    print(f"  hours SoC >{th}C: {n*300/3600:6.1f}  ({100*n/len(sv2):.1f}% of window)")
top=sorted(sv2,key=lambda p:-p[1])[:8]
print("  hottest samples:")
for t,x in top: print(f"    {dt.datetime.utcfromtimestamp(t)}Z  {x:.0f}C")

print("\n== per-drive spread (slot signature) ==")
base={}
for d in drives:
    q=sorted(x for x in (g(t,'drive_temp_c',d) for t in ts) if x is not None)
    base[d]=q[len(q)//2]
ref=base['sda']
for d in drives: print(f"  {d}: median {base[d]:.0f}C  ({base[d]-ref:+.0f} vs sda)")
