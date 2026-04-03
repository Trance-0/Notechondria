part of notechondria_frontend;

/// Planner home focused on course calendars and upcoming deadlines.
class _FrontPage extends StatelessWidget {
  const _FrontPage({
    required this.profile,
    required this.localCourses,
    required this.remoteCourses,
    required this.plannerEvents,
    required this.onOpenCourse,
  });

  final Map<String, dynamic>? profile;
  final List<Map<String, dynamic>> localCourses;
  final List<Map<String, dynamic>> remoteCourses;
  final List<Map<String, dynamic>> plannerEvents;
  final Future<void> Function(Map<String, dynamic> course) onOpenCourse;

  List<Map<String, dynamic>> get _allCourses => [...localCourses, ...remoteCourses];

  List<Map<String, dynamic>> get _upcomingEvents {
    final rows = plannerEvents
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    rows.sort((a, b) {
      final aScore = (a['urgency_score'] as num?)?.toDouble() ?? 0;
      final bScore = (b['urgency_score'] as num?)?.toDouble() ?? 0;
      return bScore.compareTo(aScore);
    });
    return rows.take(6).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final greetingName =
        profile?['username']?.toString() ?? profile?['email']?.toString();
    final courses = _allCourses;
    final events = _upcomingEvents;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Planning workspace',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  greetingName == null || greetingName.isEmpty
                      ? 'Use each course as a calendar object. Modules act like discussion-backed event groups. Deadlines and study blocks appear below.'
                      : 'Hello, $greetingName. Use each course as a calendar object. Modules act like discussion-backed event groups. Deadlines and study blocks appear below.',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _PlannerChip(
                      icon: Icons.calendar_month_outlined,
                      label: '${courses.length} course calendar(s)',
                    ),
                    _PlannerChip(
                      icon: Icons.schedule_outlined,
                      label: '${plannerEvents.length} planner event(s)',
                    ),
                    const _PlannerChip(
                      icon: Icons.forum_outlined,
                      label: 'Modules use root notes as discussion hubs',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Course calendars',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (courses.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No course calendars yet. Create or restore a local course to start planning modules and deadlines offline.',
              ),
            ),
          )
        else
          ...courses.map(
            (course) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PlannerCourseCard(
                course: course,
                onOpenCourse: () => onOpenCourse(course),
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          'Upcoming deadlines and study blocks',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (events.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No planner events yet. Add local events from the Activity tab or sync cloud deadlines after login.',
              ),
            ),
          )
        else
          ...events.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PlannerDeadlineCard(event: event),
            ),
          ),
      ],
    );
  }
}

class _PlannerCourseCard extends StatelessWidget {
  const _PlannerCourseCard({required this.course, required this.onOpenCourse});

  final Map<String, dynamic> course;
  final VoidCallback onOpenCourse;

  @override
  Widget build(BuildContext context) {
    final isLocal = course['is_local_course'] == true;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: CircleAvatar(
          child: Icon(isLocal ? Icons.laptop_chromebook_outlined : Icons.cloud_outlined),
        ),
        title: Text(course['title']?.toString() ?? 'Untitled course'),
        subtitle: Text(
          course['description']?.toString().trim().isNotEmpty == true
              ? course['description']?.toString() ?? ''
              : 'Open this course to manage modules, discussion roots, and scheduling notes.',
        ),
        trailing: FilledButton(
          onPressed: onOpenCourse,
          child: const Text('Open'),
        ),
      ),
    );
  }
}

class _PlannerDeadlineCard extends StatelessWidget {
  const _PlannerDeadlineCard({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Icon(
          event['is_completed'] == true
              ? Icons.check_circle_outline
              : Icons.event_note_outlined,
        ),
        title: Text(event['title']?.toString() ?? 'Untitled event'),
        subtitle: Text(
          '${event['event_date'] ?? 'No date'} • weight ${event['difficulty_weight'] ?? 1} • urgency ${((event['urgency_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
        ),
      ),
    );
  }
}

class _PlannerChip extends StatelessWidget {
  const _PlannerChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
