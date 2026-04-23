/// Formats note timestamps for compact card footers.
String formatCompactTimestamp(String raw) {
  if (raw.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  final now = DateTime.now();
  final local = parsed.toLocal();
  final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
  if (local.isAfter(startOfWeek) && local.year == now.year) {
    return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][local.weekday - 1];
  }
  if (local.year == now.year) {
    return '${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }
  return '${(local.year % 100).toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
}
