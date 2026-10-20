import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
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
// Export arrives with the archive bridge (Phase 4). Labels come from the
// ARB files (Phase 2); the 1.8 messages stay English.

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

/// The state line of the card, localized.
String localFolderStateText(AppLocalizations l10n, LocalFolderState state) =>
    switch (state) {
      LocalFolderState.opening => l10n.localFolderStateOpening,
      LocalFolderState.needsPick => l10n.localFolderStateNeedsPick,
      LocalFolderState.needsPermission => l10n.localFolderStateNeedsPermission,
      LocalFolderState.scanning => l10n.localFolderStateScanning,
      LocalFolderState.active => l10n.localFolderStateActive,
      LocalFolderState.error => l10n.localFolderStateError,
      LocalFolderState.disconnected => l10n.localFolderStateDisconnected,
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
        final l10n = AppLocalizations.of(context);
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
                Text(l10n.localFolderCardTitle,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                _line(context, l10n.localFolderFieldFolder, _c.folderName),
                _line(context, l10n.localFolderFieldState,
                    localFolderStateText(l10n, state)),
                if (_q.browserLabel != null)
                  _line(context, l10n.localFolderFieldBrowser, _q.browserLabel!),
                if (_c.index != null)
                  _line(context, l10n.localFolderFieldLastScan,
                      _c.index!.generatedAt),
                if (counts != null)
                  _line(
                      context,
                      l10n.localFolderFieldContents,
                      l10n.localFolderContents(
                          counts.notes,
                          counts.trashedNotes,
                          counts.courses,
                          counts.files,
                          formatBytes(counts.bytes))),
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
                    title: Text(l10n.localFolderRemember),
                  ),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (state == LocalFolderState.active)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _run(() => _c.rescan()),
                      child: Text(l10n.localFolderRescan),
                    ),
                  if (state == LocalFolderState.needsPermission)
                    FilledButton(
                      onPressed: _busy ? null : _reconnect,
                      child: Text(l10n.localFolderReconnect(_c.folderName)),
                    ),
                  if (state == LocalFolderState.needsPick ||
                      state == LocalFolderState.error)
                    FilledButton(
                      onPressed: _busy ? null : _chooseAgain,
                      child: Text(l10n.localFolderChooseAgain(_c.folderName)),
                    ),
                  if (base != null && base.trim().isNotEmpty)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _checkForUpdates(base),
                      child: Text(l10n.localFolderCheckUpdates),
                    ),
                  if (widget.onDisconnect != null)
                    TextButton(
                      onPressed:
                          _busy ? null : () => _run(widget.onDisconnect!),
                      child: Text(l10n.localFolderDisconnect),
                    ),
                ]),
                if (_feedback != null) ...[
                  const SizedBox(height: 8),
                  FeedbackText(feedback: _feedback!),
                ],
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(l10n.localFolderCloudOnly),
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
