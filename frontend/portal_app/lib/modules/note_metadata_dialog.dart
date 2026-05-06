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
    this.onUploadCover,
    this.onDeleteCover,
    this.uncategorizedLabel = 'Inbox',
  });

  final Map<String, dynamic> note;
  final List<Map<String, dynamic>> courses;
  final Map<String, dynamic> metadata;
  final bool allowPublicToggle;
  /// 0.1.120: per-account display label for the synthetic
  /// uncategorized bucket (notes with `course_id == null`). Replaces
  /// the old "No assigned course" placeholder. Defaults to "Inbox" so
  /// hosts that haven't wired the new field still render a sensible
  /// label.
  final String uncategorizedLabel;
  final Future<List<Map<String, dynamic>>> Function(int noteId) onGetHistory;
  final Future<Map<String, dynamic>> Function(int noteId, int versionId)
      onRestoreVersion;
  final Future<Map<String, dynamic>> Function(XFile file)? onUploadCover;
  final Future<Map<String, dynamic>> Function()? onDeleteCover;

  @override
  State<_NoteMetadataDialog> createState() => _NoteMetadataDialogState();
}

class _NoteMetadataDialogState extends State<_NoteMetadataDialog> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _sectionController;
  int? _courseId;
  bool _isPublic = false;
  late Future<List<Map<String, dynamic>>> _historyFuture;
  String? _coverUrl;
  bool _coverBusy = false;
  String? _coverError;

  /// Backing store for the shared `CustomMetaListEditor`. Round-tripped
  /// to `note.custom_meta` (JSON object string) on save.
  late final CustomMetaController _customMetaController;

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
    _coverUrl = widget.note['cover_image_url']?.toString();
    _historyFuture = widget.onGetHistory(widget.note['id'] as int);
    _customMetaController = CustomMetaController(
      initialJson: widget.note['custom_meta']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _sectionController.dispose();
    _customMetaController.dispose();
    super.dispose();
  }

  String get _coverSeed {
    final uuid = widget.note['uuid']?.toString() ?? '';
    final title = widget.note['title']?.toString() ?? '';
    return uuid.isNotEmpty ? uuid : 'note-$title';
  }

  Future<void> _pickAndUploadCover() async {
    final upload = widget.onUploadCover;
    if (upload == null) return;
    final XFile? picked;
    try {
      picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Cover image',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
          ),
        ],
      );
    } catch (error) {
      setState(() {
        _coverError = error.toString().replaceFirst('Exception: ', '');
      });
      return;
    }
    if (picked == null) return;
    setState(() {
      _coverBusy = true;
      _coverError = null;
    });
    try {
      final updated = await upload(picked);
      if (!mounted) return;
      setState(() {
        _coverUrl = updated['cover_image_url']?.toString() ?? _coverUrl;
        _coverBusy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _coverBusy = false;
        _coverError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _clearCover() async {
    final clear = widget.onDeleteCover;
    if (clear == null) return;
    setState(() {
      _coverBusy = true;
      _coverError = null;
    });
    try {
      final updated = await clear();
      if (!mounted) return;
      setState(() {
        _coverUrl = updated['cover_image_url']?.toString() ?? '';
        _coverBusy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _coverBusy = false;
        _coverError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _buildCoverSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasCover = _coverUrl != null && _coverUrl!.isNotEmpty;
    final canUpload = widget.onUploadCover != null;
    final canDelete = widget.onDeleteCover != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cover image',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Text(
          hasCover
              ? 'Shown above the note in view mode.'
              : canUpload
                  ? 'No cover yet — readers see a barcode generated from the note URL.'
                  : 'Sync this note to the cloud before uploading a cover image.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 10),
        NoteCoverImage(
          seed: _coverSeed,
          imageUrl: _coverUrl,
          caption: widget.note['title']?.toString(),
          showCaption: !hasCover,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: (canUpload && !_coverBusy) ? _pickAndUploadCover : null,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(hasCover ? 'Replace' : 'Upload'),
            ),
            const SizedBox(width: 8),
            if (hasCover)
              TextButton.icon(
                onPressed: (canDelete && !_coverBusy) ? _clearCover : null,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove'),
              ),
            if (_coverBusy) ...[
              const SizedBox(width: 12),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        if (_coverError != null && _coverError!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _coverError!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
          ),
        ],
      ],
    );
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
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text(widget.uncategorizedLabel),
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
              if (widget.onUploadCover != null ||
                  widget.onDeleteCover != null ||
                  (_coverUrl != null && _coverUrl!.isNotEmpty)) ...[
                const SizedBox(height: 16),
                _buildCoverSection(context),
              ],
              const SizedBox(height: 16),
              CustomMetaListEditor(controller: _customMetaController),
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
                                      'custom_meta':
                                          _customMetaController.serialize(),
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
            'custom_meta': _customMetaController.serialize(),
          }),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
