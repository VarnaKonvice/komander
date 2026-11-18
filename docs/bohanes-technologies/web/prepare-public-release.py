"""Build only the public Bohanes Technologies site for production Cloudflare Pages.
Never expose internal /hq, /crm, prototype or repository-private assets.
Usage: python3 prepare-public-release.py /path/to/empty/output
"""
from pathlib import Path
import shutil
import sys

site = Path(__file__).resolve().parent / 'site'
out = Path(sys.argv[1]).resolve()
if out == site or site in out.parents or out.exists() and any(out.iterdir()):
    raise SystemExit('Output must be a separate empty folder.')
out.mkdir(parents=True, exist_ok=True)
public_directories = ('screens', 'native-ui', 'real-ui', 'procedure-icons')
for f in site.iterdir():
    if f.is_file() and f.suffix in ('.html', '.css', '.js', '.svg', '.png', '.jpg', '.jpeg', '.webp', '.webmanifest', '.ico', '.txt'):
        shutil.copy2(f, out/f.name)
for dirname in public_directories:
    shutil.copytree(site/dirname, out/dirname)
(out/'video-ukazky').mkdir()
for name in ('Commander-Short-V6-web.mp4', 'Commander-Short-V6-poster.jpg'):
    shutil.copy2(site/'video-ukazky'/name, out/'video-ukazky'/name)
(out/'_headers').write_text('''/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: camera=(), microphone=(), geolocation=()
/*.html
  Cache-Control: no-cache, max-age=0, must-revalidate
/manifest.webmanifest
  Cache-Control: no-cache, max-age=0, must-revalidate
''')
(out/'robots.txt').write_text('User-agent: *\nAllow: /\nSitemap: https://bohanes-technologies.cz/sitemap.xml\n')
(out/'sitemap.xml').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
''' + ''.join('  <url><loc>https://bohanes-technologies.cz/'+v+'</loc></url>\n' for v in ('','o-nas','jedu-do-lazni','pro-lazne','podrobnosti')) + '</urlset>\n')
for n in ('index.html','o-nas.html','pro-lazne.html','jedu-do-lazni.html','podrobnosti.html'):
    text=(out/n).read_text()
    assert '<meta name="robots" content="index,follow">' in text, n
    assert 'Testovací přístup:' not in text and 'loginDialog' not in text and '1234' not in text, n
    assert 'bohanes-technologies-crm.pages.dev' in text, n
for bad in ('hq','crm','koncept-8-2'):
    assert not (out/bad).exists(), bad
print(f'Prepared production-only site: {len(list(out.rglob("*")))} entries, public pages, media, robots, sitemap.')
