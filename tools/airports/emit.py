import json, re, sys, collections
SP, JSONDIR = sys.argv[1], sys.argv[2]
LANGS=['ja','en','de','es','fr','hi','id','it','ko','nl','pt-BR','th','vi','zh-Hans','zh-Hant']
air=json.load(open(f'{SP}/wd/airports.json',encoding='utf-8'))

def clean(lang, s):
    if s is None: return None
    s=s.strip()
    if lang=='ja' and re.search('[A-Za-z]{3,}', s): return None      # 英語まじりの日本語ラベルは使わない
    if lang in ('fr','es','it','pt-BR','nl','de','id','vi') and s[:1].islower(): s=s[:1].upper()+s[1:]
    return s

def contains_city(lang, name, city):
    core=re.sub('[市町村区郡]$','',city) if lang in ('ja','zh-Hans','zh-Hant') else city
    return core.lower() in name.lower()

def entry(a, with_city):
    names={}
    for lang in ['ja','en']+a['local_langs']:
        n=clean(lang, a['names'].get(lang))
        if not n: continue
        if with_city:
            c=clean(lang, a['cities'].get(lang))
            if c and not contains_city(lang, n, c):
                n = f'{n}（{c}）' if lang in ('ja','zh-Hans','zh-Hant') else f'{n} ({c})'
        names[lang]=n
    return {'display':a['code'],'name':{k:names[k] for k in LANGS if k in names}}

def write(gid, items, meta_from=None, title=None, icon=None):
    path=f'{JSONDIR}/{gid}.json'
    try:
        raw=open(path,encoding='utf-8').read(); d=json.loads(raw); nl=raw.endswith('\n')
    except FileNotFoundError:
        base=json.load(open(f'{JSONDIR}/{meta_from}.json',encoding='utf-8'))
        d={'gameId':gid,'group':base['group'],'title':None,'icon':None,'displayStyle':'code','items':[]}; nl=True
    if title: d['title']=title
    if icon: d['icon']=icon
    d['items']=items
    open(path,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False,indent=2)+('\n' if nl else ''))
    print(gid,len(items))

def T(*v): return dict(zip(LANGS,v))
# 日本: 日本語名は、いまの日本語名（愛称つき）を優先する。英語名は OurAirports の名前（いまの正式な英語名に近い）
import csv
old_jp={it['display']:it['name']['ja'] for it in json.load(open(f'{JSONDIR}/airportJapan.json'))['items']}
oa_en={r['iata_code']:r['name'].split(' / ')[0] for r in csv.DictReader(open(f'{SP}/airports.csv',encoding='utf-8'))
       if r['iso_country']=='JP' and r['iata_code']}
jp=[]
for a in air:
    if a['cc']!='JP': continue
    e=entry(a,False)
    if a['code'] in old_jp: e['name']['ja']=old_jp[a['code']]
    e['name']['en']=oa_en[a['code']]
    e['name']={k:e['name'][k] for k in LANGS if k in e['name']}
    jp.append(e)
write('airportJapan', jp)

countries=[
 ('airportChina',['CN'],'🇨🇳',T('中国の空港コード','China Airports','Chinesische Flughäfen','Aeropuertos de China',"Aéroports de Chine",'चीन हवाई अड्डे','Bandara Tiongkok','Aeroporti della Cina','중국 공항','Chinese luchthavens','Aeroportos da China','สนามบินในจีน','Sân bay Trung Quốc','中国机场','中國機場')),
 ('airportGermany',['DE'],'🇩🇪',T('ドイツの空港コード','Germany Airports','Deutsche Flughäfen','Aeropuertos de Alemania',"Aéroports d'Allemagne",'जर्मनी हवाई अड्डे','Bandara Jerman','Aeroporti della Germania','독일 공항','Duitse luchthavens','Aeroportos da Alemanha','สนามบินในเยอรมนี','Sân bay Đức','德国机场','德國機場')),
 ('airportFrance',['FR'],'🇫🇷',T('フランスの空港コード','France Airports','Französische Flughäfen','Aeropuertos de Francia','Aéroports de France','फ़्रांस हवाई अड्डे','Bandara Prancis','Aeroporti della Francia','프랑스 공항','Franse luchthavens','Aeroportos da França','สนามบินในฝรั่งเศส','Sân bay Pháp','法国机场','法國機場')),
 ('airportUSA',['US'],'🇺🇸',T('アメリカの空港コード','USA Airports','US-Flughäfen','Aeropuertos de EE. UU.','Aéroports des États-Unis','अमेरिका हवाई अड्डे','Bandara Amerika Serikat','Aeroporti degli Stati Uniti','미국 공항','Amerikaanse luchthavens','Aeroportos dos EUA','สนามบินในสหรัฐอเมริกา','Sân bay Hoa Kỳ','美国机场','美國機場')),
 ('airportNetherlands',['NL','AW','CW','SX','BQ'],'🇳🇱',T('オランダの空港コード','Netherlands Airports','Niederländische Flughäfen','Aeropuertos de los Países Bajos','Aéroports des Pays-Bas','नीदरलैंड हवाई अड्डे','Bandara Belanda','Aeroporti dei Paesi Bassi','네덜란드 공항','Nederlandse luchthavens','Aeroportos dos Países Baixos','สนามบินในเนเธอร์แลนด์','Sân bay Hà Lan','荷兰机场','荷蘭機場')),
]
for gid,ccs,icon,title in countries:
    write(gid,[entry(a,False) for a in air if a['cc'] in ccs],'airportJapan',title,icon)
write('airportWorld',[entry(a,True) for a in air])
