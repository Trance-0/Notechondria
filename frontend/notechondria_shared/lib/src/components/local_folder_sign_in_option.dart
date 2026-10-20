import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../local_folder/folder_messages.dart';
import '../local_folder/folder_pick_flow.dart';
import '../local_folder/handle_store.dart';
import '../local_folder/local_folder_boot.dart';
import '../local_folder/local_folder_controller.dart';
import '../local_folder/qualification.dart';
import '../models/action_feedback.dart';
import 'auth_dialogs.dart' show FeedbackText;

// "Use a local folder (no account)" for the `AuthHub.localFolderOption`
// slot (local folder design 1.3). Each browser call that needs transient
// user activation is the first call of its own click handler: the picker in
// the option or in the notice's "Choose folder", `requestPermission` in
// "Use the connected folder". Labels come from the ARB files (Phase 2); the
// 1.8 messages stay English. The constants below are the English labels.

const String kLocalFolderOptionLabel = 'Use a local folder (no account)';
const String kLocalFolderOptionLine = 'Notes, courses, and planner data are '
    'saved as files in a folder you choose. No account is needed, and none of '
    'this data is sent to the Notechondria server.';
const String kRememberFolderLabel = 'Remember this folder on this browser';

String useConnectedFolderLabel(String name) => "Use the connected folder '$name'";

class LocalFolderSignInOption extends StatefulWidget {
  const LocalFolderSignInOption({
    super.key,
    required this.controller,
    this.qualification,
    this.onConnected,
  });

  final LocalFolderController controller;

  /// Defaults to the platform probe (1.2); tests inject one.
  final LocalFolderQualification? qualification;

  /// The app's connect step once the folder is `active`: the 7.1 push and
  /// `applyAuthPayload` with the folder payload (per-app, Phases 2 and 3).
  final Future<void> Function()? onConnected;

  @override
  State<LocalFolderSignInOption> createState() =>
      _LocalFolderSignInOptionState();
}

class _LocalFolderSignInOptionState extends State<LocalFolderSignInOption> {
  late final LocalFolderQualification _q =
      widget.qualification ?? widget.controller.platform.probe();
  late bool _remember =
      rememberDefaultForOrigin(widget.controller.platform.origin);
  bool _noticeAcked =
      LocalFolderBoot.snapshot?.containsKey(kLocalFolderNoticeAckKey) ?? false;
  bool _busy = false;
  ConnectPick? _pending;
  ActionFeedback? _feedback;

  LocalFolderController get _c => widget.controller;
  bool get _needsNotice =>
      needsSharedOriginNotice(_c.platform.origin) && !_noticeAcked;

  /// The connected folder of 2.10, when this app is not using it. After a
  /// Disconnect in this tab the shared key is gone, so there is none.
  StorageModeRecord? get _connected =>
      _c.storageMode == StorageMode.folder ||
              _c.disconnectReason == DisconnectReason.thisTab
          ? null
          : _c.record;

  @override
  void initState() {
    super.initState();
    if (_connected?.remember ?? false) _c.preloadRememberedHandle();
  }

  void _show(String message, {bool error = true}) =>
      setState(() => _feedback = ActionFeedback(
          message: scrubSessionSentinels(message), isError: error));

  Future<void> _run(Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
    } catch (error) {
      // connectPicked states its refusals as 1.8 StateErrors; anything else
      // came from the picker or the folder.
      _show(error is StateError
          ? error.message
          : LocalFolderMessages.pickFailed('$error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onPressed() {
    if (_connected != null) {
      final using = _c.useConnectedFolder(); // first call (1.3, T3)
      _run(() async => _afterOutcome(await using));
      return;
    }
    if (_needsNotice) {
      _openNotice(); // only opens the dialog (1.3 step 1)
      return;
    }
    final picking = _c.pickForConnect(); // first call (1.3 step 2)
    _run(() async => _afterPick(await picking));
  }

  Future<void> _openNotice() async {
    final l10n = AppLocalizations.of(context);
    final picking = await showDialog<Future<ConnectPick?>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(l10n.localFolderNoticeTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FeedbackText(
                feedback: ActionFeedback(
                    message: LocalFolderMessages.sharedOriginNotice(
                        _c.platform.origin.origin),
                    isError: true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _remember,
                onChanged: (v) => setDialog(() => _remember = v ?? false),
                title: Text(l10n.localFolderRemember),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                final picking = _c.pickForConnect(); // first call
                Navigator.of(context).pop(picking);
              },
              child: Text(l10n.localFolderChooseFolder),
            ),
          ],
        ),
      ),
    );
    if (picking == null || !mounted) return;
    setState(() => _noticeAcked = true);
    await _run(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kLocalFolderNoticeAckKey,
          _c.now().toUtc().toIso8601String());
      await _afterPick(await picking);
    });
  }

  Future<void> _afterPick(ConnectPick? pick) async {
    if (pick == null) return; // AbortError: the option stays as it was
    if (pick.refusal != null) return _show(pick.refusal!);
    if (pick.manifest != null) return _connect(pick);
    setState(() {
      _pending = pick;
      _feedback = pick.isEmpty
          ? null
          : ActionFeedback(
              message: scrubSessionSentinels(LocalFolderMessages.connectNonEmpty(
                  pick.folder.name, pick.entryCount)),
              isError: true);
    });
  }

  Future<void> _connect(ConnectPick pick, {bool confirmed = false}) async {
    setState(() => _pending = null);
    await _c.connectPicked(pick,
        remember: _remember, confirmedEntryCount: confirmed);
    await _afterOpen();
  }

  Future<void> _afterOutcome(PickOutcome outcome) async {
    switch (outcome) {
      case PickOpened():
        await _afterOpen();
      case PickCancelled():
        break;
      case PickFailed(:final message):
      case PickRefused(:final message):
      case PickLooksLikeCopy(:final message):
      case PickMayBeCopy(:final message):
        // Switching and the copy questions continue in the reconnect view.
        _show(message);
    }
  }

  Future<void> _afterOpen() async {
    if (_c.state == LocalFolderState.active) {
      setState(() => _feedback = null);
      await widget.onConnected?.call();
      return;
    }
    _show(_c.failure?.message ??
        _c.unavailableDetail(isRead: true) ??
        LocalFolderMessages.unavailable('connect', 'the folder did not open'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final connected = _connected;
    final pending = _pending;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _q.qualified && !_busy ? _onPressed : null,
            icon: const Icon(Icons.folder_open_outlined, size: 20),
            label: Text(connected == null
                ? l10n.localFolderOptionLabel
                : l10n.localFolderUseConnected(connected.folderName)),
          ),
        ),
        const SizedBox(height: 6),
        if (_q.qualified) ...[
          Text(l10n.localFolderOptionLine, style: theme.textTheme.bodySmall),
          if (connected == null && !needsSharedOriginNotice(_c.platform.origin))
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _remember,
              onChanged: (v) => setState(() => _remember = v ?? false),
              title: Text(l10n.localFolderRemember),
            ),
        ] else ...[
          FeedbackText(
              feedback: ActionFeedback(message: _q.message!, isError: true)),
          const SizedBox(height: 4),
          Text(l10n.localFolderFallbackLine, style: theme.textTheme.bodySmall),
        ],
        if (pending != null)
          Wrap(spacing: 8, children: [
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => _connect(pending, confirmed: !pending.isEmpty)),
              child: Text(pending.isEmpty
                  ? l10n.localFolderStartEmpty
                  : l10n.localFolderConnectAnyway(pending.folder.name)),
            ),
            TextButton(
              onPressed: () => setState(() {
                _pending = null;
                _feedback = null;
              }),
              child: Text(l10n.commonCancel),
            ),
          ]),
        if (_feedback != null) ...[
          const SizedBox(height: 6),
          FeedbackText(feedback: _feedback!),
        ],
      ],
    );
  }
}
