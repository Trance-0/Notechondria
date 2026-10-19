import 'package:flutter/material.dart';

import '../local_folder/folder_messages.dart';
import '../local_folder/folder_pick_flow.dart';
import '../local_folder/local_folder_boot.dart';
import '../local_folder/local_folder_controller.dart';
import '../local_folder/qualification.dart';
import '../local_folder/storage_mode_client.dart';
import '../models/action_feedback.dart';
import '../utils/format_bytes.dart';
import 'auth_dialogs.dart' show FeedbackText;

// The settings card of folder mode (local folder design 2.7): folder name,
// state, last scan, the folder counts and bytes from the index (F48),
// Rescan, Reconnect or Choose again, Check for updates (the one passthrough,
// Q9), Disconnect, the busy and precedence lines, the "Remember this
// folder" choice (T3), and the collapsed list of cloud-only features.
// Export arrives with the archive bridge (Phase 4). English only until the
// option ships (9.1).

/// The class (c) messages of 4.2, for the "Cloud-only features" list.
const List<String> kCloudOnlyFeatureMessages = [
  LocalFolderMessages.casdoorSignIn,
  LocalFolderMessages.emailSignIn,
  LocalFolderMessages.accountLinking,
  LocalFolderMessages.accountNotCreated,
  LocalFolderMessages.courseNotSubscribed,
  LocalFolderMessages.courseNotTransferred,
  LocalFolderMessages.publicNotesNotSearched,
  LocalFolderMessages.githubAppUnavailable,
  LocalFolderMessages.mcpUnavailable,
  LocalFolderMessages.templateCoursesNotRestored,
];

String localFolderStateLabel(LocalFolderState state) => switch (state) {
      LocalFolderState.opening => 'Opening',
      LocalFolderState.needsPick => 'Needs to be chosen again',
      LocalFolderState.needsPermission => 'Access needs to be granted again',
      LocalFolderState.scanning => 'Reading the folder',
      LocalFolderState.active => 'Open',
      LocalFolderState.error => 'Unavailable',
      LocalFolderState.disconnected => 'Disconnected',
    };

class LocalFolderStatusCard extends StatefulWidget {
  const LocalFolderStatusCard({
    super.key,
    required this.controller,
    this.onDisconnect,
    this.cloudApiBaseUrl,
    this.cloudUser,
    this.qualification,
  });

  final LocalFolderController controller;

  /// The app's `disconnectFolder()` (2.10 rule 4).
  final Future<void> Function()? onDisconnect;

  /// The saved cloud API URL; "Check for updates" is shown when set.
  final String? cloudApiBaseUrl;

  /// The cloud user whose session takes precedence (2.10 rule 2).
  final String? cloudUser;

  /// For the browser label; defaults to the platform probe.
  final LocalFolderQualification? qualification;

  @override
  State<LocalFolderStatusCard> createState() => _LocalFolderStatusCardState();
}

class _LocalFolderStatusCardState extends State<LocalFolderStatusCard> {
  late final LocalFolderQualification _q =
      widget.qualification ?? widget.controller.platform.probe();
  ActionFeedback? _feedback;
  bool _busy = false;

  LocalFolderController get _c => widget.controller;

  void _show(String message, {bool error = false}) => setState(() =>
      _feedback = ActionFeedback(
          message: scrubSessionSentinels(message), isError: error));

  Future<void> _run(Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
    } catch (error) {
      _show(LocalFolderMessages.unavailable('connect', '$error'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reconnect() {
    final reconnecting = _c.reconnect(); // first call: requestPermission
    _run(() => reconnecting);
  }

  void _chooseAgain() {
    final choosing = _c.chooseAgain(); // first call: the picker
    _run(() async {
      // Switching and the copy questions continue in the reconnect view.
      final message = pickOutcomeMessage(await choosing);
      if (message != null) _show(message, error: true);
    });
  }

  void _checkForUpdates(String base) {
    final checking = checkCloudVersion(client: _c.httpClient, apiBaseUrl: base);
    _run(() async {
      final result = await checking;
      _c.log(result.ok ? LocalFolderLogLevel.info : LocalFolderLogLevel.warning,
          result.message);
      _show(result.message, error: !result.ok);
    });
  }

  Widget _line(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text.rich(TextSpan(children: [
          TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: value),
        ])),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final theme = Theme.of(context);
        final counts = _c.index?.counts;
        final state = _c.state;
        final base = widget.cloudApiBaseUrl;
        final user = widget.cloudUser;
        final detail = _c.storageMode == StorageMode.folder
            ? _c.unavailableDetail(isRead: true)
            : null;
        return Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Local folder', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                _line(context, 'Folder', _c.folderName),
                _line(context, 'State', localFolderStateLabel(state)),
                if (_q.browserLabel != null)
                  _line(context, 'Browser', _q.browserLabel!),
                if (_c.index != null)
                  _line(context, 'Last scan', _c.index!.generatedAt),
                if (counts != null)
                  _line(
                      context,
                      'Contents',
                      '${counts.notes} notes, ${counts.trashedNotes} in the '
                          'trash, ${counts.courses} categories, '
                          '${counts.files} files, ${formatBytes(counts.bytes)}'),
                if (_c.cloudSessionWins && user != null)
                  FeedbackText(
                    feedback: ActionFeedback(
                      message: scrubSessionSentinels(
                          LocalFolderMessages.cloudSessionWins(
                              appModuleOf(_c.app), user, _c.folderName)),
                      isError: true,
                    ),
                  ),
                if (_c.busyLine != null)
                  FeedbackText(
                      feedback: ActionFeedback(
                          message: scrubSessionSentinels(_c.busyLine!))),
                if (detail != null)
                  FeedbackText(
                      feedback: ActionFeedback(message: detail, isError: true)),
                if (_c.record != null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _c.record!.remember,
                    onChanged: _busy
                        ? null
                        : (v) => _run(() => _c.setRemember(v ?? false)),
                    title: const Text('Remember this folder on this browser'),
                  ),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (state == LocalFolderState.active)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _run(() => _c.rescan()),
                      child: const Text('Rescan folder'),
                    ),
                  if (state == LocalFolderState.needsPermission)
                    FilledButton(
                      onPressed: _busy ? null : _reconnect,
                      child: Text("Reconnect '${_c.folderName}'"),
                    ),
                  if (state == LocalFolderState.needsPick ||
                      state == LocalFolderState.error)
                    FilledButton(
                      onPressed: _busy ? null : _chooseAgain,
                      child: Text("Choose '${_c.folderName}' again"),
                    ),
                  if (base != null && base.trim().isNotEmpty)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _checkForUpdates(base),
                      child: const Text('Check for updates'),
                    ),
                  if (widget.onDisconnect != null)
                    TextButton(
                      onPressed:
                          _busy ? null : () => _run(widget.onDisconnect!),
                      child: const Text('Disconnect folder'),
                    ),
                ]),
                if (_feedback != null) ...[
                  const SizedBox(height: 8),
                  FeedbackText(feedback: _feedback!),
                ],
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Cloud-only features'),
                  children: [
                    for (final m in kCloudOnlyFeatureMessages)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SelectableText(m,
                            style: theme.textTheme.bodySmall),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
