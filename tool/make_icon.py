"""Génère l'icône d'OMNIA (Windows .ico et aperçus PNG), sans dépendance.

Même dessin que linux/dev.omnia.omnia.svg : le duo d'écrans. Un moniteur au
contour blanc chaud, le faisceau ambre sur son écran, et devant lui un
téléphone ambre, bouton lecture à l'écran, d'où partent deux ondes : le même
lecteur sur l'ordinateur et sur le téléphone, et le téléphone qui pilote
l'ordinateur (future télécommande mobile).

Les formes sont celles du SVG, peintes dans son ordre : chaque élément
recouvre les précédents, dégradés et opacités se mélangent à ce qui est déjà
peint. Rendu par sur-échantillonnage 4×4 (anticrénelage), PNG encodés à la
main (zlib), puis assemblés dans un .ico (entrées PNG, lues par Windows depuis
Vista).

Jusqu'à 24 px (barre de titre, barre des tâches), le dessin complet tourne à
la bouillie : ses contours font moins d'un pixel, ondes et détails du
téléphone deviennent des taches. Ces tailles reçoivent une variante
simplifiée, calée sur la grille des pixels : contours d'un pixel plein,
écran du téléphone nu (ni bouton ni barre), ni ondes ni évasement du pied.
Même composition, mêmes couleurs : c'est la même icône.

Usage : python tool/make_icon.py <dossier de sortie> [--previews] [--sizes=48,256]
  --previews : écrit aussi des aperçus PNG (16, 24, 32, 48 et 256 px).
  --sizes    : ne rend que ces tailles (aperçus compris), pour un essai rapide ;
               l'.ico, incomplet, n'est alors pas écrit.

L'icône livrée se régénère avec :
  python tool/make_icon.py windows/runner/resources
"""
import math
import os
import struct
import sys
import zlib

VELVET = (0x12, 0x0F, 0x14)      # Velours : fond, contour et écran du téléphone
VELVET_TOP = (0x21, 0x1A, 0x26)  # velours éclairci, en haut du fond
CURTAIN = (0x1C, 0x17, 0x20)     # Rideau : écran du moniteur
AMBER = (0xF2, 0xB4, 0x41)       # Projecteur : téléphone, faisceau, ondes
WHITE = (0xF3, 0xEF, 0xE6)       # Écran : blanc chaud du moniteur et de la lampe

SIZES = [16, 24, 32, 48, 64, 128, 256]
PREVIEW_SIZES = (16, 24, 32, 48, 256)
SMALL_MAX = 24  # jusqu'à cette taille, variante simplifiée
SAMPLES = 4  # sur-échantillonnage par axe


def blend(dst, src, alpha):
    """Mélange src sur dst (RGB) avec l'opacité alpha."""
    return tuple(d + (s - d) * alpha for d, s in zip(dst, src))


class RoundRect:
    """<rect> SVG aux coins arrondis (rx = ry).

    grow déplace chaque bord vers l'extérieur (vers l'intérieur s'il est
    négatif), rayon compris : ce sont les bords extérieur et intérieur d'un
    contour centré sur le tracé, comme en SVG.
    """

    def __init__(self, x, y, w, h, rx, grow=0.0):
        self.left, self.top = x - grow, y - grow
        self.right, self.bottom = x + w + grow, y + h + grow
        # Comme en SVG, le rayon ne dépasse pas la moitié du côté.
        half_side = min(self.right - self.left, self.bottom - self.top) / 2
        self.r = min(max(0.0, rx + grow), half_side)

    def hit(self, u, v):
        if u < self.left or u > self.right or v < self.top or v > self.bottom:
            return False
        r = self.r
        cx = min(max(u, self.left + r), self.right - r)
        cy = min(max(v, self.top + r), self.bottom - r)
        return (u - cx) ** 2 + (v - cy) ** 2 <= r * r


class Ring:
    """Contour d'une forme : dans son bord extérieur, hors de son bord intérieur."""

    def __init__(self, outer, inner):
        self.outer, self.inner = outer, inner

    def hit(self, u, v):
        return self.outer.hit(u, v) and not self.inner.hit(u, v)


class Polygon:
    """Polygone convexe : les triangles et le trapèze du SVG."""

    def __init__(self, *points):
        self.edges = list(zip(points, points[1:] + points[:1]))
        xs = [x for x, _ in points]
        ys = [y for _, y in points]
        self.left, self.right = min(xs), max(xs)
        self.top, self.bottom = min(ys), max(ys)

    def hit(self, u, v):
        if u < self.left or u > self.right or v < self.top or v > self.bottom:
            return False
        # Dedans : du même côté de chaque arête, quel que soit le sens du tracé.
        pos = neg = False
        for (x1, y1), (x2, y2) in self.edges:
            cross = (x2 - x1) * (v - y1) - (y2 - y1) * (u - x1)
            if cross > 0:
                pos = True
            elif cross < 0:
                neg = True
        return not (pos and neg)


class Circle:
    def __init__(self, cx, cy, r):
        self.cx, self.cy, self.r = cx, cy, r

    def hit(self, u, v):
        return (u - self.cx) ** 2 + (v - self.cy) ** 2 <= self.r * self.r


def arc_centre(x1, y1, x2, y2, r, large_arc, sweep):
    """Centre d'un arc de cercle SVG (commande A, sans rotation).

    Conversion « extrémités → centre » de la norme SVG (annexe F.6.5) pour
    rx = ry = r. Retourne (cx, cy, r, départ, étendue), angles en radians,
    y vers le bas : l'étendue est négative quand sweep vaut 0.
    """
    hx, hy = (x1 - x2) / 2, (y1 - y2) / 2
    d2 = hx * hx + hy * hy
    r = max(r, math.sqrt(d2))  # rayon trop court : la norme l'agrandit
    k = math.sqrt(max(0.0, r * r / d2 - 1))
    if large_arc == sweep:
        k = -k
    cx = k * hy + (x1 + x2) / 2
    cy = -k * hx + (y1 + y2) / 2
    start = math.atan2(y1 - cy, x1 - cx)
    extent = math.atan2(y2 - cy, x2 - cx) - start
    if sweep and extent < 0:
        extent += 2 * math.pi
    elif not sweep and extent > 0:
        extent -= 2 * math.pi
    return cx, cy, r, start, extent


class Arc:
    """Arc SVG relatif (M x y a r r 0 large sweep dx dy), au trait à bouts ronds."""

    def __init__(self, x, y, dx, dy, r, large_arc, sweep, width):
        self.x1, self.y1, self.x2, self.y2 = x, y, x + dx, y + dy
        self.cx, self.cy, self.r, self.start, self.extent = arc_centre(
            x, y, x + dx, y + dy, r, large_arc, sweep)
        self.half = width / 2
        reach = self.r + self.half
        self.left, self.right = self.cx - reach, self.cx + reach
        self.top, self.bottom = self.cy - reach, self.cy + reach

    def hit(self, u, v):
        if u < self.left or u > self.right or v < self.top or v > self.bottom:
            return False
        # Bouts ronds : un disque à chaque extrémité.
        h2 = self.half * self.half
        if ((u - self.x1) ** 2 + (v - self.y1) ** 2 <= h2
                or (u - self.x2) ** 2 + (v - self.y2) ** 2 <= h2):
            return True
        dx, dy = u - self.cx, v - self.cy
        if abs(math.hypot(dx, dy) - self.r) > self.half:
            return False
        # Angle parcouru depuis le départ, dans le sens du tracé.
        turn = math.atan2(dy, dx) - self.start
        if self.extent < 0:
            turn = -turn
        return turn % (2 * math.pi) <= abs(self.extent)


def fade(color, x0, x1, alpha0, alpha1):
    """Dégradé horizontal d'opacité, de x0 à x1 (boîte englobante de la forme)."""
    def paint(u, v):
        t = min(max((u - x0) / (x1 - x0), 0.0), 1.0)
        return color, alpha0 + (alpha1 - alpha0) * t
    return paint


def rect(x, y, w, h, rx, fill=None, stroke=None, width=0.0):
    """Couches d'un <rect> SVG : le remplissage, puis le contour centré sur le bord."""
    layers = []
    if fill:
        layers.append((RoundRect(x, y, w, h, rx), (fill, 1.0)))
    if stroke:
        half = width / 2
        ring = Ring(RoundRect(x, y, w, h, rx, half), RoundRect(x, y, w, h, rx, -half))
        layers.append((ring, (stroke, 1.0)))
    return layers


# Le dessin du SVG, élément par élément et dans le même ordre (le fond à part).
FULL = [
    # L'ordinateur : moniteur, pied et socle.
    *rect(28, 50, 172, 118, 16, fill=CURTAIN, stroke=WHITE, width=9),
    (Polygon((100, 168), (128, 168), (134, 196), (94, 196)), (WHITE, 1.0)),
    *rect(76, 194, 76, 9, 4.5, fill=WHITE),
    # À l'écran, le faisceau qui s'ouvre depuis la lampe.
    (Polygon((62, 110), (158, 76), (158, 144)), fade(AMBER, 62, 158, 0.95, 0.08)),
    (Circle(62, 110, 10), (WHITE, 1.0)),
    # Le téléphone ambre ; son contour velours le détache du moniteur.
    *rect(160, 100, 66, 116, 16, fill=AMBER, stroke=VELVET, width=9),
    *rect(171, 116, 44, 70, 6, fill=VELVET),
    (Polygon((186, 137), (204, 151), (186, 165)), (AMBER, 1.0)),
    *rect(186, 195, 14, 5, 2.5, fill=VELVET),
    # Les ondes : le téléphone pilote l'ordinateur.
    (Arc(210, 76, -30, -12, 24, 0, 0, 7), (AMBER, 1.0)),
    (Arc(221, 70, -46, -22, 38, 0, 0, 7), (AMBER, 0.55)),
]


def small_layers(size):
    """Variante simplifiée du dessin, calée sur les pixels d'une petite taille.

    Chaque bord visible du dessin complet est arrondi au pixel le plus proche,
    et chaque contour fait un pixel plein. Le pied est centré sur le moniteur
    ainsi calé, sinon il penche d'un demi-pixel.
    """
    px = 256 / size  # un pixel, en unités du dessin

    def snap(c):
        return round(c / px) * px

    def box(left, top, right, bottom, radius, grow=0.0):
        return RoundRect(left, top, right - left, bottom - top, radius, grow)

    # Moniteur : les bords extérieurs du contour blanc (28 − 4,5, etc.).
    m_left, m_top, m_right, m_bottom = snap(23.5), snap(45.5), snap(204.5), snap(172.5)
    monitor = box(m_left, m_top, m_right, m_bottom, 20.5)
    centre = (m_left + m_right) / 2

    def centred(half_width):
        left = snap(centre - half_width)
        return left, 2 * centre - left

    neck_left, neck_right = centred(14)
    base_left, base_right = centred(38)
    base_top = snap(194)

    # Téléphone : l'ambre visible (dans le contour velours), puis un pixel
    # de velours autour pour le détacher du moniteur.
    p_left, p_top, p_right, p_bottom = snap(164.5), snap(104.5), snap(221.5), snap(211.5)
    phone = box(p_left, p_top, p_right, p_bottom, 11.5)
    # Écran du téléphone : au moins un pixel d'ambre sur chaque bord.
    s_left = max(snap(171), p_left + px)
    s_right = min(snap(215), p_right - px)
    s_top = max(snap(116), p_top + px)
    s_bottom = min(snap(186), p_bottom - px)

    # Lampe : un carré de deux pixels aux coins adoucis, centré sur un coin de
    # pixel. Un disque d'un pixel de rayon ne couvrirait aucun des quatre
    # pixels en entier : la lampe tournerait au gris.
    lamp_x, lamp_y = snap(62), snap(110)
    lamp = box(lamp_x - px, lamp_y - px, lamp_x + px, lamp_y + px, px / 2)
    return [
        (monitor, (CURTAIN, 1.0)),
        (Ring(monitor, box(m_left, m_top, m_right, m_bottom, 20.5, -px)), (WHITE, 1.0)),
        (box(neck_left, m_bottom, neck_right, base_top, 0), (WHITE, 1.0)),
        (box(base_left, base_top, base_right, base_top + px, px / 2), (WHITE, 1.0)),
        (Polygon((lamp_x, lamp_y), (158, 76), (158, 144)), fade(AMBER, lamp_x, 158, 0.95, 0.08)),
        (lamp, (WHITE, 1.0)),
        (box(p_left, p_top, p_right, p_bottom, 11.5, px), (VELVET, 1.0)),
        (phone, (AMBER, 1.0)),
        (box(s_left, s_top, s_right, s_bottom, 0), (VELVET, 1.0)),
    ]


BACKGROUND = RoundRect(0, 0, 256, 256, 56)


def layers_for(size):
    """Le dessin complet, ou sa variante simplifiée jusqu'à SMALL_MAX px."""
    return small_layers(size) if size <= SMALL_MAX else FULL


def shade(u, v, layers):
    """Couleur au point (u, v) du dessin 256×256 (coordonnées SVG).

    None hors du carré arrondi du fond (transparent) ; dedans, le dégradé du
    fond puis chaque couche touchée, dans l'ordre.
    """
    if not BACKGROUND.hit(u, v):
        return None
    color = blend(VELVET_TOP, VELVET, v / 256)
    for shape, paint in layers:
        if shape.hit(u, v):
            rgb, alpha = paint(u, v) if callable(paint) else paint
            color = rgb if alpha >= 1 else blend(color, rgb, alpha)
    return color


def render(size, layers=None):
    """Image RGBA de size×size, en liste de lignes d'octets."""
    if layers is None:
        layers = layers_for(size)
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
                    s = shade(u, v, layers)
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
    for_linux = '--linux' in sys.argv
    only = [a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--sizes=')]
    sizes = [int(s) for s in only[0].split(',')] if only else SIZES
    out = args[0] if args else '.'
    os.makedirs(out, exist_ok=True)
    images = []
    for size in sizes:
        blob = png(size, render(size))
        images.append((size, blob))
        if previews and (only or size in PREVIEW_SIZES):
            with open(os.path.join(out, f'omnia-{size}.png'), 'wb') as f:
                f.write(blob)
        if for_linux:
            hicolor_dir = os.path.join(out, 'icons', 'hicolor', f'{size}x{size}', 'apps')
            os.makedirs(hicolor_dir, exist_ok=True)
            with open(os.path.join(hicolor_dir, 'dev.omnia.omnia.png'), 'wb') as f:
                f.write(blob)
            if size == 256:
                with open(os.path.join(out, 'dev.omnia.omnia.png'), 'wb') as f:
                    f.write(blob)
    if only or for_linux:
        # Un .ico privé de tailles ne doit jamais remplacer l'icône livrée.
        print('Génération terminée pour', sizes)
        return
    with open(os.path.join(out, 'app_icon.ico'), 'wb') as f:
        f.write(ico(images))
    print('icône écrite :', os.path.join(out, 'app_icon.ico'), [s for s, _ in images])



if __name__ == '__main__':
    main()
