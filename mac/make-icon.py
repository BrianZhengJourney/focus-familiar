#!/usr/bin/env python3
"""Generate AppIcon.icns from LuLu's pixel-art data. Pure stdlib."""
import zlib, struct, os, subprocess, math

PAL = {
    'Y': 'ffd982', 'y': 'fff0c4', 'O': 'ffb043', 'C': 'fff1cf', 'N': 'c96f3f',
    'F': 'f7c778', 'T': 'e69b3d', 'B': 'ff9d6b', 'K': '2b1c12', 'W': 'ffffff',
    'H': 'f2bc61', 'M': '8a5a33',
}
BASE = [
    '....Y......YB.......',
    '...yY.....YYYy......',
    '..YYYY...YYYY..T....',
    '.YyYYYYYYYYYY.TT....',
    '.YYYYYYYYYYYYyTTT...',
    'YYYOOOOOOOOYYYYTT...',
    'YYOOOOOOOOOOYYYTT...',
    '.YOOOOOOOOOOYYTT....',
    '.YBOOCNCOOOBYYT.....',
    'YYOOOCCCOOOOYYY.....',
    'YYYOOOOOOOOYYYY.....',
    'YYYYYYYYYYYYHHH.....',
    '.YYYYYYYYYYYHH......',
    '.YFF.YHHY.FF.H......',
    '..FF......FF........',
]
EYES = [(4,6,'K'),(5,6,'K'),(4,7,'K'),(5,7,'K'),(4,6,'W'),
        (9,6,'K'),(10,6,'K'),(9,7,'K'),(10,7,'K'),(9,6,'W')]
MOUTH = [(5,10,'M'),(7,10,'M')]

def hex2rgb(h): return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

BG_TOP, BG_BOT = hex2rgb('241d4e'), hex2rgb('14102b')

def render(size):
    """rounded-rect gradient bg + centered nearest-neighbor creature"""
    px = [[None] * size for _ in range(size)]
    r = size * 0.225                      # macOS-style corner radius
    for y in range(size):
        t = y / size
        base = tuple(round(BG_TOP[i] + (BG_BOT[i] - BG_TOP[i]) * t) for i in range(3))
        for x in range(size):
            # rounded-rect mask
            dx = max(r - x, x - (size - 1 - r), 0)
            dy = max(r - y, y - (size - 1 - r), 0)
            if dx * dx + dy * dy > r * r: continue
            px[y][x] = base + (255,)
    # creature: 15 visible cols (grid 20 wide but art ends ~col 17)
    grid = [[c for c in row] for row in BASE]
    for (gx, gy, ch) in EYES + MOUTH: grid[gy][gx] = ch
    cols, rows = 17, 15
    cell = int(size * 0.72 / cols)
    ox = (size - cols * cell) // 2
    oy = (size - rows * cell) // 2 + int(size * 0.01)
    shade = lambda c: tuple(round(v * 0.55) for v in c)
    for gy in range(rows):
        for gx in range(min(cols, len(grid[gy]))):
            ch = grid[gy][gx]
            if ch == '.' or ch not in PAL: continue
            rgb = hex2rgb(PAL[ch])
            d = max(1, cell // 8)  # depth offset
            for yy in range(gy * cell + d, (gy + 1) * cell + d):
                for xx in range(gx * cell + d, (gx + 1) * cell + d):
                    X, Y = ox + xx, oy + yy
                    if 0 <= X < size and 0 <= Y < size and px[Y][X] is not None:
                        px[Y][X] = shade(rgb) + (140,)
    for gy in range(rows):
        for gx in range(min(cols, len(grid[gy]))):
            ch = grid[gy][gx]
            if ch == '.' or ch not in PAL: continue
            rgb = hex2rgb(PAL[ch])
            for yy in range(gy * cell, (gy + 1) * cell):
                for xx in range(gx * cell, (gx + 1) * cell):
                    X, Y = ox + xx, oy + yy
                    if 0 <= X < size and 0 <= Y < size and px[Y][X] is not None:
                        px[Y][X] = rgb + (255,)
    return px

def write_png(path, px):
    size = len(px)
    raw = b''
    for row in px:
        raw += b'\x00' + b''.join(bytes(p) if p else b'\x00\x00\x00\x00' for p in row)
    def chunk(tag, data):
        c = tag + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c))
    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 9))
    png += chunk(b'IEND', b'')
    open(path, 'wb').write(png)

os.chdir(os.path.dirname(os.path.abspath(__file__)))
os.makedirs('AppIcon.iconset', exist_ok=True)
for size in [16, 32, 64, 128, 256, 512, 1024]:
    write_png(f'AppIcon.iconset/icon_{size}x{size}.png', render(size))
# @2x pairs reuse the double-size renders
for size in [16, 32, 128, 256, 512]:
    src = f'AppIcon.iconset/icon_{size*2}x{size*2}.png'
    dst = f'AppIcon.iconset/icon_{size}x{size}@2x.png'
    subprocess.run(['cp', src, dst], check=True)
os.rename('AppIcon.iconset/icon_1024x1024.png', 'AppIcon.iconset/icon_512x512@2x.png') if os.path.exists('AppIcon.iconset/icon_1024x1024.png') else None
subprocess.run(['iconutil', '-c', 'icns', 'AppIcon.iconset', '-o', 'AppIcon.icns'], check=True)
subprocess.run(['rm', '-rf', 'AppIcon.iconset'])
print('AppIcon.icns written')
