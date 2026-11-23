"""Build original crest-inspired SVG artwork and offline PNGs (requires rsvg-convert)."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
# Each symbol is drawn on a 96-unit canvas, with ample transparent clearance.
ART = {
# Bold, familiar silhouettes; details stay at least one pixel wide at 24 px.
'wood': '''<path fill="{dark}" d="M26 23h43c13 0 21 11 21 25S82 75 69 75H26Z"/><path fill="{mid}" d="M26 23h43c11 0 18 8 20 18H26Z"/><ellipse fill="{light}" cx="26" cy="49" rx="20" ry="26"/><ellipse fill="{mid}" cx="26" cy="49" rx="10" ry="16"/><path fill="none" stroke="{light}" stroke-width="4" d="M51 35h20M52 59h25"/>''',
'brick': '''<path fill="{mid}" d="M6 40h84v43H6Z"/><path fill="{light}" d="M21 11h54v29H21Z"/><path stroke="{dark}" stroke-width="6" d="M6 61h84M48 11v29M34 40v21m29 0v22"/>''',
'wheat': '''<path stroke="{mid}" stroke-width="8" d="M48 87V22"/><path fill="{light}" d="M48 27C35 20 38 9 48 3c10 6 13 17 0 24Z"/><g fill="{mid}"><path d="M43 44C24 43 19 30 22 18c17 2 23 12 21 26Z"/><path d="M53 44c19-1 24-14 21-26-17 2-23 12-21 26Z"/><path d="M43 64C23 63 18 50 21 38c18 2 24 12 22 26Z"/><path d="M53 64c20-1 25-14 22-26-18 2-24 12-22 26Z"/><path d="M43 81C25 80 21 68 23 58c16 2 22 11 20 23Z"/><path d="M53 81c18-1 22-13 20-23-16 2-22 11-20 23Z"/></g>''',
'wool': '''<path fill="{dark}" d="M25 61h11v23H25Zm31 0h11v23H56Z"/><path fill="{light}" d="M22 66C10 66 6 54 13 46 5 36 13 24 24 25 27 13 41 11 48 19 58 10 72 17 72 29 84 29 89 42 81 50 86 63 73 73 62 68 52 77 39 74 34 68 29 71 24 70 22 66Z"/><path fill="none" stroke="{mid}" stroke-width="4" d="M22 43q-4-9 6-12m8-5q6-7 12 0M20 55q1 8 10 7"/><path fill="{mid}" d="M59 38 47 32q-5 13 10 17m19-11 12-6q5 13-10 17"/><path fill="{dark}" d="M59 36q9-6 18 0l2 17q0 15-11 15T57 53Z"/><path fill="{light}" stroke="none" d="M59 34q9-10 18 0v7q-5 3-9-1-5 4-9 0Z"/><g fill="{light}" stroke="none"><circle cx="63" cy="49" r="2.4"/><circle cx="73" cy="49" r="2.4"/></g><path fill="none" stroke="{mid}" stroke-width="3" d="m65 59 3 2 3-2"/>''',
'ore': '''<path fill="{mid}" d="m8 65 12-29 24-18 27 7 17 33-9 23-53 3Z"/><path fill="{light}" d="m20 36 24-18 27 7-17 21Z"/><path fill="{dark}" d="m54 46 17-21 17 33-9 23-25 3Z"/><path fill="{mid}" d="m8 65 46-19v38l-28 0Z"/>''',
'paper': '''<path fill="{light}" d="M20 6h39l22 22v62H20Z"/><path fill="{mid}" d="M59 6v22h22Z"/><path stroke="{dark}" stroke-width="5" d="M33 44h34M33 58h34M33 72h23"/>''',
'cloth': '''<path fill="{mid}" d="M33 9 9 22l-6 25 20 7 6-13v47h38V41l6 13 20-7-6-25L63 9Q48 26 33 9Z"/><path fill="{light}" d="M33 9q15 17 30 0l-4 19H37Z"/><path stroke="{light}" stroke-width="4" d="M38 76h20"/>''',
'coin': '''<circle fill="{dark}" cx="48" cy="51" r="40"/><circle fill="{mid}" cx="48" cy="46" r="40"/><circle fill="none" stroke="{light}" stroke-width="5" cx="48" cy="46" r="30"/>''',
}
# Resource colours remain distinct in every theme; shared gold accents connect to the crest.
BANNER = [('58331d','a86835','f2c58a'),('8e2923','ed6549','ffad7c'),('a46716','f2bb31','fff09b'),('263543','aabdc4','fff8e6'),('52504d','92918a','d7d5c9'),('716657','cec5a6','ffffe9'),('522472','b35dd1','f3b6ff'),('9c5b0b','efaf21','fff080')]
PALETTES = {
'banner': BANNER,
# Jewel and cool mineral variants retain colour cues rather than flattening resources to one hue.
 'treasury': [('63381b','c07f35','ffdda0'),('9a3027','ee7951','ffd2a0'),('a96a0a','ffd04b','fff6b3'),('453937','ceba94','fff5d6'),('595148','a39887','e6dbca'),('8e7541','e6cc8a','fff7db'),('66246c','d477c2','ffd2ef'),('a66508','ffc53e','ffffb5')],
 'carved-stone': [('3b5150','739e89','cce6bc'),('6b3d41','c1817c','f4c5b8'),('706047','c5b479','fff0b8'),('344a5c','a4bbc6','ffffff'),('4f5553','929b96','dbe2db'),('616b69','c0d2c7','f5fff2'),('57436e','a18ec5','e8d5ff'),('806a39','cbbb71','fff5bd')],
}
for pack, palettes in PALETTES.items():
    folder = ROOT / 'assets/icons' / pack
    folder.mkdir(exist_ok=True)
    for (name, art), (dark, mid, light) in zip(ART.items(), palettes):
        svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96"><g stroke="#172c36" stroke-width="2.8" stroke-linejoin="round" stroke-linecap="round">' + art.format(dark='#'+dark, mid='#'+mid, light='#'+light) + '</g></svg>'
        source = folder / f'{name}.svg'
        source.write_text(svg+'\n')
        subprocess.run(['rsvg-convert', '-w', '192', '-h', '192', '-o', str(folder / f'{name}.png'), str(source)], check=True)
    (folder / 'LICENSE.txt').write_text('Original Stone & Banner resource artwork. Copyright 2026 Stone & Banner contributors. All rights reserved.\n')
