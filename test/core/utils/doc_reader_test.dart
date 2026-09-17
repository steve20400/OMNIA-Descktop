import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/utils/doc_reader.dart';

void main() {
  group('DocReader', () {
    test('RTF parsing extrait le texte sans les balises ni mots de contrôle', () async {
      const rtf = r'''{\rtf1\ansi\deff0
{\fonttbl{\f0\fnil\fcharset0 Arial;}}
\viewkind4\uc1\pard\lang1036\b Titre du document\b0\par
Ceci est un paragraphe avec du texte standard.\par
}''';
      final file = File('${Directory.systemTemp.path}/test_doc.rtf');
      await file.writeAsString(rtf);
      try {
        final text = await DocReader.read(file.path);
        expect(text, contains('Titre du document'));
        expect(text, contains('Ceci est un paragraphe avec du texte standard.'));
        expect(text, isNot(contains(r'\rtf1')));
        expect(text, isNot(contains(r'\fonttbl')));
      } finally {
        if (await file.exists()) await file.delete();
      }
    });

    test('DOCX parsing extrait le texte XML depuis le zip', () async {
      const xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r><w:t>Premier paragraphe &amp; titre</w:t></w:r>
    </w:p>
    <w:p>
      <w:r><w:t>Deuxième paragraphe avec du contenu.</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';

      final archive = Archive();
      final xmlBytes = utf8.encode(xml);
      archive.addFile(ArchiveFile('word/document.xml', xmlBytes.length, xmlBytes));
      final zipEncoder = ZipEncoder();
      final zipBytes = zipEncoder.encode(archive);

      final file = File('${Directory.systemTemp.path}/test_doc.docx');
      await file.writeAsBytes(zipBytes);
      try {
        final text = await DocReader.read(file.path);
        expect(text, contains('Premier paragraphe & titre'));
        expect(text, contains('Deuxième paragraphe avec du contenu.'));
      } finally {
        if (await file.exists()) await file.delete();
      }
    });

    test('ODT parsing extrait le texte XML depuis content.xml', () async {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
                         xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
  <office:body>
    <office:text>
      <text:h>Grand Titre ODT</text:h>
      <text:p>Texte dans le paragraphe libre &lt;important&gt;.</text:p>
    </office:text>
  </office:body>
</office:document-content>''';

      final archive = Archive();
      final xmlBytes = utf8.encode(xml);
      archive.addFile(ArchiveFile('content.xml', xmlBytes.length, xmlBytes));
      final zipEncoder = ZipEncoder();
      final zipBytes = zipEncoder.encode(archive);

      final file = File('${Directory.systemTemp.path}/test_doc.odt');
      await file.writeAsBytes(zipBytes);
      try {
        final text = await DocReader.read(file.path);
        expect(text, contains('Grand Titre ODT'));
        expect(text, contains('Texte dans le paragraphe libre <important>.'));
      } finally {
        if (await file.exists()) await file.delete();
      }
    });

    test('DOC binaire ancien extrait les portions lisibles', () async {
      // Simule un flux binaire contenant du texte ASCII/latin
      final bytes = Uint8List.fromList([
        0xD0, 0xCF, 0x11, 0xE0, // Signature OLE2
        0x00, 0x01, 0x02,
        ...utf8.encode('Contenu texte présent dans le fichier doc legacy.'),
        0x00, 0x04, 0x05,
      ]);
      final file = File('${Directory.systemTemp.path}/test_doc.doc');
      await file.writeAsBytes(bytes);
      try {
        final text = await DocReader.read(file.path);
        expect(text, contains('Contenu texte présent dans le fichier doc legacy.'));
      } finally {
        if (await file.exists()) await file.delete();
      }
    });
  });
}
