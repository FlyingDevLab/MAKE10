import csv, json, collections, sys
SP=sys.argv[1]
raw=json.load(open(f'{SP}/wd/raw.json',encoding='utf-8'))
# item -> info
info=collections.defaultdict(lambda:{'iata':set(),'icao':set(),'cc':set(),'labels':{},'city':collections.defaultdict(dict)})
for r in raw:
    it=info[r['item']]
    it['iata'].add(r['iata'])
    if 'icao' in r: it['icao'].add(r['icao'])
    if 'cc' in r: it['cc'].add(r['cc'])
    if 'label' in r: it['labels'][r['lang']]=r['label']
    if 'clabel' in r: it['city'][r['city']][r['clang']]=r['clabel']
by_iata=collections.defaultdict(list)
for k,v in info.items():
    for c in v['iata']: by_iata[c].append((k,v))

PREF={'ja':['ja'],'en':['en'],'zh-Hans':['zh-hans','zh-cn','zh'],'zh-Hant':['zh-hant','zh-tw','zh-hk'],
      'de':['de'],'fr':['fr'],'nl':['nl'],'es':['es'],'it':['it'],'pt-BR':['pt-br','pt'],'ko':['ko'],
      'th':['th'],'vi':['vi'],'id':['id'],'hi':['hi']}
LOCAL={'JP':['ja'],'CN':['zh-Hans'],'TW':['zh-Hant'],'HK':['zh-Hant'],'MO':['zh-Hant'],
 'DE':['de'],'AT':['de'],'LI':['de'],'CH':['de','fr','it'],'FR':['fr'],'MC':['fr'],
 'GP':['fr'],'MQ':['fr'],'RE':['fr'],'PF':['fr'],'NC':['fr'],'GF':['fr'],'YT':['fr'],'PM':['fr'],'WF':['fr'],'BL':['fr'],'MF':['fr'],
 'BE':['nl','fr'],'LU':['fr','de'],'NL':['nl'],'SR':['nl'],'AW':['nl'],'CW':['nl'],'SX':['nl'],'BQ':['nl'],
 'ES':['es'],'MX':['es'],'AR':['es'],'CO':['es'],'CL':['es'],'PE':['es'],'VE':['es'],'EC':['es'],'BO':['es'],'PY':['es'],'UY':['es'],
 'CR':['es'],'PA':['es'],'GT':['es'],'HN':['es'],'NI':['es'],'SV':['es'],'DO':['es'],'CU':['es'],'PR':['es'],'GQ':['es'],
 'IT':['it'],'SM':['it'],'BR':['pt-BR'],'PT':['pt-BR'],'AO':['pt-BR'],'MZ':['pt-BR'],'CV':['pt-BR'],'GW':['pt-BR'],'ST':['pt-BR'],'TL':['pt-BR'],
 'KR':['ko'],'KP':['ko'],'TH':['th'],'VN':['vi'],'ID':['id'],'IN':['hi'],'CA':['fr'],'HT':['fr'],
 'SN':['fr'],'CI':['fr'],'CM':['fr'],'ML':['fr'],'BF':['fr'],'NE':['fr'],'TD':['fr'],'CF':['fr'],'CG':['fr'],'CD':['fr'],
 'GA':['fr'],'BJ':['fr'],'TG':['fr'],'GN':['fr'],'MG':['fr'],'DJ':['fr'],'KM':['fr'],'BI':['fr'],'RW':['fr'],'SC':['fr'],'VU':['fr']}
def pick(d,lang):
    for k in PREF[lang]:
        if k in d: return d[k]
    return None

rows=[r for r in csv.DictReader(open(f'{SP}/airports.csv',encoding='utf-8'))
      if r['iata_code'].strip() and r['type']!='closed' and r['scheduled_service']=='yes']
out=[]; stats=collections.Counter()
seen=set()
for r in rows:
    code=r['iata_code'].strip(); cc=r['iso_country']
    if code in seen: stats['dup_iata']+=1; continue
    seen.add(code)
    cands=by_iata.get(code,[])
    best=None
    if cands:
        def score(kv):
            k,v=kv
            return ((r['icao_code'] in v['icao']) if r['icao_code'] else 0, cc in v['cc'], 'ja' in v['labels'], len(v['labels']))
        best=max(cands,key=score)[1]
        if not ((r['icao_code'] and r['icao_code'] in best['icao']) or cc in best['cc']):
            best=None; stats['wd_mismatch']+=1
    else: stats['wd_missing']+=1
    labels=best['labels'] if best else {}
    city={}
    if best and best['city']:
        # 一番ラベルの多い都市を使う
        city=max(best['city'].values(),key=len)
    names={'en': pick(labels,'en') or r['name']}
    cities={'en': pick(city,'en') or r['municipality'] or None}
    ja=pick(labels,'ja')
    if ja: names['ja']=ja; stats['ja']+=1
    cj=pick(city,'ja')
    if cj: cities['ja']=cj
    for lang in LOCAL.get(cc,[]):
        if lang=='ja': continue
        v=pick(labels,lang)
        if v: names[lang]=v; stats['local']+=1
        c=pick(city,lang)
        if c: cities[lang]=c
    out.append({'code':code,'cc':cc,'names':names,'cities':cities,'type':r['type'],'local_langs':LOCAL.get(cc,[])})
json.dump(out,open(f'{SP}/wd/airports.json','w'),ensure_ascii=False,indent=1)
print(len(out),dict(stats))
c=collections.Counter(a['cc'] for a in out)
for k in ['JP','CN','DE','FR','US','NL']:
    a=[x for x in out if x['cc']==k]
    print(k,len(a),'ja',sum('ja' in x['names'] for x in a),'local',sum(all(l in x['names'] for l in x['local_langs']) for x in a))
print('world ja',sum('ja' in x['names'] for x in out),'/',len(out))
