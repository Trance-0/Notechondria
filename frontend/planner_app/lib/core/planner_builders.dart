part of notechondria_frontend;

/// Planner-event builders.
extension _AppShellPlannerBuildersX on _AppShellState {
  Map<String, dynamic> _buildLocalPlannerEvent({
    required String title,
    required DateTime eventDate,
    required int difficultyWeight,
    required String description,
    int? courseId,
  }) {
    final now = DateTime.now().toUtc();
    return {
      'id': -DateTime.now().microsecondsSinceEpoch,
      'title': title,
      'event_date': _dateOnly(eventDate).toIso8601String().split('T').first,
      'starts_at': eventDate.toUtc().toIso8601String(),
      'ends_at':
          eventDate.toUtc().add(const Duration(hours: 1)).toIso8601String(),
      'difficulty_weight': difficultyWeight,
      'description': description,
      'course_id': courseId,
      'is_completed': false,
      'completed_at': null,
      'is_local_event': true,
      'date_created': now.toIso8601String(),
      'last_edit': now.toIso8601String(),
    };
  }

  double _deadlineTimeWeight() =>
      (_localSettings['deadline_time_weight'] as num?)?.toDouble() ?? 1.0;

  double _deadlineImportanceWeight() =>
      (_localSettings['deadline_importance_weight'] as num?)?.toDouble() ?? 1.0;

  double _deadlineUrgencyScore(Map<String, dynamic> event) {
    final raw =
        event['starts_at']?.toString() ?? event['event_date']?.toString() ?? '';
    DateTime due;
    try {
      due = DateTime.parse(raw);
    } catch (_) {
      due = DateTime.now().toUtc();
    }
    final hoursRemaining =
        due.difference(DateTime.now().toUtc()).inMinutes / 60.0;
    final timePressure = hoursRemaining <= 0
        ? 24.0
        : 1 / (hoursRemaining / 24.0).clamp(0.25, 365.0);
    final importance = (event['difficulty_weight'] as num?)?.toDouble() ?? 1.0;
    return (_deadlineTimeWeight() * timePressure) *
        (_deadlineImportanceWeight() * importance);
  }

  Map<String, dynamic> _buildOfflineActivityWeek() {
    final base = _dateOnly(DateTime.now());
    final days = List.generate(7, (index) {
      final day = base.add(Duration(days: index));
      return {
        'date': day.toIso8601String().split('T').first,
        'events': const <Map<String, dynamic>>[],
      };
    });
    final deadlines = _plannerEvents
        .map((event) => {
              'title': event['title'],
              'event_date': event['event_date'],
              'starts_at': event['starts_at'],
              'difficulty_weight': event['difficulty_weight'] ?? 1,
              'description': event['description'] ?? '',
              'is_completed': event['is_completed'] ?? false,
              'urgency_score': _deadlineUrgencyScore(event),
            })
        .toList(growable: false)
      ..sort((a, b) => ((b['urgency_score'] as num?)?.toDouble() ?? 0)
          .compareTo((a['urgency_score'] as num?)?.toDouble() ?? 0));
    return {
      'days': days,
      'deadlines': deadlines,
    };
  }
}
