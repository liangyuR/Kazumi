import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';

void main() {
  group('Plugin episode identity', () {
    test('keeps roadId empty when rule does not provide explicit road identity',
        () {
      final plugin = _plugin();

      final roads = plugin.testQueryChapterRoads(_chapterHtml);

      expect(roads, hasLength(1));
      expect(roads.single.roadId, isEmpty);
      expect(roads.single.data.map((episode) => episode.roadId), ['', '']);
      expect(roads.single.data.map((episode) => episode.stableId),
          ['/play/1', '/play/2']);
    });

    test('propagates explicit roadId from the road node', () {
      final plugin = _plugin(roadId: './/span[@data-kind="road-id"]');

      final roads = plugin.testQueryChapterRoads(_chapterHtml);

      expect(roads, hasLength(1));
      expect(roads.single.roadId, 'source-main');
      expect(roads.single.data.map((episode) => episode.roadId),
          ['source-main', 'source-main']);
    });
  });
}

Plugin _plugin({String roadId = ''}) {
  return Plugin.fromTemplate()
    ..name = 'fixture'
    ..baseUrl = 'https://example.com'
    ..chapterRoads = '//div[@data-kind="road"]'
    ..chapterResult = './/a'
    ..roadId = roadId;
}

const _chapterHtml = '''
<html>
  <body>
    <div data-kind="road">
      <span data-kind="road-id">source-main</span>
      <a href="/play/1">第1集</a>
      <a href="/play/2">第2集</a>
    </div>
  </body>
</html>
''';
