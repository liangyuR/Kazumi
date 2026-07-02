import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/source/source_binding.dart';

void main() {
  group('sourceBindingKeyFromSource', () {
    const baseUrl = 'https://www.example.com';

    test('uses explicit source id before url fallback', () {
      expect(
        sourceBindingKeyFromSource(
          baseUrl: baseUrl,
          sourceUrl: '/detail/123',
          sourceId: 'subject-123',
        ),
        'sourceId:subject-123',
      );
    });

    test('normalizes explicit source urls instead of keeping their domain', () {
      expect(
        sourceBindingKeyFromSource(
          baseUrl: baseUrl,
          sourceUrl: '/fallback/1',
          sourceId: 'https://mirror.example.org/detail/123/',
        ),
        'source:/detail/123',
      );
    });

    test('derives a domain-independent key from source url', () {
      final oldDomain = sourceBindingKeyFromSource(
        baseUrl: 'https://old.example.com',
        sourceUrl: 'https://old.example.com/detail/123',
      );
      final newDomain = sourceBindingKeyFromSource(
        baseUrl: 'https://new.example.org',
        sourceUrl: 'http://new.example.org/detail/123/',
      );

      expect(oldDomain, 'source:/detail/123');
      expect(newDomain, oldDomain);
    });

    test('keeps query because it can identify source resources', () {
      expect(
        sourceBindingKeyFromSource(
          baseUrl: baseUrl,
          sourceUrl: '/vod/detail?id=123&season=2',
        ),
        'source:/vod/detail?id=123&season=2',
      );
    });

    test('drops fragments from source urls', () {
      expect(
        sourceBindingKeyFromSource(
          baseUrl: baseUrl,
          sourceUrl: '/detail/123#episodes',
        ),
        'source:/detail/123',
      );
    });

    test('returns empty key when no source identity is available', () {
      expect(
        sourceBindingKeyFromSource(baseUrl: '', sourceUrl: ''),
        isEmpty,
      );
    });
  });
}
