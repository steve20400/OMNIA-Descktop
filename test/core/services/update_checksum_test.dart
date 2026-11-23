import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/services/update_service.dart';

void main() {
  group('Empreinte d’une mise à jour', () {
    const sums = '''
0d8e3a62c5a1b7f04f2c8e1d9b6a3f5e7c4b2a19087f6e5d4c3b2a1908f7e6d5  OMNIA-0.1.231-Windows-portable.zip
A1B2C3D4E5F60718293A4B5C6D7E8F90A1B2C3D4E5F60718293A4B5C6D7E8F90 *OMNIA-Setup-0.1.231.exe
''';

    test('l’empreinte du paquet est retrouvée, en minuscules', () {
      expect(
        UpdateService.checksumFor(sums, 'OMNIA-Setup-0.1.231.exe'),
        'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
      );
      expect(
        UpdateService.checksumFor(sums, 'OMNIA-0.1.231-Windows-portable.zip'),
        startsWith('0d8e3a62'),
      );
    });

    test('un paquet absent de la liste n’a pas d’empreinte : rien ne s’exécute', () {
      expect(UpdateService.checksumFor(sums, 'OMNIA-Setup-9.9.9.exe'), isNull);
      expect(UpdateService.checksumFor('pas une liste', 'OMNIA-Setup-0.1.231.exe'), isNull);
    });
  });
}
