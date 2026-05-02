import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/action_feedback.dart';

/// Editable text area for the user's MCP `skill.md`. Surfaced to MCP-
/// connected agents as the `instructions` field of the JSON-RPC
/// `initialize` response. Treat it as a personal prompt playbook:
/// import sources, preferred note formats, target export platforms,
/// and any other agent-facing preferences.
///
/// Shared across editor / planner / portal so the surface stays
/// identical regardless of which app the user opens.
class McpSkillSection extends StatefulWidget {
  const McpSkillSection({
    required this.initialContent,
    required this.onSave,
    super.key,
  });

  final String initialContent;
  final Future<ActionFeedback> Function(String skillMd) onSave;

  @override
  State<McpSkillSection> createState() => _McpSkillSectionState();
}

class _McpSkillSectionState extends State<McpSkillSection> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialContent);
  bool _saving = false;
  String _lastSaved = '';

  @override
  void initState() {
    super.initState();
    _lastSaved = widget.initialContent;
  }

  @override
  void didUpdateWidget(covariant McpSkillSection old) {
    super.didUpdateWidget(old);
    if (old.initialContent != widget.initialContent &&
        _controller.text == old.initialContent) {
      _controller.text = widget.initialContent;
      _lastSaved = widget.initialContent;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final result = await widget.onSave(_controller.text);
      if (!mounted) return;
      if (!result.isError) {
        _lastSaved = _controller.text;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copy() async {
    final text = _controller.text;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('skill.md copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dirty = _controller.text != _lastSaved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Agent skill (skill.md)',
          style: theme.textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Personal playbook for MCP-connected agents. Use this to '
          'describe where to pull notes from (e.g. external sites like '
          'notenextra.trance-0.com), how to format imports, which files '
          'to export, and where to publish them. Sent verbatim as the '
          '`instructions` field of the MCP initialize response.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _controller,
          minLines: 8,
          maxLines: 24,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            hintText:
                '# Import\n- Pull notes from notenextra.trance-0.com once a day...\n\n'
                '# Export\n- Mirror to GitHub Gist as YAML+markdown.\n\n'
                '# Format\n- Wrap math in \$...\$. Tag deadlines with \\#deadline.',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.icon(
              onPressed: dirty && !_saving ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _controller.text.isEmpty ? null : _copy,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy'),
            ),
            const Spacer(),
            if (dirty)
              Text(
                'unsaved changes',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Disabled "Connect to GitHub" card for the experimental data-sync
/// feature. Shared across the three apps; the actual install flow is
/// gated behind backend env vars (`GITHUB_DATA_SYNC_APP_*`) plus a
/// JWT-signing dependency that has not landed yet.
class GithubSyncExperimentalCard extends StatelessWidget {
  const GithubSyncExperimentalCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.science_outlined,
                  size: 18,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Experimental — GitHub Sync',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Push your full account (profile, settings, MCP skill, '
              'courses, notes, custom meta, planner events) to a '
              'GitHub repo you own so you can recover everything if '
              'our server is wiped. Static assets we host (avatars, '
              'attachments, cover images) are referenced by URL, not '
              'committed. Wire-up requires a Notechondria GitHub App '
              'install — see docs/integrations/github-sync.md for the '
              'full flow.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Connect to GitHub (coming soon)'),
            ),
          ],
        ),
      ),
    );
  }
}
