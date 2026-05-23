import 'package:flutter_test/flutter_test.dart';
import 'package:deshplayer/ui/utils/search_utils.dart';

void main() {
  test('Subsequence matching logic', () {
    expect(SearchUtils.matchesSubsequence('abc', 'a..b..c'), true);
    expect(SearchUtils.matchesSubsequence('abc', 'xaxbxxc'), true);
    expect(SearchUtils.matchesSubsequence('abc', 'cba'), false);
    expect(SearchUtils.matchesSubsequence('artist', 'Some Artist Song'), true);
    expect(SearchUtils.matchesSubsequence('rtst', 'artist'), true);
    expect(SearchUtils.matchesSubsequence('123', 'song_1_final_23.mp3'), true);
  });
}
