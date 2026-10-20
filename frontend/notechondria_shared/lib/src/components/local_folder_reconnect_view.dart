import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../local_folder/folder_messages.dart';
import '../local_folder/folder_pick_flow.dart';
import '../local_folder/local_folder_boot.dart';
import '../local_folder/local_folder_controller.dart';
import '../models/action_feedback.dart';
import 'auth_dialogs.dart' show FeedbackText;

// The startup reconnect view (local folder design 2.9 step 4, 6.3) and the
// one-line banners of 2.10 rule 5. "Reconnect '<name>'" calls
// `requestPermission` and "Choose '<name>' again" calls the picker, each as
// the first call of its `onPressed` (1.3 step 4); the picked folder's
// folder_id is checked only after the picker returns. Labels come from the
// ARB files (Phase 2); the 1.8 messages stay English.

/// A follow-up the last outcome offers: "Switch to this folder" after a
/// different folder_id, or the copy questions of 3.7.
enum _FollowUp { switchFolder, giveIdentity, checkRemembered, moved }

class LocalFolderReconnectView extends StatefulWidget {
  const LocalFolderReconnectView({
    super.key,
    required this.controller,
    this.onUseBrowserLocal,
    this.onOpened,
  });

  final LocalFolderController controller;

  /// "Use browser-local mode instead": the app's `disconnectFolder()`.
  final Future<void> Function()? onUseBrowserLocal;

  /// Step 3 after the folder opens: the app's `applyAuthPayload` with the
  /// folder payload, outside any startup budget (2.9 "Reconnect").
  final Future<void> Function()? onOpened;

  @override
  State<LocalFolderReconnectView> createState() =>
      _LocalFolderReconnectViewState();
}

class _LocalFolderReconnectViewState extends State<LocalFolderReconnectView> {
  ActionFeedback? _feedback;
  Set<_FollowUp> _followUps = const {};
  bool _busy = false;

  LocalFolderController get _c => widget.controller;

  Future<void> _settle(Future<PickOutcome> pending) async {
    setState(() => _busy = true);
    try {
      final outcome = await pending;
      final message = pickOutcomeMessage(outcome);
      setState(() {
        _feedback = message == null
            ? null
            : ActionFeedback(
                message: scrubSessionSentinels(message), isError: true);
        _followUps = switch (outcome) {
          PickRefused(canSwitch: true) => {_FollowUp.switchFolder},
          PickLooksLikeCopy() => {_FollowUp.giveIdentity},
          PickMayBeCopy() => {
              _FollowUp.checkRemembered,
              _FollowUp.giveIdentity,
              _FollowUp.moved,
            },
          _ => const {},
        };
      });
      await _afterAttempt();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _afterAttempt() async {
    if (_c.state == LocalFolderState.active) {
      await widget.onOpened?.call();
    } else if (_feedback == null && _c.failure != null) {
      setState(() => _feedback = ActionFeedback(
          message: scrubSessionSentinels(_c.failure!.message), isError: true));
    }
  }

  void _reconnect() {
    final reconnecting = _c.reconnect(); // first call: requestPermission
    _settle(reconnecting.then((_) => const PickCancelled()));
  }

  void _chooseAgain() {
    final choosing = _c.chooseAgain(); // first call: the picker
    _settle(choosing);
  }

  void _checkRemembered() {
    final checking = _c.checkRememberedCopy(); // first call: requestPermission
    _settle(checking);
  }

  Future<void> _switch() async {
    setState(() => _busy = true);
    try {
      await _c.switchToPicked();
      setState(() {
        _feedback = null;
        _followUps = const {};
      });
      await _afterAttempt();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context);
        final theme = Theme.of(context);
        final name = _c.folderName;
        final state = _c.state;
        final detail = _c.unavailableDetail(isRead: true);
        final canChoose = state == LocalFolderState.needsPick ||
            (state == LocalFolderState.error &&
                const {'permission', 'restore_handle'}
                    .contains(_c.failure?.process));
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.localFolderViewTitle(name),
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    if (state == LocalFolderState.opening ||
                        state == LocalFolderState.scanning)
                      const LinearProgressIndicator(),
                    if (detail != null)
                      FeedbackText(
                          feedback:
                              ActionFeedback(message: detail, isError: true)),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (state == LocalFolderState.needsPermission)
                        FilledButton(
                          onPressed: _busy ? null : _reconnect,
                          child: Text(l10n.localFolderReconnect(name)),
                        ),
                      if (canChoose)
                        FilledButton(
                          onPressed: _busy ? null : _chooseAgain,
                          child: Text(l10n.localFolderChooseAgain(name)),
                        ),
                      if (_followUps.contains(_FollowUp.switchFolder))
                        OutlinedButton(
                          onPressed: _busy ? null : _switch,
                          child: Text(l10n.localFolderSwitch),
                        ),
                      if (_followUps.contains(_FollowUp.checkRemembered))
                        OutlinedButton(
                          onPressed: _busy ? null : _checkRemembered,
                          child: Text(l10n.localFolderCheckRemembered),
                        ),
                      if (_followUps.contains(_FollowUp.giveIdentity))
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _settle(_c.giveCopyOwnIdentity()),
                          child: Text(l10n.localFolderGiveIdentity),
                        ),
                      if (_followUps.contains(_FollowUp.moved))
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _settle(_c.treatPickedAsMoved()),
                          child: Text(l10n.localFolderSameMoved),
                        ),
                      if (widget.onUseBrowserLocal != null)
                        TextButton(
                          onPressed: _busy ? null : widget.onUseBrowserLocal,
                          child: Text(l10n.localFolderUseBrowserLocal),
                        ),
                    ]),
                    if (_feedback != null) ...[
                      const SizedBox(height: 12),
                      FeedbackText(feedback: _feedback!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The one-line banners of 2.10 rule 5: a folder connected in another tab
/// (this tab in browser-local mode), or disconnected or switched in another
/// tab (this tab in folder mode). Nothing otherwise.
class LocalFolderChangeBanner extends StatelessWidget {
  const LocalFolderChangeBanner({super.key, required this.controller});

  final LocalFolderController controller;

  static String? messageFor(LocalFolderController c) {
    if (c.storageMode == StorageMode.browserOrCloud) {
      final name = c.connectedElsewhere;
      return name == null ? null : LocalFolderMessages.connectedElsewhere(name);
    }
    final reason = c.disconnectReason;
    if (c.state != LocalFolderState.disconnected ||
        reason == null ||
        reason == DisconnectReason.thisTab) {
      return null;
    }
    return c.unavailableDetail(isRead: true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final message = messageFor(controller);
        if (message == null) return const SizedBox.shrink();
        return MaterialBanner(
          content: FeedbackText(
            feedback: ActionFeedback(
                message: scrubSessionSentinels(message), isError: true),
          ),
          actions: const [SizedBox.shrink()],
        );
      },
    );
  }
}
