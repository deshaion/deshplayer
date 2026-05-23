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
}
