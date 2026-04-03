part of notechondria_frontend;

/// Portal landing page for auth, cloud routing, and cross-app orchestration.
class _FrontPage extends StatelessWidget {
  const _FrontPage({
    required this.frontPage,
    required this.profile,
    required this.apiBaseUrl,
    required this.onOpenNote,
    required this.onOpenCourse,
  });

  final Map<String, dynamic> frontPage;
  final Map<String, dynamic>? profile;
  final String? apiBaseUrl;
  final Future<void> Function(Map<String, dynamic> note) onOpenNote;
  final Future<void> Function(Map<String, dynamic> course) onOpenCourse;

  bool get _isAuthenticated => profile != null;

  String _appUrl(String app) {
    if (kIsWeb) {
      final base = Uri.base;
      final segments = base.pathSegments.where((segment) => segment.isNotEmpty).toList();
      if (segments.isEmpty) {
        segments.add(app);
      } else {
        segments[segments.length - 1] = app;
      }
      return Uri(
        scheme: base.scheme,
        userInfo: base.userInfo,
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: '/${segments.join('/')}/',
      ).toString();
    }
    return switch (app) {
      'editor' => 'http://localhost:9061/',
      'planner' => 'http://localhost:9062/',
      _ => 'http://localhost:9063/',
    };
  }

  Future<void> _copyUrl(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied $url')),
      );
    }
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final ok = await launchUrlString(url);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final greetingName =
        profile?['username']?.toString() ?? profile?['email']?.toString() ?? 'guest';
    final editorUrl = _appUrl('editor');
    final plannerUrl = _appUrl('planner');
    final publicCourses =
        (frontPage['carousel_courses'] as List<dynamic>? ?? const <dynamic>[]).length;
    final apiUrl = apiBaseUrl ?? _defaultApiBaseUrl();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Portal shell',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  _isAuthenticated
                      ? 'Signed in as $greetingName. Use this app for cloud identity, preferences, and routing into the dedicated editor/planner workspaces.'
                      : 'Signed out. Use this app for sign-in, cloud preferences, and launching the dedicated editor/planner workspaces.',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _PortalStatChip(
                      icon: Icons.cloud_outlined,
                      label: _isAuthenticated ? 'Cloud session ready' : 'Cloud session offline',
                    ),
                    _PortalStatChip(
                      icon: Icons.api_outlined,
                      label: 'API: $apiUrl',
                    ),
                    _PortalStatChip(
                      icon: Icons.library_books_outlined,
                      label: 'Public courses cached: $publicCourses',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 860;
            final children = [
              _PortalRouteCard(
                title: 'Editor workspace',
                description:
                    'Offline-first markdown editing, local drafts, search, sync staging, and note-focused settings.',
                icon: Icons.edit_note_outlined,
                url: editorUrl,
                onOpen: () => _openUrl(context, editorUrl),
                onCopy: () => _copyUrl(context, editorUrl),
              ),
              _PortalRouteCard(
                title: 'Planner workspace',
                description:
                    'Course planning, module discussion surfaces, calendar workflows, and scheduling views.',
                icon: Icons.event_note_outlined,
                url: plannerUrl,
                onOpen: () => _openUrl(context, plannerUrl),
                onCopy: () => _copyUrl(context, plannerUrl),
              ),
            ];
            if (!wide) {
              return Column(children: children.map((child) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: child,
              )).toList());
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: children[0]),
                const SizedBox(width: 16),
                Expanded(child: children[1]),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How this app should evolve',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const _PortalBullet(
                  text: 'Auth lives here: sign in, verification, password reset, and account identity.',
                ),
                const _PortalBullet(
                  text: 'Cloud preferences live here: API target, synced profile settings, and future remote workspace configuration.',
                ),
                const _PortalBullet(
                  text: 'Editor and planner should remain independent deployable apps rather than being re-embedded here as large duplicate flows.',
                ),
                const _PortalBullet(
                  text: 'Future git-like versioning and cross-device orchestration should enter through this shell.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PortalRouteCard extends StatelessWidget {
  const _PortalRouteCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.url,
    required this.onOpen,
    required this.onCopy,
  });

  final String title;
  final String description;
  final IconData icon;
  final String url;
  final VoidCallback onOpen;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(description),
            const SizedBox(height: 12),
            SelectableText(
              url,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open workspace'),
                ),
                OutlinedButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Copy URL'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PortalStatChip extends StatelessWidget {
  const _PortalStatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _PortalBullet extends StatelessWidget {
  const _PortalBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.arrow_right_alt, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
