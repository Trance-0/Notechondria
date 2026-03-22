part of notechondria_frontend;

/// Course module for switching collections and reading public course notes.
class _CoursePage extends StatelessWidget {
  const _CoursePage({
    required this.courses,
    required this.selectedCourse,
    required this.notes,
    required this.onCourseChanged,
    required this.onFetchNoteDetail,
  });

  final List<Map<String, dynamic>> courses;
  final Map<String, dynamic>? selectedCourse;
  final List<Map<String, dynamic>> notes;
  final ValueChanged<Map<String, dynamic>> onCourseChanged;
  final Future<Map<String, dynamic>> Function(int noteId) onFetchNoteDetail;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Collections', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: selectedCourse?['id'] as int?,
          items: courses
              .map(
                (course) => DropdownMenuItem<int>(
                  value: course['id'] as int,
                  child: Text(course['title']?.toString() ?? 'Course'),
                ),
              )
              .toList(),
          onChanged: (value) {
            for (final course in courses) {
              if (course['id'] == value) {
                onCourseChanged(course);
                break;
              }
            }
          },
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 20),
        Text('Notes', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        for (final note in notes)
          Card(
            child: ListTile(
              title: Text(note['title']?.toString() ?? 'Untitled note'),
              subtitle: Text(note['excerpt']?.toString() ?? ''),
              onTap: () async {
                final detail = await onFetchNoteDetail(note['id'] as int);
                if (context.mounted) {
                  await showDialog<void>(
                    context: context,
                    builder: (context) => _NoteViewerDialog(note: detail),
                  );
                }
              },
            ),
          ),
      ],
    );
  }
}
