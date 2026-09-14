"""Régénère la liste des extensions de l'installateur Windows depuis
MediaRouter, la source de vérité des formats lisibles par OMNIA.

Usage : python tool/make_installer_assoc.py
Réécrit le bloc entre « ; BEGIN EXTENSIONS » et « ; END EXTENSIONS » de
windows/installer/omnia.iss. Un test (test/packaging_test.dart) vérifie que
les deux listes restent identiques.
"""
import io
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROUTER = os.path.join(ROOT, 'lib', 'core', 'controllers', 'media_router.dart')
ISS = os.path.join(ROOT, 'windows', 'installer', 'omnia.iss')

FAMILIES = [
    ('videoExtensions', 'OMNIA.Video'),
    ('audioExtensions', 'OMNIA.Audio'),
    ('pdfExtensions', 'OMNIA.Document'),
    ('textExtensions', 'OMNIA.Document'),
]


def extensions(source, name):
    match = re.search(name + r"\s*=\s*\{(.*?)\};", source, re.S)
    if not match:
        raise SystemExit(f'liste introuvable dans media_router.dart : {name}')
    return re.findall(r"'([a-z0-9]+)'", match.group(1))


def main():
    with io.open(ROUTER, encoding='utf-8') as f:
        source = f.read()

    lines = ['; BEGIN EXTENSIONS', '; Généré par tool/make_installer_assoc.py — ne pas modifier à la main.']
    for name, progid in FAMILIES:
        for ext in extensions(source, name):
            lines.append(
                f'Root: HKA; Subkey: "Software\\Classes\\.{ext}\\OpenWithProgids"; '
                f'ValueType: none; ValueName: "{progid}"; Flags: uninsdeletevalue; Tasks: associate'
            )
            lines.append(
                f'Root: HKA; Subkey: "Software\\Classes\\Applications\\{{#AppExe}}\\SupportedTypes"; '
                f'ValueType: string; ValueName: ".{ext}"; ValueData: ""; Tasks: associate'
            )
    lines.append('; END EXTENSIONS')

    with io.open(ISS, encoding='utf-8') as f:
        iss = f.read()
    block = re.compile(r'; BEGIN EXTENSIONS.*?; END EXTENSIONS', re.S)
    if not block.search(iss):
        raise SystemExit('marqueurs BEGIN/END EXTENSIONS absents de omnia.iss')
    iss = block.sub(lambda _: '\n'.join(lines), iss)

    # Inno Setup lit l'UTF-8 avec BOM : les accents des messages restent justes.
    with io.open(ISS, 'w', encoding='utf-8-sig', newline='\r\n') as f:
        f.write(iss)
    print(f'{(len(lines) - 3) // 2} extensions écrites dans {ISS}')


if __name__ == '__main__':
    main()
