"""Génère l'icône d'OMNIA (Windows .ico et aperçus PNG), sans dépendance.

Même dessin que linux/dev.omnia.omnia.svg : carré aux coins doux couleur
velours, halo ambre, faisceau qui s'ouvre depuis la lampe, trait du temps
écoulé. Rendu par sur-échantillonnage 4×4 (anticrénelage), PNG encodés à la
main (zlib), puis assemblés dans un .ico (entrées PNG, lues par Windows
depuis Vista).

Usage : python tool/make_icon.py <dossier de sortie> [--previews]
  --previews : écrit aussi des aperçus PNG (48 et 256 px) pour vérifier le rendu.

L'icône livrée se régénère avec :
  python tool/make_icon.py windows/runner/resources
"""
import math
import os
import struct
import sys
import zlib

VELVET = (0x12, 0x0F, 0x14)
AMBER = (0xF2, 0xB4, 0x41)
LAMP = (0xF3, 0xEF, 0xE6)
SEAM = (0x2E, 0x27, 0x34)

SIZES = [16, 24, 32, 48, 64, 128, 256]
SAMPLES = 4  # sur-échantillonnage par axe


def blend(dst, src, alpha):
    """Mélange src sur dst (RGB) avec l'opacité alpha."""
    return tuple(d + (s - d) * alpha for d, s in zip(dst, src))


def in_rounded_rect(x, y, size, radius):
    """Vrai si (x, y) est dans le carré [0, size] aux coins arrondis."""
    rx = min(max(x, radius), size - radius)
    ry = min(max(y, radius), size - radius)
    return (x - rx) ** 2 + (y - ry) ** 2 <= radius ** 2


def in_triangle(px, py, a, b, c):
    def sign(p1, p2, p3):
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
    d1 = sign((px, py), a, b)
    d2 = sign((px, py), b, c)
    d3 = sign((px, py), c, a)
    has_neg = d1 < 0 or d2 < 0 or d3 < 0
    has_pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (has_neg and has_pos)


def shade(u, v):
    """Couleur et opacité au point (u, v) du dessin 256×256 (coordonnées SVG).

    Retourne (rgb, alpha), alpha = 0 hors du carré arrondi.
    """
    if not in_rounded_rect(u, v, 256, 56):
        return None
    color = VELVET

    # Halo radial ambre, centré sur la lampe (34 % / 50 %).
    dx, dy = u - 0.34 * 256, v - 0.5 * 256
    glow = max(0.0, 1 - math.hypot(dx, dy) / (0.62 * 256)) * 0.55
    color = blend(color, AMBER, glow * 0.55)

    # Faisceau : triangle lampe → bord droit, dégradé horizontal.
    if in_triangle(u, v, (78, 128), (218, 58), (218, 198)):
        t = (u - 78) / (218 - 78)
        color = blend(color, AMBER, 0.95 + (0.10 - 0.95) * t)

    # Lampe : halo puis cœur blanc chaud.
    d = math.hypot(u - 78, v - 128)
    if d <= 26:
        color = blend(color, AMBER, 0.30)
    if d <= 15:
        color = LAMP

    # Trait du temps écoulé sous le faisceau.
    if 196 <= v <= 202 and 52 <= u <= 204:
        color = AMBER if u <= 138 else SEAM

    return color


def render(size):
    """Image RGBA de size×size, en liste de lignes d'octets."""
    rows = []
    scale = 256 / size
    for y in range(size):
        row = bytearray()
        for x in range(size):
            acc = [0.0, 0.0, 0.0]
            covered = 0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    u = (x + (sx + 0.5) / SAMPLES) * scale
                    v = (y + (sy + 0.5) / SAMPLES) * scale
                    s = shade(u, v)
                    if s is None:
                        continue
                    covered += 1
                    for i in range(3):
                        acc[i] += s[i]
            n = SAMPLES * SAMPLES
            if covered == 0:
                row += bytes((0, 0, 0, 0))
            else:
                rgb = [round(c / covered) for c in acc]
                row += bytes((*rgb, round(255 * covered / n)))
        rows.append(bytes(row))
    return rows


def png(size, rows):
    raw = b''.join(b'\x00' + r for r in rows)

    def chunk(kind, data):
        body = kind + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header)
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def ico(images):
    """images : liste de (taille, octets PNG)."""
    header = struct.pack('<HHH', 0, 1, len(images))
    offset = 6 + 16 * len(images)
    entries = b''
    data = b''
    for size, blob in images:
        dim = 0 if size >= 256 else size  # 0 signifie 256 dans le format ICO
        entries += struct.pack('<BBBBHHII', dim, dim, 0, 0, 1, 32, len(blob), offset)
        data += blob
        offset += len(blob)
    return header + entries + data


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    previews = '--previews' in sys.argv
    out = args[0] if args else '.'
    os.makedirs(out, exist_ok=True)
    images = []
    for size in SIZES:
        blob = png(size, render(size))
        images.append((size, blob))
        if previews and size in (48, 256):
            with open(os.path.join(out, f'omnia-{size}.png'), 'wb') as f:
                f.write(blob)
    with open(os.path.join(out, 'app_icon.ico'), 'wb') as f:
        f.write(ico(images))
    print('icône écrite :', os.path.join(out, 'app_icon.ico'), [s for s, _ in images])


if __name__ == '__main__':
    main()
