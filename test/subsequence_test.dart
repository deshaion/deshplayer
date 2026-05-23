import 'package:flutter_test/flutter_test.dart';

void main() {
  bool matchesSubsequence(String query, String target) {
    if (query.isEmpty) return true;
    query = query.toLowerCase();
    target = target.toLowerCase();

    int queryIndex = 0;
    for (int i = 0; i < target.length; i++) {
      if (query[queryIndex] == target[i]) {
        queryIndex++;
        if (queryIndex == query.length) {
          return true;
        }
      }
    }
    return false;
  }

  test('Subsequence matching logic', () {
    expect(matchesSubsequence('abc', 'a..b..c'), true);
    expect(matchesSubsequence('abc', 'xaxbxxc'), true);
    expect(matchesSubsequence('abc', 'cba'), false);
    expect(matchesSubsequence('artist', 'Some Artist Song'), true);
    expect(matchesSubsequence('rtst', 'artist'), true);
    expect(matchesSubsequence('123', 'song_1_final_23.mp3'), true);
  });
}
