"""Refresh licensed reference photos; never use uploaded inventory photos as references.

Run from repository root. Commons file descriptions and licences are retained in
the catalogue. Existing files are reused. Downloads are bounded and serial.
"""
import json
from pathlib import Path
import re
import urllib.parse
import urllib.request
from io import BytesIO
from PIL import Image
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'mobile/tmp/species_sources'
CACHE.mkdir(parents=True, exist_ok=True)
UA = {'User-Agent': 'TreeTraceBot/1.0 (educational botanical reference catalogue)'}

def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=20) as response:
        return response.read()

def source_rows(name, page):
    path = CACHE / (name.replace(' ', '_') + '.json')
    if path.exists():
        return json.loads(path.read_text(encoding='utf-8'))
    soup = BeautifulSoup(fetch(page), 'html.parser')
    rows = {}
    for row in soup.select('tr'):
        cells = row.find_all(['th', 'td'], recursive=False)
        if len(cells) == 2:
            rows[cells[0].get_text(' ', strip=True)] = cells[1].get_text(' ', strip=True)
    path.write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
    return rows

def commons_photos(name, count=2):
    metadata = CACHE / (name.replace(' ', '_') + '_commons.json')
    if metadata.exists():
        return json.loads(metadata.read_text(encoding='utf-8'))
    query = urllib.parse.urlencode(dict(action='query', generator='categorymembers',
        gcmtitle='Category:' + name, gcmnamespace=6, gcmlimit=50,
        prop='imageinfo', iiprop='url|extmetadata', iiurlwidth=800, format='json'))
    data = json.loads(fetch('https://commons.wikimedia.org/w/api.php?' + query))
    photos = []
    pages = list(data.get('query', {}).get('pages', {}).values())
    latin = name.lower().replace(' ', '_')
    pages.sort(key=lambda page: latin not in page['title'].lower())
    failures = 0
    for page in pages:
        title = page['title']
        if not title.lower().endswith(('.jpg', '.jpeg', '.png')):
            continue
        if re.search(r'herbarium|distribution|map\b|illustration|drawing|timber|poles|seedling|museum|cunninghamiana|hybrid', title, re.I):
            continue
        info = page.get('imageinfo', [{}])[0]
        meta = info.get('extmetadata', {})
        clean = lambda key: BeautifulSoup(meta.get(key, {}).get('value', ''), 'html.parser').get_text(' ', strip=True)
        license_name = clean('LicenseShortName')
        if not (license_name.startswith(('CC BY', 'CC0')) or license_name in ('Public domain', 'PDM')):
            continue
        if 'NC' in license_name or 'ND' in license_name:
            continue
        slug = re.sub('[^a-z0-9]+', '_', name.lower()).strip('_')
        filename = f'{slug}_{len(photos)+1}.jpg'
        dest = ROOT / 'mobile/assets/reference_photos' / filename
        try:
            raw = fetch('https://commons.wikimedia.org/wiki/Special:FilePath/' + urllib.parse.quote(title[5:]) + '?width=800')
            im = Image.open(BytesIO(raw))
            im.verify()
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(raw)
        except Exception as exc:
            print(json.dumps({'download_failed': title, 'reason': str(exc)}), flush=True)
            failures += 1
            if failures >= 3:
                break
            continue
        photos.append(dict(url=info.get('thumburl') or info['url'],
            asset='assets/reference_photos/' + filename,
            caption=name + ' - botanical reference', author=clean('Artist') or clean('Credit'),
            license=license_name, license_url=clean('LicenseUrl'),
            source_url=info['descriptionurl'], scientific_name=name,
            description=clean('ImageDescription')))
        if len(photos) >= count:
            break
    metadata.write_text(json.dumps(photos, ensure_ascii=False, indent=2), encoding='utf-8')
    return photos

if __name__ == '__main__':
    import sys
    if sys.argv[1] == 'sources':
        pages = json.loads((CACHE / 'pages.json').read_text())
        from concurrent.futures import ThreadPoolExecutor
        def work(item):
            name, url = item
            try:
                rows = source_rows(name, url)
                print(json.dumps({'name': name, 'fields': {k:v for k,v in rows.items() if k in ('Family Name:', 'Foliage', 'Flowers', 'Fruit', 'Fruits', 'Similar', 'Native Distribution', 'Others - Plant Morphology')}}), flush=True)
            except Exception as exc:
                print(json.dumps({'name': name, 'error': str(exc)}), flush=True)
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(work, pages.items()))
    else:
        from concurrent.futures import ThreadPoolExecutor
        def photos(name):
            try:
                result = commons_photos(name)
                print(json.dumps({'name':name, 'count':len(result)}), flush=True)
            except Exception as exc:
                print(json.dumps({'name':name, 'error':str(exc)}), flush=True)
        with ThreadPoolExecutor(max_workers=3) as pool:
            list(pool.map(photos, sys.argv[1:]))
