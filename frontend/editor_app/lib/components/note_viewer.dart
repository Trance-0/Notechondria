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
    final l10n = AppLocalizations.of(context);
    final note = widget.note;
    final content = note['content']?.toString() ?? _noteToMarkdown(note);
    final author =
        Map<String, dynamic>.from(note['author'] as Map? ?? const {});
    final course =
        Map<String, dynamic>.from(note['course'] as Map? ?? const {});
    final subtitleParts = <String>[
      if ((author['username']?.toString() ?? '').isNotEmpty)
        author['username'].toString(),
      if ((course['title']?.toString() ?? '').isNotEmpty)
        course['title'].toString(),
      if ((note['last_edit']?.toString() ?? '').isNotEmpty)
        formatCompactTimestamp(note['last_edit'].toString()),
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
                      tooltip: l10n.commonBack,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note['title']?.toString() ?? l10n.noteUntitled,
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
                        tooltip: l10n.noteOptions,
                        onSelected: (value) async {
                          if (value == 'edit' && widget.onEdit != null) {
                            Navigator.of(context).pop();
                            widget.onEdit!();
                          } else if (value == 'export' &&
                              widget.onExport != null) {
                            await widget.onExport!();
                          } else if (value == 'copy_link') {
                            final uuid = note['uuid']?.toString();
                            if (uuid != null) {
                              final base = Uri.base.removeFragment();
                              final link = '$base#/notes/$uuid';
                              await Clipboard.setData(
                                  ClipboardData(text: link));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(l10n.noteLinkCopied)),
                                );
                              }
                            }
                          } else if (value == 'delete' &&
                              widget.onDelete != null) {
                            Navigator.of(context).pop();
                            await widget.onDelete!();
                          }
                        },
                        itemBuilder: (context) => [
                          if (widget.onEdit != null)
                            PopupMenuItem(
                                value: 'edit', child: Text(l10n.commonEdit)),
                          if (note['uuid'] != null)
                            PopupMenuItem(
                                value: 'copy_link',
                                child: Text(l10n.noteCopyLink)),
                          if (widget.onExport != null)
                            PopupMenuItem(
                                value: 'export',
                                child: Text(l10n.noteExportMarkdown)),
                          if (widget.onDelete != null)
                            PopupMenuItem(
                                value: 'delete', child: Text(l10n.commonDelete)),
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
                        final uuid = note['uuid']?.toString() ?? '';
                        final title = note['title']?.toString() ?? '';
                        final coverUrl =
                            note['cover_image_url']?.toString() ?? '';
                        return ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth > 40
                                ? constraints.maxWidth - 40
                                : constraints.maxWidth,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              NoteCoverImage(
                                seed: uuid.isNotEmpty ? uuid : 'note-$title',
                                imageUrl: coverUrl.isNotEmpty ? coverUrl : null,
                                caption: title,
                                showCaption: coverUrl.isEmpty,
                              ),
                              const SizedBox(height: 20),
                              MarkdownBody(
                                data: content,
                                selectable: true,
                                builders: _markdownBuilders(),
                                sizedImageBuilder: _localAttachmentImageBuilder,
                                inlineSyntaxes: _markdownInlineSyntaxes(),
                                blockSyntaxes: _markdownBlockSyntaxes(),
                                styleSheet: _markdownStyleSheet(context),
                              ),
                            ],
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

/// User-chosen options returned from [_ExportOptionsDialog].
class _ExportOptions {
  const _ExportOptions({
    required this.includeMetadata,
    required this.recursive,
    required this.format,
  });

  final bool includeMetadata;
  final bool recursive;

  /// Either 'md' (single/combined markdown file) or 'zip' (archive of notes).
  final String format;
}

/// Dialog that collects export preferences before a note is written to disk.
/// Shown once per export action so users can pick metadata, recursive (whole
/// category), and the output format.
class _ExportOptionsDialog extends StatefulWidget {
  const _ExportOptionsDialog({
    required this.noteTitle,
    required this.categoryTitle,
    required this.siblingCount,
  });

  final String noteTitle;
  final String categoryTitle;
  final int siblingCount;

  @override
  State<_ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<_ExportOptionsDialog> {
  bool _includeMetadata = true;
  bool _recursive = false;
  String _format = 'md';

  @override
  Widget build(BuildContext context) {
    final canRecurse = widget.siblingCount > 1;
    // Recursive + md combines into one file; zip stores notes as separate files.
    return AlertDialog(
      title: const Text('Export markdown'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Exporting "${widget.noteTitle}"',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _includeMetadata,
              onChanged: (value) =>
                  setState(() => _includeMetadata = value ?? true),
              title: const Text('Include metadata (YAML frontmatter)'),
              subtitle: const Text(
                  'Adds title, author, category, and last-edited timestamp.'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _recursive,
              onChanged: canRecurse
                  ? (value) => setState(() => _recursive = value ?? false)
                  : null,
              title: Text(
                  'Recursive (entire "${widget.categoryTitle}" category, ${widget.siblingCount} notes)'),
              subtitle: Text(canRecurse
                  ? 'Exports every note in the same category.'
                  : 'Only one note in this category — nothing to recurse.'),
            ),
            const SizedBox(height: 8),
            Text('Format', style: Theme.of(context).textTheme.titleSmall),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'md',
              groupValue: _format,
              onChanged: (value) => setState(() => _format = value ?? 'md'),
              title: const Text('Markdown (.md)'),
              subtitle: Text(_recursive
                  ? 'All notes combined into one file with separators.'
                  : 'Single markdown file.'),
            ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'zip',
              groupValue: _format,
              onChanged: (value) => setState(() => _format = value ?? 'zip'),
              title: const Text('Zip archive (.zip)'),
              subtitle:
                  const Text('Each note as a separate .md file inside a zip.'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _ExportOptions(
              includeMetadata: _includeMetadata,
              recursive: _recursive,
              format: _format,
            ),
          ),
          child: const Text('Export'),
        ),
      ],
    );
  }
}
