part of notechondria_frontend;

/// Full-screen markdown note reader shared by front, course, and learner flows.
class _NoteViewerDialog extends StatelessWidget {
  const _NoteViewerDialog({required this.note});

  final Map<String, dynamic> note;

  @override
  Widget build(BuildContext context) {
    final content = note['content']?.toString() ?? _noteToMarkdown(note);
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
                      child: Text(
                        note['title']?.toString() ?? 'Untitled note',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
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
                    child: SingleChildScrollView(
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
