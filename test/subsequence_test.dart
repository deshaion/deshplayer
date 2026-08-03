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

  test('Match score logic', () {
    expect(SearchUtils.calculateMatchScore('abc', 'cba'), 0);

    // Higher score for exact matches
    final exactScore = SearchUtils.calculateMatchScore('artist', 'artist');
    final containsScore = SearchUtils.calculateMatchScore('artist', 'some artist song');
    final subsequenceScore = SearchUtils.calculateMatchScore('art', 'a r t');

    expect(exactScore > containsScore, true);
    expect(containsScore > subsequenceScore, true);
  });
}
