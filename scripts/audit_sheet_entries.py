#!/usr/bin/env python3
"""Scan the FTS and XTS response sheets (CSV exports of the first tab) for likely
data-entry errors: brand spelling/spacing variants, lot numbers within 2 edits
of each other, one lot under two brands, odd or inconsistent expirations, tester
name variants.  Prints row numbers (= Google Sheet rows) for manual review; it
never changes data.  See the Operational Runbook wiki page for the checklist.

Usage: python3 scripts/audit_sheet_entries.py <fts.csv> <xts.csv>
"""
import csv,re,itertools,collections,sys
def load(path,skip,cols):
    rows=list(csv.reader(open(path)))[skip:]
    out=[]
    for n,r in enumerate(rows,start=skip+1):
        g=lambda c:(r[c] if c<len(r) else '').strip()
        out.append(dict(row=n,ts=g(0),name=g(2),brand=g(6),lot=g(7),exp=g(8),src=g(cols['src']),notes=[g(c) for c in cols['notes']]))
    return out
D={'FTS':load(sys.argv[1],3,dict(src=10,notes=[67,68])),'XTS':load(sys.argv[2],1,dict(src=9,notes=[72]))}
def norm(s): return re.sub(r'[^a-z0-9]','',s.lower())
def lev(a,b):
    if abs(len(a)-len(b))>2: return 9
    prev=list(range(len(b)+1))
    for i,ca in enumerate(a,1):
        cur=[i]
        for j,cb in enumerate(b,1):
            cur.append(min(prev[j]+1,cur[j-1]+1,prev[j-1]+(ca!=cb)))
        prev=cur
    return prev[-1]
for ds,recs in D.items():
    print('=====',ds,len(recs),'rows')
    brands=collections.Counter(r['brand'] for r in recs)
    print('BRANDS:',dict(brands))
    byn=collections.defaultdict(set)
    for b in brands: byn[norm(b)].add(b)
    for k,v in byn.items():
        if len(v)>1: print('  brand spelling variants:',v)
    bl=list(brands)
    for a,b in itertools.combinations(bl,2):
        if norm(a)!=norm(b) and lev(norm(a),norm(b))<=2: print('  similar brands:',a,'|',b)
    # lots
    lots=collections.defaultdict(list)
    for r in recs: lots[(norm(r['brand']),re.sub(r'\s','',r['lot']).upper())].append(r)
    print('lots (brand,lot) n:',len(lots))
    keys=list(lots)
    print(' same brand-normalised lots differing by <=2 edits, or case/space/punct variants:')
    for a,b in itertools.combinations(keys,2):
        if a[0]==b[0] and lev(a[1],b[1])<=2:
            print('  ',a[0],a[1],'(n=%d)'%len(lots[a]),'vs',b[1],'(n=%d)'%len(lots[b]),'rows',[r['row'] for r in lots[a]],[r['row'] for r in lots[b]])
    print(' same lot string under different brands:')
    bylot=collections.defaultdict(set)
    for (b,l),rs in lots.items(): bylot[l].add(b)
    for l,bs in bylot.items():
        if len(bs)>1: print('  ',l,bs)
    print(' lot raw-form variants (same normalised lot, different raw text):')
    for k,rs in lots.items():
        raws={r['lot'] for r in rs}; brs={r['brand'] for r in rs}
        if len(raws)>1 or len(brs)>1: print('  ',k,raws,brs)
    print(' expiration inconsistent within lot:')
    for k,rs in lots.items():
        ex={r['exp'] for r in rs}
        if len(ex)>1: print('  ',k,[(r['row'],r['exp']) for r in rs])
    print(' odd lot strings (leading/trailing space, letter O vs 0, I/l, scientific notation, .0, very short/long):')
    for r in recs:
        raw=r['lot']
        if re.search(r'[Ee]\+|\.0$|^\d+\.\d+$',raw) or len(raw)<4 or len(raw)>16 or re.search(r'[ ]{2,}|[^\w\- /]',raw): print('  row',r['row'],repr(raw),r['brand'])
    print(' missing/odd expiration:')
    for r in recs:
        if not re.match(r'^\d{1,2}/\d{1,2}/\d{4}$',r['exp']): print('  row',r['row'],r['brand'],r['lot'],repr(r['exp']))
    print(' testers:',dict(collections.Counter(r['name'] for r in recs)))
    print(' sources:',dict(collections.Counter(r['src'] for r in recs)))
