part of notechondria_frontend;

/// Full-screen markdown note viewer with Apple Journal-style navigation:
/// back button (top-left) and options menu (top-right).
class _NoteViewerDialog extends StatefulWidget {
  const _NoteViewerDialog({
    required this.note,
    this.onEdit,
    this.onExport,
    this.onDelete,
  });

  final Map<String, dynamic> note;
  final VoidCallback? onEdit;
  final Future<void> Function()? onExport;
  final Future<void> Function()? onDelete;

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
      if ((course['title']?.toString() ?? '').isNotEmpty)
        course['title'].toString(),
      if ((note['last_edit']?.toString() ?? '').isNotEmpty)
        _formatCompactTimestamp(note['last_edit'].toString()),
    ];
    return Dialog.fullscreen(
      child: SafeArea(
        child: SelectionArea(
          child: Column(
            children: [
              // Top bar: back button (left), title, options menu (right)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note['title']?.toString() ?? 'Untitled note',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitleParts.isNotEmpty)
                            Text(
                              subtitleParts.join(' \u2022 '),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (widget.onEdit != null ||
                        widget.onExport != null ||
                        widget.onDelete != null)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        tooltip: 'Options',
                        onSelected: (value) async {
                          if (value == 'edit' && widget.onEdit != null) {
                            Navigator.of(context).pop();
                            widget.onEdit!();
                          } else if (value == 'export' &&
                              widget.onExport != null) {
                            await widget.onExport!();
                          } else if (value == 'delete' &&
                              widget.onDelete != null) {
                            Navigator.of(context).pop();
                            await widget.onDelete!();
                          }
                        },
                        itemBuilder: (context) => [
                          if (widget.onEdit != null)
                            const PopupMenuItem(
                                value: 'edit', child: Text('Edit')),
                          if (widget.onExport != null)
                            const PopupMenuItem(
                                value: 'export',
                                child: Text('Export markdown')),
                          if (widget.onDelete != null)
                            const PopupMenuItem(
                                value: 'delete', child: Text('Delete')),
                        ],
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Markdown body — live rendered
              Expanded(
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(20),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth > 40
                                ? constraints.maxWidth - 40
                                : constraints.maxWidth,
                          ),
                          child: MarkdownBody(
                            data: content,
                            selectable: true,
                            builders: _markdownBuilders(),
                            inlineSyntaxes: _markdownInlineSyntaxes(),
                            styleSheet: MarkdownStyleSheet.fromTheme(
                              Theme.of(context),
                            ).copyWith(
                              codeblockDecoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              code: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontFamily: 'monospace',
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  ),
                              horizontalRuleDecoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
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
