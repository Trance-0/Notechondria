part of notechondria_frontend;

/// Attachment subsystem for `_NoteEditorDialogState`: pick and upload
/// files from the platform picker, maintain the stored attachment
/// list, delete local attachments, and sniff content-types. Extracted
/// as an extension so `modules/note_editor.dart` stays closer to the
/// AGENTS.md §1.5 1000-line ceiling.
extension _NoteEditorAttachmentsX on _NoteEditorDialogState {
  Future<void> _pickAndUploadAttachment() async {
    final noteId = _note['id'] as int?;
    if (noteId == null) return;

    final xfile = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'All files'),
    ]);
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    if (bytes.length > LocalAttachmentStore.maxBytesPerAttachment) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Attachment not added: '
              'Editor.UI/editor.attachment \u2014 '
              'file exceeds '
              '${LocalAttachmentStore.maxBytesPerAttachment ~/ (1024 * 1024)} '
              'MB per-attachment limit.',
            ),
          ),
        );
      }
      return;
    }

    final filename = xfile.name;
    final contentType = _guessContentType(xfile.name, bytes);
    final isImage = contentType.startsWith('image/');
    final isLocalNote = noteId < 0;
    final uploadFn = widget.onUploadAttachment;

    // Cloud-ready path: we have a saved cloud note id AND an upload
    // callback AND the host actually has a session. If the host rejects
    // mid-upload (no token, network failure), fall through to the
    // offline-queue path so the user never loses the file.
    if (!isLocalNote && uploadFn != null) {
      try {
        final attachment = await uploadFn(noteId, xfile);
        final url = attachment['url']?.toString() ?? '';
        final serverName =
            attachment['original_filename']?.toString() ?? filename;
        final embed = isImage ? '![$serverName]($url)' : '[$serverName]($url)';
        _bodyController.text = '${_bodyController.text}\n\n$embed';
        _handleChanged();
        widget.onLogEvent(
          'Attachment uploaded: Editor.UI/editor.attachment \u2014 '
          '"$serverName" attached to the open note.',
        );
        return;
      } catch (_) {
        // Fall through to the local-store offline-queue path below.
      }
    }

    // Offline / local-draft / upload-failed path: save the bytes to
    // LocalAttachmentStore under a note-uuid-scoped key, embed a
    // compact `local://<uuid>/<filename>` URL into the markdown body,
    // and record a pointer in `metadata_json['queued_attachments']`
    // so the next sync pass can promote it to a real upload. Unlike
    // the 0.1.37 path this never puts base64 into the note body.
    final storeNoteUuid = _resolveStoreNoteUuid();
    try {
      final store = await LocalAttachmentStore.open();
      final record = await store.put(
        noteUuid: storeNoteUuid,
        filename: filename,
        contentType: contentType,
        bytes: bytes,
      );
      final embed = isImage
          ? '![${record.filename}](${record.localUrl})'
          : '[${record.filename}](${record.localUrl})';
      _bodyController.text = '${_bodyController.text}\n\n$embed';
      _handleChanged();

      final metadata =
          _decodeNoteMetadata(_note['metadata_json']?.toString() ?? '{}');
      final queued = List<Map<String, dynamic>>.from(
        (metadata['queued_attachments'] as List?) ?? const [],
      );
      queued.add({
        'filename': record.filename,
        'content_type': record.contentType,
        'size_bytes': record.sizeBytes,
        'local_url': record.localUrl,
        'note_uuid': record.noteUuid,
        'queued_at': record.createdAt.toIso8601String(),
      });
      metadata['queued_attachments'] = queued;
      _note = {
        ..._note,
        'metadata_json': jsonEncode(metadata),
      };
      _handleChanged();

      widget.onLogEvent(
        'Attachment queued for sync: '
        'Editor.Sync.Notes/attachment.queue \u2014 '
        '"${record.filename}" stored at ${record.localUrl} '
        '(${record.sizeBytes} bytes); will upload on next sync.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Attachment saved locally: '
              'Editor.Sync.Notes/attachment.queue \u2014 '
              '"${record.filename}" kept offline under ${record.localUrl}; '
              'it will upload on the next sync.',
            ),
          ),
        );
      }
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      widget.onLogEvent(
        'Attachment not saved locally: '
        'Editor.Sync.Notes/attachment.queue \u2014 $cause.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Attachment not saved: '
              'Editor.Sync.Notes/attachment.queue \u2014 $cause.',
            ),
          ),
        );
      }
    }
  }

  /// Store-key rules:
  ///   - server note with a uuid: use the uuid verbatim.
  ///   - local draft without a server uuid: prefix with `local-`
  ///     + client-draft-id so the namespace never collides.
  String _resolveStoreNoteUuid() {
    final serverUuid = _note['uuid']?.toString() ?? '';
    if (serverUuid.isNotEmpty) return serverUuid;
    final client = _note['client_draft_id']?.toString() ??
        _note['id']?.toString() ??
        '';
    return client.isEmpty ? 'local-unknown' : 'local-$client';
  }

  /// Opens a modal bottom sheet listing every attachment currently
  /// embedded in the note:
  ///   - **Local (queued)**: entries from
  ///     `metadata_json['queued_attachments']` that carry a
  ///     `local_url`. These have a small inline image preview
  ///     (via FutureBuilder + LocalAttachmentStore.getBytes) for
  ///     image/* content-types. Delete removes from the store,
  ///     drops the queue entry, and strips the URL from the body.
  ///   - **Cloud (CDN URLs)**: `http(s)://...` URLs scraped from
  ///     the body. Shown read-only with a copy-link action; to
  ///     delete a cloud attachment the user still goes through
  ///     the server endpoint (not wired here).
  ///
  /// The sheet is populated from a snapshot of the current state;
  /// it does not live-update while open. Closing and re-opening
  /// refreshes the list.
  Future<void> _openAttachmentsList() async {
    final queued = _readQueuedAttachmentEntries();
    final cloudUrls = _extractCloudAttachmentUrls(_bodyController.text);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    'Attachments',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    '${queued.length} local, ${cloudUrls.length} uploaded',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      if (queued.isEmpty && cloudUrls.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              'No attachments in this note yet.',
                            ),
                          ),
                        ),
                      for (final entry in queued)
                        _AttachmentSheetRow(
                          filename: (entry['filename'] ?? '').toString(),
                          sizeBytes:
                              (entry['size_bytes'] as num?)?.toInt() ?? 0,
                          contentType:
                              (entry['content_type'] ?? '').toString(),
                          localUrl:
                              (entry['local_url'] ?? '').toString(),
                          cloudUrl: null,
                          onDelete: () async {
                            Navigator.of(ctx).pop();
                            await _deleteLocalAttachment(entry);
                            if (mounted) await _openAttachmentsList();
                          },
                        ),
                      for (final url in cloudUrls)
                        _AttachmentSheetRow(
                          filename: _filenameFromUrl(url),
                          sizeBytes: 0,
                          contentType: _guessContentType(
                              _filenameFromUrl(url), Uint8List(0)),
                          localUrl: null,
                          cloudUrl: url,
                          onDelete: null,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Reads the list of local queued-attachment entries from the
  /// draft's metadata. Returns an empty list when the note has
  /// never been pickered or when migration stripped the queue.
  List<Map<String, dynamic>> _readQueuedAttachmentEntries() {
    final metadata =
        _decodeNoteMetadata(_note['metadata_json']?.toString() ?? '{}');
    final raw = metadata['queued_attachments'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((entry) =>
            (entry['local_url']?.toString().isNotEmpty ?? false) ||
            (entry['filename']?.toString().isNotEmpty ?? false))
        .toList(growable: false);
  }

  /// Extracts every `http(s)://...` image / link URL embedded in the
  /// note body. Used by the attachments sheet to surface
  /// already-uploaded CDN attachments.
  List<String> _extractCloudAttachmentUrls(String body) {
    final re = RegExp(r'(?:!\[[^\]]*\]|\[[^\]]*\])\((https?://[^)\s]+)\)');
    final seen = <String>{};
    final out = <String>[];
    for (final match in re.allMatches(body)) {
      final url = match.group(1);
      if (url == null) continue;
      if (seen.add(url)) out.add(url);
    }
    return out;
  }

  String _filenameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.isEmpty) return url;
      return uri.pathSegments.last;
    } catch (_) {
      return url;
    }
  }

  /// Removes a local queued-attachment entry from the store, from
  /// the draft's metadata, and strips its `local://` URL from the
  /// note body. Silently no-ops when the store key doesn't exist.
  Future<void> _deleteLocalAttachment(Map<String, dynamic> entry) async {
    final localUrl = entry['local_url']?.toString() ?? '';
    final filename = entry['filename']?.toString() ?? 'attachment';
    if (localUrl.isEmpty) return;
    try {
      final store = await LocalAttachmentStore.open();
      await store.delete(localUrl: localUrl);
    } catch (_) {
      // Silent: user cleanup of a missing blob still succeeds
      // because the metadata strip below removes the queue entry.
    }
    final metadata =
        _decodeNoteMetadata(_note['metadata_json']?.toString() ?? '{}');
    final queued = List<Map<String, dynamic>>.from(
      (metadata['queued_attachments'] as List?) ?? const [],
    );
    queued.removeWhere((e) => e['local_url']?.toString() == localUrl);
    metadata['queued_attachments'] = queued;
    _note = {
      ..._note,
      'metadata_json': jsonEncode(metadata),
    };
    // Remove any markdown line that references this localUrl so the
    // body doesn't render a broken-attachment pill afterwards.
    final lines = _bodyController.text.split('\n');
    _bodyController.text = lines
        .where((line) => !line.contains(localUrl))
        .join('\n');
    _handleChanged();
    widget.onLogEvent(
      'Attachment deleted locally: '
      'Editor.UI/editor.attachment.delete \u2014 '
      '"$filename" removed from note body and local store.',
    );
  }

  /// Best-effort content-type guess from filename extension, falling back
  /// to a short magic-bytes sniff for common image formats when the
  /// extension is missing.
  String _guessContentType(String filename, Uint8List bytes) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      return 'text/markdown';
    }
    if (lower.endsWith('.txt')) return 'text/plain';
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    return 'application/octet-stream';
  }
}
