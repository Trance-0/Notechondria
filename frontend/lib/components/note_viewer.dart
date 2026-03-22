part of notechondria_frontend;

/// Full-screen markdown note reader shared by front, course, and learner flows.
class _NoteViewerDialog extends StatefulWidget {
  const _NoteViewerDialog({required this.note});

  final Map<String, dynamic> note;

  @override
  State<_NoteViewerDialog> createState() => _NoteViewerDialogState();
}

class _NoteViewerDialogState extends State<_NoteViewerDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final content = note['content']?.toString() ?? _noteToMarkdown(note);
    final author = Map<String, dynamic>.from(note['author'] as Map? ?? const {});
    final course = Map<String, dynamic>.from(note['course'] as Map? ?? const {});
    final subtitleParts = <String>[
      if ((author['username']?.toString() ?? '').isNotEmpty)
        author['username'].toString(),
      if ((course['title']?.toString() ?? '').isNotEmpty) course['title'].toString(),
      if ((note['last_edit']?.toString() ?? '').isNotEmpty)
        _formatCompactTimestamp(note['last_edit'].toString()),
    ];
    return Dialog.fullscreen(
      child: SafeArea(
        child: SelectionArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note['title']?.toString() ?? 'Untitled note',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (subtitleParts.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitleParts.join(' • '),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Card(
                  margin: const EdgeInsets.all(20),
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      child: MarkdownBody(
                        data: content,
                        selectable: true,
                        builders: _markdownBuilders(),
                        inlineSyntaxes: _markdownInlineSyntaxes(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
