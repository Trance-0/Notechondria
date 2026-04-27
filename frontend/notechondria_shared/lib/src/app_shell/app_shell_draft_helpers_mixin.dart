import 'dart:convert';

import 'package:flutter/widgets.dart';

/// Offline draft store-and-fallback helpers shared across
/// `_AppShellState` in editor / planner / portal. Both methods sit
/// just outside the `setState` boundary — `storeLocalDraft` mutates
/// the in-memory `localDrafts` list (callers persist + rebuild
/// afterward), and `buildOfflineFallbackDraft` is a pure constructor
/// over `localDrafts` for the offline-create + offline-update paths.
///
/// What this mixin owns (2 methods, byte-identical across all three
/// apps before this refactor):
///   - `storeLocalDraft(draft, {incrementCreated})` — moves the
///     draft to the front of `localDrafts` if it's already there
///     (matched by `id`), otherwise inserts it at the front.
///     Replaces `localDrafts` with an unmodifiable list view.
///     Optionally bumps `localStats['local_drafts_created']`.
///   - `buildOfflineFallbackDraft({sourceNote, payload})` — used
///     when the cloud create / update path fails: looks for an
///     existing local draft pointing at `sourceNote.id` (via
///     `metadata.offline_source_note_id`), then builds a fresh
///     local draft via the per-app `buildLocalDraft` hook with
///     `payload` overlaying `sourceNote` defaults.
///
/// What stays per-app (provided as abstract hooks below):
///   - `buildLocalDraft({...})` — the local-draft constructor in
///     each app's `core/local_course_builders.dart`. The shape is
///     identical across apps but it lives in app-private code that
///     the shared mixin can't reach directly.
///   - `decodeNoteMetadata(raw)` — the JSON-decoder for a note's
///     `metadata_json` field. Top-level function in each app's
///     `core/helpers.dart`; same body in all three.
///
/// Usage in `_AppShellState`:
/// ```dart
/// class _AppShellState extends State<AppShell>
///     with AppShellDraftHelpersMixin<AppShell> {
///   @override
///   List<Map<String, dynamic>> get localDrafts => _localDrafts;
///   @override
///   set localDrafts(List<Map<String, dynamic>> v) => _localDrafts = v;
///   @override
///   Map<String, dynamic> get localStats => _localStats;
///   @override
///   set localStats(Map<String, dynamic> v) => _localStats = v;
///
///   @override
///   Map<String, dynamic> decodeNoteMetadata(String raw) =>
///       _decodeNoteMetadata(raw);
///   @override
///   Map<String, dynamic> buildLocalDraft({...}) =>
///       _buildLocalDraft(...);  // forward all named params
/// }
/// ```
mixin AppShellDraftHelpersMixin<W extends StatefulWidget> on State<W> {
  // State the mixin reads AND writes. The getters duplicate the
  // declarations on `AppShellLocalPersistMixin` deliberately — a
  // single override on the State satisfies both mixins, and this
  // mixin shouldn't depend on the persist mixin being present.
  List<Map<String, dynamic>> get localDrafts;
  set localDrafts(List<Map<String, dynamic>> value);
  Map<String, dynamic> get localStats;
  set localStats(Map<String, dynamic> value);

  /// Per-app JSON-decoder for a note's `metadata_json` field.
  /// Lives as a top-level function in each app's `core/helpers.dart`
  /// (same body in all three). The State implementing this mixin
  /// forwards to that function with a one-line override.
  Map<String, dynamic> decodeNoteMetadata(String raw);

  /// Per-app local-draft constructor. Same shape across apps but
  /// lives in app-private code. The State implementing this mixin
  /// forwards every named param to its `_buildLocalDraft`. Defaults
  /// match the per-app implementations exactly so callers can omit
  /// optional args without changing behavior.
  Map<String, dynamic> buildLocalDraft({
    required String title,
    required String content,
    String description = '',
    String editorMode = 'P',
    String? clientDraftId,
    String? createdAt,
    int? id,
    String metadataJson = '{}',
  });

  /// Insert or move-to-front a local draft in `localDrafts`. The
  /// draft is matched by `id`. If found, it's moved to the front
  /// and replaced; if not, it's inserted at the front.
  ///
  /// `incrementCreated: true` bumps `localStats['local_drafts_created']`
  /// — the counter shown in the debug log + Settings stats panel.
  /// Pass true on first creation, false on subsequent edits to the
  /// same draft.
  ///
  /// Replaces `localDrafts` with an `unmodifiable` list view, so
  /// callers can rely on the new reference being immutable until
  /// the next `storeLocalDraft` call.
  ///
  /// Does NOT call `setState` or persist to disk — callers are
  /// responsible for both. Returns the input `draft` for fluent
  /// chaining.
  Map<String, dynamic> storeLocalDraft(
    Map<String, dynamic> draft, {
    bool incrementCreated = false,
  }) {
    final existingIndex =
        localDrafts.indexWhere((item) => item['id'] == draft['id']);
    final nextDrafts = List<Map<String, dynamic>>.from(localDrafts);
    if (existingIndex >= 0) {
      nextDrafts[existingIndex] = draft;
      nextDrafts.insert(0, nextDrafts.removeAt(existingIndex));
    } else {
      nextDrafts.insert(0, draft);
    }
    localDrafts = List<Map<String, dynamic>>.unmodifiable(nextDrafts);
    if (incrementCreated) {
      localStats = {
        ...localStats,
        'local_drafts_created':
            ((localStats['local_drafts_created'] as num?)?.toInt() ?? 0) + 1,
      };
    }
    return draft;
  }

  /// Build a fallback local draft for the offline-create + offline-
  /// update paths. When a cloud `POST /notes/` or `PATCH /notes/<id>/`
  /// fails (no token, network error, server 5xx), the caller wraps
  /// `payload` in this method and stores the result locally; on the
  /// next sync the draft is promoted to the cloud.
  ///
  /// If `sourceNote` is provided AND a local draft already exists
  /// whose `metadata.offline_source_note_id` matches `sourceNote.id`,
  /// the existing draft's `id` / `client_draft_id` / `date_created`
  /// are reused — i.e. subsequent failed updates to the same source
  /// note keep editing the same local draft instead of accumulating
  /// new ones. Title / description / content / editor_mode prefer
  /// `payload` over `sourceNote`, falling back to "Untitled note" /
  /// "" / "# Untitled note\n\n" / "P" respectively.
  Map<String, dynamic> buildOfflineFallbackDraft({
    Map<String, dynamic>? sourceNote,
    required Map<String, dynamic> payload,
  }) {
    final sourceId = (sourceNote?['id'] as num?)?.toInt();
    final existingIndex = sourceId == null
        ? -1
        : localDrafts.indexWhere((item) {
            final metadata = decodeNoteMetadata(
                item['metadata_json']?.toString() ?? '{}');
            return (metadata['offline_source_note_id'] as num?)?.toInt() ==
                sourceId;
          });
    final existingDraft = existingIndex >= 0
        ? Map<String, dynamic>.from(localDrafts[existingIndex])
        : null;
    final metadata = decodeNoteMetadata(
      payload['metadata_json']?.toString() ??
          sourceNote?['metadata_json']?.toString() ??
          '{}',
    );
    if (sourceId != null) {
      metadata['offline_source_note_id'] = sourceId;
    }
    return buildLocalDraft(
      id: (existingDraft?['id'] as num?)?.toInt(),
      clientDraftId: existingDraft?['client_draft_id']?.toString(),
      createdAt: existingDraft?['date_created']?.toString() ??
          sourceNote?['date_created']?.toString(),
      title: payload['title']?.toString() ??
          sourceNote?['title']?.toString() ??
          'Untitled note',
      description: payload['description']?.toString() ??
          sourceNote?['description']?.toString() ??
          '',
      content: payload['content']?.toString() ??
          sourceNote?['content']?.toString() ??
          '# Untitled note\n\n',
      editorMode: payload['editor_mode']?.toString() ??
          sourceNote?['editor_mode']?.toString() ??
          'P',
      metadataJson: jsonEncode(metadata),
    );
  }
}
