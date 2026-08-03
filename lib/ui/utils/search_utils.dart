class SearchUtils {
  static bool matchesSubsequence(String query, String target) {
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

  static bool _isWordStart(String target, int index) {
    if (index == 0) return true;
    String prev = target[index - 1];
    return prev == ' ' || prev == '_' || prev == '-' || prev == '.' || prev == '/' || prev == '\\' || prev == '(' || prev == ')' || prev == '[' || prev == ']';
  }

  static int calculateMatchScore(String query, String target) {
    if (query.isEmpty) return 0;

    String queryLower = query.toLowerCase();
    String targetLower = target.toLowerCase();

    if (!matchesSubsequence(queryLower, targetLower)) return 0;

    int score = 0;

    if (queryLower == targetLower) {
      score += 1000;
    }

    List<String> targetWords = targetLower.split(RegExp(r'[\s_\-\.\/\\()\[\]]+'));
    if (targetWords.contains(queryLower)) {
      score += 500;
    }

    if (targetLower.contains(queryLower)) {
      score += 200;
    }

    score += _calculateMaxSubsequenceScore(queryLower, targetLower);

    return score;
  }

  static int _calculateMaxSubsequenceScore(String query, String target) {
    int m = query.length;
    int n = target.length;

    if (m == 0 || n == 0) return 0;

    List<List<int>> dp = List.generate(m, (_) => List.filled(n, -1));

    for (int j = 0; j < n; j++) {
      if (query[0] == target[j]) {
        dp[0][j] = _isWordStart(target, j) ? 10 : 1;
      }
    }

    for (int i = 1; i < m; i++) {
      int maxPrev = -1;

      for (int j = i; j < n; j++) {
        if (j - 2 >= 0 && dp[i - 1][j - 2] > maxPrev) {
          maxPrev = dp[i - 1][j - 2];
        }

        if (query[i] == target[j]) {
          int score = -1;

          if (dp[i - 1][j - 1] != -1) {
            score = dp[i - 1][j - 1] + 5;
          }

          if (maxPrev != -1) {
            int nonConsecScore = maxPrev + (_isWordStart(target, j) ? 3 : 1);
            if (nonConsecScore > score) {
              score = nonConsecScore;
            }
          }

          dp[i][j] = score;
        }
      }
    }

    int finalMax = 0;
    for (int j = m - 1; j < n; j++) {
      if (dp[m - 1][j] > finalMax) {
        finalMax = dp[m - 1][j];
      }
    }

    return finalMax;
  }
}
