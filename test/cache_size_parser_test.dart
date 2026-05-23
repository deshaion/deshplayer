import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/cache_size_parser.dart';

void main() {
  group('CacheSizeParser', () {
    test('parses correctly', () {
      expect(CacheSizeParser.parse('500'), 500 * 1024 * 1024);
      expect(CacheSizeParser.parse('500mb'), 500 * 1024 * 1024);
      expect(CacheSizeParser.parse('500MB'), 500 * 1024 * 1024);
      expect(CacheSizeParser.parse('5 gb'), 5 * 1024 * 1024 * 1024);
      expect(CacheSizeParser.parse('2GB'), 2 * 1024 * 1024 * 1024);
      expect(CacheSizeParser.parse('100 gb'), 100 * 1024 * 1024 * 1024);

      expect(CacheSizeParser.parse(''), null);
      expect(CacheSizeParser.parse('abc'), null);
      expect(CacheSizeParser.parse('5kb'), null);
      expect(CacheSizeParser.parse('5mb abc'), null);
    });

    test('formats correctly', () {
      expect(CacheSizeParser.format(500 * 1024 * 1024), '500mb');
      expect(CacheSizeParser.format(5 * 1024 * 1024 * 1024), '5gb');
      expect(CacheSizeParser.format(1024 * 1024 * 1024), '1gb');
    });
  });
}
