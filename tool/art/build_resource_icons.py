"""Build original crest-inspired SVG artwork and offline PNGs (requires rsvg-convert)."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
# Each symbol is drawn on a 96-unit canvas, with ample transparent clearance.
ART = {
# Bold, familiar silhouettes; details stay at least one pixel wide at 24 px.
'wood': '''<path fill="{dark}" d="M26 23h43c13 0 21 11 21 25S82 75 69 75H26Z"/><path fill="{mid}" d="M26 23h43c11 0 18 8 20 18H26Z"/><ellipse fill="{light}" cx="26" cy="49" rx="20" ry="26"/><ellipse fill="{mid}" cx="26" cy="49" rx="10" ry="16"/><path fill="none" stroke="{light}" stroke-width="4" d="M51 35h20M52 59h25"/>''',
'brick': '''<!-- One straight wall with three even courses and staggered mortar joints. --><path fill="{light}" d="M8 22 16 14H88L80 22Z"/><path fill="{dark}" d="m80 22 8-8v60l-8 8Z"/><path fill="{mid}" d="M8 22h72v60H8Z"/><path fill="none" d="M8 42h72M8 62h72M44 22v20M26 42v20M62 42v20M44 62v20"/><path fill="none" stroke="{light}" stroke-width="3" d="M14 28h24m12 0h24M14 48h6m12 0h24m12 0h6M14 68h24m12 0h24"/>''',
'wheat': '''<path stroke="{mid}" stroke-width="8" d="M48 87V22"/><path fill="{light}" d="M48 27C35 20 38 9 48 3c10 6 13 17 0 24Z"/><g fill="{mid}"><path d="M43 44C24 43 19 30 22 18c17 2 23 12 21 26Z"/><path d="M53 44c19-1 24-14 21-26-17 2-23 12-21 26Z"/><path d="M43 64C23 63 18 50 21 38c18 2 24 12 22 26Z"/><path d="M53 64c20-1 25-14 22-26-18 2-24 12-22 26Z"/><path d="M43 81C25 80 21 68 23 58c16 2 22 11 20 23Z"/><path d="M53 81c18-1 22-13 20-23-16 2-22 11-20 23Z"/></g>''',
'wool': '''<!-- Broad fleece, short legs and a drooping face keep the sheep readable at 24 px. --><path fill="{mid}" d="M27 61h9v21h-9Zm25 0h9v21h-9Z"/><path fill="{dark}" d="M20 62h10v24H20Zm35 0h10v24H55Z"/><path fill="{light}" d="M15 60C6 57 6 46 13 41 8 32 16 23 26 25 29 14 43 12 50 21 60 16 71 22 71 32 81 35 83 46 76 53 80 64 68 73 58 69 52 77 39 76 33 70 25 75 15 69 15 60Z"/><path fill="none" stroke="{mid}" stroke-width="3.5" d="M19 37q-1-7 7-7m8-3q7-6 13 0M17 52q-1 8 7 9m10 3q6 7 13 1"/><path fill="{mid}" d="M63 37q-10-11-17-5 1 11 15 14m15-9q7-11 15-7-1 12-13 15"/><path fill="{dark}" d="M62 36q7-4 14 1l3 19c1 10-3 18-11 18-7 0-12-7-11-15Z"/><path fill="{light}" d="M57 34q-1-8 7-8 5-6 10 0 9 0 8 8l-5 8q-5 0-9-4-4 4-9 3Z"/><g fill="{light}" stroke="none"><ellipse cx="63" cy="51" rx="2" ry="2.7"/><ellipse cx="73" cy="51" rx="2" ry="2.7"/></g><path fill="none" stroke="{mid}" stroke-width="3" d="m65 65 3 1 3-1"/>''',
'ore': '''<!-- A tall mountain with a summit face and a few broad rocky ridges. --><path fill="{mid}" d="M12 86 44 9 53 5 84 86Z"/><path fill="{light}" d="M12 86 44 9 53 5 42 58Z"/><path fill="{dark}" d="M53 5 84 86H54L42 58Z"/><path fill="{light}" d="m44 9 9-4 10 27-10-7-7 10-6-6Z"/><path fill="none" stroke="{mid}" stroke-width="3" d="m62 49 7 16-7-4 5 13"/><path fill="none" stroke="{mid}" stroke-width="2.8" d="m31 48-7 18"/>''',
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
