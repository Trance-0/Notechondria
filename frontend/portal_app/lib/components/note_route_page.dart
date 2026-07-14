part of notechondria_frontend;

/// Full-page, URL-addressable note view behind `#/note/<uuid>` (0.1.179).
///
/// Two entry paths share this widget:
///  - **In-session** pushes arrive with the note `preloaded` and the auth
///    `token`, so nothing refetches.
///  - **Cold-start deep links** fetch by uuid through the shared client —
///    anonymously that reads public notes; with a token it also reads the
///    owner's and subscribed courses' private notes (the backend policy).
class _NoteRoutePage extends StatefulWidget {
  const _NoteRoutePage({
    required this.client,
    required this.noteUuid,
    this.token,
    this.preloaded,
  });

  final NotechondriaClient client;
  final String noteUuid;
  final String? token;
  final Map<String, dynamic>? preloaded;

  @override
  State<_NoteRoutePage> createState() => _NoteRoutePageState();
}

class _NoteRoutePageState extends State<_NoteRoutePage> {
  Map<String, dynamic>? _note;
  String? _error;

  @override
  void initState() {
    super.initState();
    _note = widget.preloaded;
    if (_note == null) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final detail = await widget.client
          .getNoteDetailByUuid(widget.noteUuid, token: widget.token);
      if (!mounted) return;
      setState(() => _note = detail);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Same in-course link semantics as the in-shell viewer, but each hop
  /// pushes another `/note/<uuid>` route so the URL always identifies the
  /// note on screen and browser Back walks the chain.
  Future<void> _followLink(Map<String, dynamic> fromNote, String href) async {
    final raw = href.trim();
    if (raw.isEmpty) return;
    if (_isExternalLink(raw)) {
      url_strategy.browserRedirect(raw);
      return;
    }
    final courseId = _noteCourseIdOf(fromNote);
    if (courseId == null) return;
    List<Map<String, dynamic>> siblings;
    try {
      siblings =
          await widget.client.getCourseNotes(courseId, token: widget.token);
    } catch (_) {
      return;
    }
    final target = _matchNoteLinkTarget(fromNote, raw, siblings);
    final uuid = target?['uuid']?.toString() ?? '';
    if (uuid.isEmpty || !mounted) return;
    await Navigator.of(context).pushNamed(
      '/note/$uuid',
      arguments: <String, dynamic>{'token': widget.token},
    );
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    if (note != null) {
      return _NoteViewerDialog(note: note, onFollowLink: _followLink);
    }
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This note may be private — sign in from the app to '
                      'read owned or subscribed content.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
