class CacheSizeParser {
  static int? parse(String input) {
    input = input.trim().toLowerCase();
    if (input.isEmpty) return null;

    final regex = RegExp(r'^(\d+)\s*(mb|gb)?$');
    final match = regex.firstMatch(input);

    if (match == null) return null;

    final valueStr = match.group(1);
    if (valueStr == null) return null;

    final value = int.tryParse(valueStr);
    if (value == null) return null;

    final unit = match.group(2);

    if (unit == 'gb') {
      return value * 1024 * 1024 * 1024;
    } else {
      // Default to mb
      return value * 1024 * 1024;
    }
  }

  static String format(int bytes) {
    if (bytes >= 1024 * 1024 * 1024 && bytes % (1024 * 1024 * 1024) == 0) {
      return '${bytes ~/ (1024 * 1024 * 1024)}gb';
    } else {
      return '${bytes ~/ (1024 * 1024)}mb';
    }
  }
}
