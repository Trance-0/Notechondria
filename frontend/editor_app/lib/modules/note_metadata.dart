part of notechondria_frontend;

/// Dialog for editing note metadata and restoring saved versions.
class _NoteMetadataDialog extends StatefulWidget {
  const _NoteMetadataDialog({
    required this.note,
    required this.courses,
    required this.metadata,
    required this.allowPublicToggle,
    required this.onGetHistory,
    required this.onRestoreVersion,
  });

  final Map<String, dynamic> note;
  final List<Map<String, dynamic>> courses;
  final Map<String, dynamic> metadata;
  final bool allowPublicToggle;
  final Future<List<Map<String, dynamic>>> Function(int noteId) onGetHistory;
  final Future<Map<String, dynamic>> Function(int noteId, int versionId)
      onRestoreVersion;

  @override
  State<_NoteMetadataDialog> createState() => _NoteMetadataDialogState();
}

class _NoteMetadataDialogState extends State<_NoteMetadataDialog> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _sectionController;
  int? _courseId;
  bool _isPublic = false;
  late Future<List<Map<String, dynamic>>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(
      text: widget.metadata['description']?.toString() ??
          widget.note['description']?.toString() ??
          '',
    );
    _sectionController = TextEditingController(
      text: widget.metadata['section']?.toString() ?? '',
    );
    _courseId = (widget.metadata['course_id'] as num?)?.toInt() ??
        (widget.note['course']?['id'] as num?)?.toInt();
    _isPublic = widget.metadata['is_public'] == true ||
        widget.note['is_public'] == true;
    _historyFuture = widget.onGetHistory(widget.note['id'] as int);
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Note details'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int?>(
                value: _courseId,
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('No assigned course'),
                  ),
                  ...widget.courses.map(
                    (course) => DropdownMenuItem<int?>(
                      value: course['id'] as int,
                      child: Text(course['title']?.toString() ?? 'Course'),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _courseId = value),
                decoration: const InputDecoration(
                  labelText: 'Assigned course / plan',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sectionController,
                decoration: const InputDecoration(
                  labelText: 'Section',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Short description / comments',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _isPublic,
                onChanged: widget.allowPublicToggle
                    ? (value) => setState(() => _isPublic = value)
                    : null,
                contentPadding: EdgeInsets.zero,
                title: const Text('Public note'),
                subtitle: Text(
                  widget.allowPublicToggle
                      ? 'Public notes appear in the recommendation feed.'
                      : 'Sync this note to the cloud before making it public.',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Version history',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _historyFuture,
                  builder: (context, snapshot) {
                    final rows = snapshot.data ?? const [];
                    if (rows.isEmpty) {
                      return const Text('No saved versions yet.');
                    }
                    return ListView(
                      children: [
                        for (final version in rows)
                          ListTile(
                            dense: true,
                            title:
                                Text(version['label']?.toString() ?? 'Version'),
                            subtitle:
                                Text(version['date_created']?.toString() ?? ''),
                            trailing: TextButton(
                              onPressed: () async {
                                final restored = await widget.onRestoreVersion(
                                  widget.note['id'] as int,
                                  version['id'] as int,
                                );
                                if (mounted) {
                                  Navigator.of(context).pop({
                                    'metadata': {
                                      'description':
                                          _descriptionController.text,
                                      'section': _sectionController.text,
                                      'course_id': _courseId,
                                      'is_public': _isPublic,
                                    },
                                    'restored_note': restored,
                                  });
                                }
                              },
                              child: const Text('Restore'),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'description': _descriptionController.text,
            'section': _sectionController.text,
            'course_id': _courseId,
            'is_public': _isPublic,
          }),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Compact save indicator shown beside the note title while editing.
class _SaveStatus extends StatelessWidget {
  const _SaveStatus({
    required this.lastSavedAt,
    required this.errorMessage,
    required this.saving,
  });

  final DateTime? lastSavedAt;
  final String? errorMessage;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    if (saving) {
      return const Text('Saving...');
    }
    if (errorMessage != null && errorMessage!.isNotEmpty) {
      return Tooltip(
        message: errorMessage!,
        child: const Icon(
          Icons.warning_amber_rounded,
          color: Color(0xFFF59E0B),
        ),
      );
    }
    return Text(
      lastSavedAt == null ? 'Not saved' : 'Saved ${_formatTime(lastSavedAt!)}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
