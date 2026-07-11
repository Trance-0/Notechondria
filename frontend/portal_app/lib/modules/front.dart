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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final greetingName = profile?['username']?.toString() ??
        profile?['email']?.toString() ??
        l10n.frontGreetingGuest;
    final carouselCourses =
        (frontPage['carousel_courses'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
    final recentNotes =
        (frontPage['recent_notes'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
    final heatmap = Map<String, dynamic>.from(
        frontPage['heatmap'] as Map? ?? const <String, dynamic>{});

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Hero greeting with recent-course count.
        _StaggeredFadeIn(
          index: 0,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isAuthenticated
                        ? l10n.frontWelcomeBack(greetingName)
                        : l10n.frontWelcomeGuest,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isAuthenticated ? l10n.frontHeroAuth : l10n.frontHeroAnon,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        // Recent public courses carousel.
        _StaggeredFadeIn(
          index: 1,
          child: _PublicCoursesSection(
            courses: carouselCourses,
            apiBaseUrl: apiBaseUrl,
            onOpenCourse: onOpenCourse,
          ),
        ),
        const SizedBox(height: 18),
        // Heatmap — only meaningful for authenticated users.
        if (_isAuthenticated && heatmap.isNotEmpty)
          _StaggeredFadeIn(
            index: 2,
            child: _HeatmapSection(heatmap: heatmap),
          ),
        if (_isAuthenticated && heatmap.isNotEmpty) const SizedBox(height: 18),
        // Recent public notes — a compact discovery feed.
        if (recentNotes.isNotEmpty)
          _StaggeredFadeIn(
            index: 3,
            child: _RecentPublicNotesSection(
              notes: recentNotes,
              onOpenNote: onOpenNote,
            ),
          ),
      ],
    );
  }
}

/// Horizontally-scrolling carousel of public courses. Each card shows the
/// course cover image (or a theme-colored placeholder) plus title and
/// description. Tapping a card opens the course detail view.
class _PublicCoursesSection extends StatelessWidget {
  const _PublicCoursesSection({
    required this.courses,
    required this.apiBaseUrl,
    required this.onOpenCourse,
  });

  final List<Map<String, dynamic>> courses;
  final String? apiBaseUrl;
  final Future<void> Function(Map<String, dynamic> course) onOpenCourse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_stories_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  AppLocalizations.of(context).frontRecentCourses,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (courses.isEmpty)
              Text(AppLocalizations.of(context).frontNoCourses)
            else
              SizedBox(
                height: 220,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: courses.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final course = courses[index];
                    final coverUrl = _resolveRemoteUrl(
                      course['cover_image_url']?.toString() ?? '',
                      apiBaseUrl: apiBaseUrl,
                    );
                    return SizedBox(
                      width: 240,
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        elevation: 2,
                        child: InkWell(
                          onTap: () => onOpenCourse(course),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: 108,
                                child: coverUrl.isEmpty
                                    ? Container(
                                        color: theme.colorScheme.surfaceVariant,
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.menu_book_outlined,
                                          size: 36,
                                        ),
                                      )
                                    : _RemoteMedia(
                                        imageUrl: coverUrl,
                                        fit: BoxFit.cover,
                                        fallback: Container(
                                          color:
                                              theme.colorScheme.surfaceVariant,
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.menu_book_outlined,
                                            size: 36,
                                          ),
                                        ),
                                      ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        course['title']?.toString() ?? 'Course',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Expanded(
                                        child: Text(
                                          course['description']?.toString() ??
                                              '',
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// GitHub-style contribution heatmap. Renders the backend-computed cells as a
/// scrollable grid of 7-row columns (one column per week). Each cell is tinted
/// by intensity (0-4) with "today" called out by a border.
class _HeatmapSection extends StatelessWidget {
  const _HeatmapSection({required this.heatmap});

  final Map<String, dynamic> heatmap;

  List<List<Map<String, dynamic>>> _groupByWeek(
      List<Map<String, dynamic>> cells) {
    if (cells.isEmpty) {
      return const [];
    }
    final weeks = <List<Map<String, dynamic>>>[];
    var current = <Map<String, dynamic>>[];
    for (final cell in cells) {
      final date = DateTime.tryParse(cell['date']?.toString() ?? '');
      if (date == null) continue;
      // Monday=1..Sunday=7; use (weekday - 1) as the row index.
      final row = date.weekday - 1;
      if (current.isEmpty && row > 0) {
        // Pad the first partial week with placeholders.
        for (var i = 0; i < row; i++) {
          current.add(const {'placeholder': true});
        }
      }
      current.add(cell);
      if (row == 6) {
        weeks.add(current);
        current = <Map<String, dynamic>>[];
      }
    }
    if (current.isNotEmpty) {
      while (current.length < 7) {
        current.add(const {'placeholder': true});
      }
      weeks.add(current);
    }
    return weeks;
  }

  Color _tintFor(BuildContext context, Map<String, dynamic> cell) {
    final theme = Theme.of(context);
    if (cell['placeholder'] == true) {
      return theme.colorScheme.surfaceVariant.withOpacity(0.25);
    }
    final kind = cell['kind']?.toString() ?? 'past';
    final intensity = (cell['intensity'] as num?)?.toInt() ?? 0;
    if (intensity == 0) {
      return theme.colorScheme.surfaceVariant.withOpacity(0.6);
    }
    final base = kind == 'future'
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
    final opacity = 0.25 + (intensity.clamp(0, 4) * 0.18);
    return base.withOpacity(opacity);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cells = (heatmap['cells'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
    final weeks = _groupByWeek(cells);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  AppLocalizations.of(context).frontActivityHeatmap,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  heatmap['today']?.toString() ?? '',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context).frontHeatmapLegend,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            // The payload spans ~53 weeks; fixed 13px cells always
            // overflowed (mobile) or left the card half-empty (desktop).
            // Instead auto-fit: show the most recent weeks that fit and
            // scale the cells so the grid spans the available width in a
            // fixed-height band on both mobile and desktop.
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 3.0;
                const minCell = 9.0;
                const maxCell = 16.0;
                final available = constraints.maxWidth;
                if (weeks.isEmpty || available <= 0) {
                  return const SizedBox.shrink();
                }
                // Most weeks that fit at the minimum cell size; show the
                // most recent ones (trim from the front).
                final maxWeeks =
                    ((available + gap) / (minCell + gap)).floor().clamp(1, 9999);
                final shownWeeks = weeks.length <= maxWeeks
                    ? weeks
                    : weeks.sublist(weeks.length - maxWeeks);
                final rawCell =
                    (available - (shownWeeks.length - 1) * gap) /
                        shownWeeks.length;
                final cell = rawCell.clamp(minCell, maxCell);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var w = 0; w < shownWeeks.length; w++)
                      Padding(
                        padding: EdgeInsets.only(
                            right: w == shownWeeks.length - 1 ? 0 : gap),
                        child: Column(
                          children: [
                            for (final c in shownWeeks[w])
                              Container(
                                width: cell,
                                height: cell,
                                margin: const EdgeInsets.only(bottom: gap),
                                decoration: BoxDecoration(
                                  color: _tintFor(context, c),
                                  borderRadius: BorderRadius.circular(3),
                                  border: c['is_today'] == true
                                      ? Border.all(
                                          color: theme.colorScheme.onSurface,
                                          width: 1,
                                        )
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact list of recent public notes as a discovery feed on the front page.
class _RecentPublicNotesSection extends StatelessWidget {
  const _RecentPublicNotesSection({
    required this.notes,
    required this.onOpenNote,
  });

  final List<Map<String, dynamic>> notes;
  final Future<void> Function(Map<String, dynamic> note) onOpenNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.article_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  AppLocalizations.of(context).frontRecentNotes,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final note in notes.take(6))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(
                  note['title']?.toString() ??
                      AppLocalizations.of(context).noteUntitled,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  note['description']?.toString() ??
                      note['excerpt']?.toString() ??
                      '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.arrow_forward_outlined, size: 18),
                onTap: () => onOpenNote(note),
              ),
          ],
        ),
      ),
    );
  }
}
