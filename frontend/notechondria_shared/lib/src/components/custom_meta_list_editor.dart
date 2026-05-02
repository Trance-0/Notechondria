import 'dart:convert';

import 'package:flutter/material.dart';

/// Holds the live `(key, value)` rows for a [CustomMetaListEditor].
/// Parents construct one with the JSON object string read from the
/// note's `custom_meta` column and call [serialize] when the user
/// hits Save in the parent dialog.
class CustomMetaController extends ChangeNotifier {
  CustomMetaController({String initialJson = ''}) {
    _load(initialJson);
  }

  final List<_CustomMetaRow> _rows = [];
  bool _expanded = false;

  int get rowCount => _rows.length;

  bool get expanded => _expanded;

  set expanded(bool value) {
    if (_expanded == value) return;
    _expanded = value;
    notifyListeners();
  }

  void _load(String raw) {
    if (raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        decoded.forEach((key, value) {
          _rows.add(
            _CustomMetaRow(
              key: TextEditingController(text: key),
              value: TextEditingController(text: value?.toString() ?? ''),
            ),
          );
        });
        if (_rows.isNotEmpty) _expanded = true;
        return;
      }
    } catch (_) {
      // Malformed JSON — preserve raw payload as a single row so the
      // user can repair it without losing data.
    }
    _rows.add(
      _CustomMetaRow(
        key: TextEditingController(text: 'invalid_json'),
        value: TextEditingController(text: raw),
      ),
    );
    _expanded = true;
  }

  void _addRow() {
    _rows.add(
      _CustomMetaRow(
        key: TextEditingController(),
        value: TextEditingController(),
      ),
    );
    notifyListeners();
  }

  void _removeRow(int index) {
    if (index < 0 || index >= _rows.length) return;
    _rows[index].key.dispose();
    _rows[index].value.dispose();
    _rows.removeAt(index);
    notifyListeners();
  }

  /// Returns the JSON object string of trimmed-key entries, or `''`
  /// when the editor is empty. Empty keys are dropped silently.
  String serialize() {
    final map = <String, String>{};
    for (final row in _rows) {
      final k = row.key.text.trim();
      if (k.isEmpty) continue;
      map[k] = row.value.text;
    }
    if (map.isEmpty) return '';
    return jsonEncode(map);
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.key.dispose();
      row.value.dispose();
    }
    _rows.clear();
    super.dispose();
  }
}

class _CustomMetaRow {
  _CustomMetaRow({required this.key, required this.value});

  final TextEditingController key;
  final TextEditingController value;
}

/// Expandable list of user-defined `(key, value)` metadata pairs.
/// Round-tripped to YAML frontmatter on the GitHub-sync export, sent
/// to the backend on `note.custom_meta`.
class CustomMetaListEditor extends StatefulWidget {
  const CustomMetaListEditor({
    required this.controller,
    super.key,
  });

  final CustomMetaController controller;

  @override
  State<CustomMetaListEditor> createState() => _CustomMetaListEditorState();
}

class _CustomMetaListEditorState extends State<CustomMetaListEditor> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant CustomMetaListEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final rows = controller._rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => controller.expanded = !controller.expanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    controller.expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Custom meta variables',
                    style: theme.textTheme.titleSmall,
                  ),
                  if (!controller.expanded && rows.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '(${rows.length})',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (controller.expanded) ...[
          const SizedBox(height: 4),
          Text(
            'User-defined keys round-tripped to YAML frontmatter on '
            'export. Empty keys are dropped on save.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < rows.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: TextField(
                    controller: rows[i].key,
                    decoration: const InputDecoration(
                      labelText: 'key',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 6,
                  child: TextField(
                    controller: rows[i].value,
                    decoration: const InputDecoration(
                      labelText: 'value',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove row',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => controller._removeRow(i),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: controller._addRow,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add variable'),
          ),
        ],
      ],
    );
  }
}
