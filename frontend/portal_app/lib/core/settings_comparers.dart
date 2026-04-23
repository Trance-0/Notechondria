part of notechondria_frontend;

/// Settings comparers.
extension _AppShellSettingsComparersX on _AppShellState {
  bool _sameTrimmedValue(String a, String b) => a.trim() == b.trim();

  bool _sameEmailValue(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  String _summarizeChangedFields(List<String> fields) {
    final unique = <String>[];
    for (final field in fields) {
      if (field.isEmpty || unique.contains(field)) {
        continue;
      }
      unique.add(field);
    }
    if (unique.isEmpty) {
      return 'settings';
    }
    if (unique.length == 1) {
      return unique.first;
    }
    if (unique.length == 2) {
      return '${unique.first} and ${unique.last}';
    }
    return '${unique[0]}, ${unique[1]} +${unique.length - 2}';
  }
}
