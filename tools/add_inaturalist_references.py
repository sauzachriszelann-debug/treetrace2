"""Fetch an openly licensed, taxon-matched reference from iNaturalist.

Alternative photo provider when Commons is unavailable. No NC/ND photos are used.
The taxon name must match exactly (or the accepted Indian mast tree synonym).
Review the resulting contact sheet before exporting the catalogue.
"""
import json
import re
import sys
import urllib.parse
from build_species_references import CACHE, ROOT, fetch
from PIL import Image
from io import BytesIO

def add(name):
    meta = CACHE / (name.replace(' ', '_') + '_photos.json')
    if meta.exists():
        return len(json.loads(meta.read_text(encoding='utf-8')))
    query = urllib.parse.urlencode({'q':name, 'rank':'species', 'per_page':3})
    data = json.loads(fetch('https://api.inaturalist.org/v1/taxa?' + query))
    taxa = [t for t in data.get('results',[]) if t.get('name','').lower() == name.lower()]
    if name == 'Polyalthia longifolia':
        taxa = [t for t in data.get('results',[]) if t.get('name','').lower() in ('polyalthia longifolia','monoon longifolium')]
    if not taxa:
        raise ValueError('No exact taxon match')
    taxon = taxa[0]
    candidates = [taxon['default_photo']] if taxon.get('default_photo') else []
    if not candidates or candidates[0].get('license_code') not in ('cc0','cc-by','cc-by-sa'):
        query = urllib.parse.urlencode(dict(taxon_id=taxon['id'], photos='true',
            photo_license='cc0,cc-by,cc-by-sa', quality_grade='research', per_page=3))
        observations = json.loads(fetch('https://api.inaturalist.org/v1/observations?' + query))
        candidates = [photo for obs in observations.get('results',[]) for photo in obs.get('photos',[])]
    for photo in candidates:
        license_code = photo.get('license_code')
        if license_code not in ('cc0','cc-by','cc-by-sa'):
            continue
        url = photo.get('medium_url') or photo.get('url','').replace('/square.', '/medium.')
        if not url.startswith('https://'):
            continue
        raw = fetch(url)
        image = Image.open(BytesIO(raw)); image.verify()
        filename = re.sub('[^a-z0-9]+','_',name.lower()) + '_inat.jpg'
        path = ROOT / 'mobile/assets/reference_photos' / filename
        path.write_bytes(raw)
        result = [dict(url=url, asset='assets/reference_photos/'+filename,
            caption=name+' - botanical reference', scientific_name=name,
            author=photo.get('attribution_name') or photo.get('attribution',''),
            license={'cc0':'CC0','cc-by':'CC BY 4.0','cc-by-sa':'CC BY-SA 4.0'}[license_code],
            license_url='https://creativecommons.org/publicdomain/zero/1.0/' if license_code == 'cc0' else
                'https://creativecommons.org/licenses/'+license_code[3:]+'/4.0/',
            source_url='https://www.inaturalist.org/photos/'+str(photo['id']))]
        meta.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
        return 1
    return 0

if __name__ == '__main__':
    from concurrent.futures import ThreadPoolExecutor
    def work(name):
        try:
            print(json.dumps({'name':name,'photos':add(name)}),flush=True)
        except Exception as exc:
            print(json.dumps({'name':name,'error':str(exc)}),flush=True)
    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(work,sys.argv[1:]))
