import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/ui/document_search.dart';

void main() {
  const text = 'Le chat dort. Le CHAT mange. Un chaton.';

  test('findAll : insensible à la casse, sans chevauchement', () {
    final matches = PlainTextSearch.findAll(text, 'chat');
    expect(matches.map((m) => m.start), [3, 17, 32]);
    expect(matches.map((m) => m.end), [7, 21, 36]);
  });

  test('findAll : aiguille vide → rien', () {
    expect(PlainTextSearch.findAll(text, ''), isEmpty);
  });

  test('findAll : occurrences adjacentes', () {
    expect(PlainTextSearch.findAll('aaaa', 'aa').length, 2);
  });

  test('search puis next/previous bouclent', () async {
    final search = PlainTextSearch(text);
    var notified = 0;
    search.addListener(() => notified++);

    await search.search('chat');
    expect(search.state.count, 3);
    expect(search.state.current, 0);

    search.next();
    search.next();
    expect(search.state.current, 2);
    search.next();
    expect(search.state.current, 0);
    search.previous();
    expect(search.state.current, 2);
    expect(notified, greaterThan(0));
  });

  test('recherche sans résultat', () async {
    final search = PlainTextSearch(text);
    await search.search('zèbre');
    expect(search.state.count, 0);
    expect(search.state.current, -1);
    expect(search.state.currentMatch, isNull);
    search.next(); // ne doit pas planter
  });

  test('chaîne vide efface', () async {
    final search = PlainTextSearch(text);
    await search.search('chat');
    await search.search('   ');
    expect(search.state.count, 0);
    expect(search.state.query, '');
  });
}
