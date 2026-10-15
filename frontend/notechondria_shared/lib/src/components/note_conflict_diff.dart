import 'package:flutter/material.dart';

import '../utils/line_diff.dart';

/// Side-by-side, git-diff-style view of a note conflict (#31): the local
/// version on the left, the remote (cloud) version on the right, with
/// changed / removed / added lines highlighted so the user can see what
/// actually differs before choosing which to keep. Scrolls internally and
/// is height-capped so it fits inside the conflict dialog.
class NoteConflictDiffView extends StatelessWidget {
  const NoteConflictDiffView({
    super.key,
    required this.localContent,
    required this.remoteContent,
    this.localLabel = 'Local',
    this.remoteLabel = 'Cloud',
    this.maxHeight = 320,
  });

  final String localContent;
  final String remoteContent;
  final String localLabel;
  final String remoteLabel;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final rows = diffLines(localContent, remoteContent);
    final changed = rows.where((r) => r.kind != DiffLineKind.equal).length;

    // git-diff-ish tints that read in both themes (low-alpha over surface).
    final removedBg = isDark ? const Color(0x33F85149) : const Color(0x33FFC9C4);
    final addedBg = isDark ? const Color(0x3339D353) : const Color(0x33B4F0C0);
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4);

    Widget cell(String? text, Color? bg) => Container(
          width: double.infinity,
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Text(text ?? '', style: mono, softWrap: true),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _header(theme, localLabel, Icons.smartphone_outlined)),
            const SizedBox(width: 8),
            Expanded(child: _header(theme, remoteLabel, Icons.cloud_outlined)),
          ],
        ),
        const SizedBox(height: 6),
        if (changed == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('The two versions are identical.',
                style: theme.textTheme.bodySmall),
          )
        else
          Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(6),
            ),
            clipBehavior: Clip.antiAlias,
            child: Scrollbar(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final r in rows)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: cell(
                                r.left,
                                r.kind == DiffLineKind.removed ||
                                        r.kind == DiffLineKind.changed
                                    ? removedBg
                                    : null,
                              ),
                            ),
                            const VerticalDivider(width: 1, thickness: 1),
                            Expanded(
                              child: cell(
                                r.right,
                                r.kind == DiffLineKind.added ||
                                        r.kind == DiffLineKind.changed
                                    ? addedBg
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _header(ThemeData theme, String label, IconData icon) => Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style:
                  theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );
}
