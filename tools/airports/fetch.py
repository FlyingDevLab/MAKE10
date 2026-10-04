import csv, json, time, urllib.request, urllib.parse, os, sys
SP=sys.argv[1]
rows=[r for r in csv.DictReader(open(f'{SP}/airports.csv',encoding='utf-8'))
      if r['iata_code'].strip() and r['type']!='closed' and r['scheduled_service']=='yes']
codes=sorted({r['iata_code'].strip() for r in rows})
print('codes',len(codes))
LANGS='"ja","en","zh-hans","zh-cn","zh","zh-hant","zh-tw","zh-hk","de","fr","nl","es","it","pt-br","pt","ko","th","vi","id","hi"'
def q(query):
    url='https://query.wikidata.org/sparql?'+urllib.parse.urlencode({'query':query,'format':'json'})
    for attempt in range(4):
        try:
            req=urllib.request.Request(url,headers={'User-Agent':'MAKE10-quiz-data/1.0 (masakato100@gmail.com)','Accept':'application/sparql-results+json'})
            return json.load(urllib.request.urlopen(req,timeout=120))['results']['bindings']
        except Exception as e:
            print('retry',e); time.sleep(5*(attempt+1))
    raise SystemExit('failed')
out=[]
B=300
for i in range(0,len(codes),B):
    vals=' '.join('"%s"'%c for c in codes[i:i+B])
    res=q(f'''SELECT ?item ?iata ?icao ?cc ?city ?lang ?label ?clang ?clabel WHERE {{
      VALUES ?iata {{ {vals} }}
      ?item wdt:P238 ?iata .
      OPTIONAL {{ ?item wdt:P239 ?icao }}
      OPTIONAL {{ ?item wdt:P17/wdt:P297 ?cc }}
      {{ ?item rdfs:label ?label BIND(lang(?label) AS ?lang) FILTER(?lang IN ({LANGS})) }}
      UNION
      {{ ?item wdt:P931 ?city . ?city rdfs:label ?clabel BIND(lang(?clabel) AS ?clang) FILTER(?clang IN ({LANGS})) }}
    }}''')
    out+= [{k:v['value'] for k,v in r.items()} for r in res]
    print(i,len(res)); time.sleep(1)
json.dump(out,open(f'{SP}/wd/raw.json','w'),ensure_ascii=False)
print('rows',len(out))
