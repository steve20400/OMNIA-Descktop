#!/usr/bin/env python3
"""Fichiers d'essai du lancement réel en CI : un son et un PDF d'une page.

Usage : python tool/ci/make_samples.py <dossier>

Produit <dossier>/Musique/essai.wav et <dossier>/Documents/essai.pdf. Les deux
fichiers sont dans des dossiers distincts : OMNIA enchaîne automatiquement le
fichier suivant du dossier, et le son ne doit pas céder la place au PDF avant
que la seconde instance ne l'envoie.

Sans dépendance : le WAV est écrit par le module `wave`, le PDF à la main
(objets et table xref avec leurs vrais décalages, pour que pdfium n'ait rien
à réparer).
"""
import math
import os
import struct
import sys
import wave


def write_wav(path, seconds=30, rate=22050, frequency=440.0):
    """La 440 Hz, mono, 16 bits."""
    frames = bytearray()
    for i in range(seconds * rate):
        sample = int(12000 * math.sin(2 * math.pi * frequency * i / rate))
        frames += struct.pack('<h', sample)
    with wave.open(path, 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(bytes(frames))


def write_pdf(path):
    """Une page A4 avec deux lignes de texte en Helvetica."""
    content = (b'BT /F1 48 Tf 72 700 Td (OMNIA) Tj ET\n'
               b'BT /F1 18 Tf 72 650 Td (Document d essai de la CI) Tj ET')
    objects = [
        b'<< /Type /Catalog /Pages 2 0 R >>',
        b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        b'/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
        b'<< /Length %d >>\nstream\n' % len(content) + content + b'\nendstream',
        b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    ]
    out = bytearray(b'%PDF-1.4\n')
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b'%d 0 obj\n' % number + body + b'\nendobj\n'
    xref = len(out)
    out += b'xref\n0 %d\n' % (len(objects) + 1)
    out += b'0000000000 65535 f \n'
    for offset in offsets:
        out += b'%010d 00000 n \n' % offset
    out += b'trailer\n<< /Size %d /Root 1 0 R >>\n' % (len(objects) + 1)
    out += b'startxref\n%d\n%%%%EOF\n' % xref
    with open(path, 'wb') as f:
        f.write(bytes(out))


def main():
    if len(sys.argv) != 2:
        sys.exit('Usage : python tool/ci/make_samples.py <dossier>')
    root = sys.argv[1]
    music = os.path.join(root, 'Musique')
    documents = os.path.join(root, 'Documents')
    os.makedirs(music, exist_ok=True)
    os.makedirs(documents, exist_ok=True)
    write_wav(os.path.join(music, 'essai.wav'))
    write_pdf(os.path.join(documents, 'essai.pdf'))
    print('Fichiers d\'essai écrits dans', root)


if __name__ == '__main__':
    main()
