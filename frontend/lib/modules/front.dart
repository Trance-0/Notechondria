part of notechondria_frontend;

/// Front page module showing the carousel, heatmap, and public recommendation feed.
class _FrontPage extends StatefulWidget {
  const _FrontPage({
    required this.frontPage,
    required this.profile,
    required this.apiBaseUrl,
    required this.onOpenNote,
    required this.onOpenCourse,
    required this.onRestoreTemplateCourses,
  });

  final Map<String, dynamic> frontPage;
  final Map<String, dynamic>? profile;
  final String? apiBaseUrl;
  final Future<void> Function(Map<String, dynamic> note) onOpenNote;
  final Future<void> Function(Map<String, dynamic> course) onOpenCourse;
  final Future<ActionFeedback> Function() onRestoreTemplateCourses;

  @override
  State<_FrontPage> createState() => _FrontPageState();
}

class _FrontPageState extends State<_FrontPage> {
  final PageController _pageController = PageController(viewportFraction: 0.92);
  Timer? _autoSlideTimer;
  int _currentPage = 0;

  bool get _enableAutoSlide {
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    return !bindingName.contains('TestWidgetsFlutterBinding');
  }

  List<Map<String, dynamic>> get _carouselCourses {
    final rows = (widget.frontPage['carousel_courses'] as List<dynamic>? ??
            widget.frontPage['collections'] as List<dynamic>? ??
            const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    if (rows.isEmpty) {
      final fallback =
          widget.frontPage['default_course'] as Map<String, dynamic>? ?? const {};
      if (fallback.isNotEmpty) {
        rows.add(Map<String, dynamic>.from(fallback));
      }
    }
    return rows;
  }

  @override
  void initState() {
    super.initState();
    if (_enableAutoSlide) {
      _startAutoSlide();
    }
  }

  @override
  void didUpdateWidget(covariant _FrontPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frontPage != widget.frontPage) {
      _currentPage = 0;
      _restartAutoSlide();
    }
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final courses = _carouselCourses;
      if (!_pageController.hasClients || courses.length <= 1) {
        return;
      }
      final nextPage = (_currentPage + 1) % courses.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _restartAutoSlide() {
    if (!_enableAutoSlide) {
      return;
    }
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
    _startAutoSlide();
  }

  @override
  Widget build(BuildContext context) {
    final heatmap = widget.frontPage['heatmap'] as Map<String, dynamic>?;
    final recommendedNotes =
        (widget.frontPage['recommended_notes'] as List<dynamic>? ??
                widget.frontPage['recent_notes'] as List<dynamic>? ??
                const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
    final greetingName =
        widget.profile?['username']?.toString() ?? widget.profile?['email']?.toString();
    final isAdmin = widget.profile?['is_superuser'] == true;
    final carouselCourses = _carouselCourses;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (carouselCourses.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Public courses are unavailable right now. You can still use local drafts, local courses, and settings while the backend is offline.',
              ),
            ),
          )
        else
          _CourseCarousel(
            courses: carouselCourses,
            pageController: _pageController,
            currentPage: _currentPage,
            apiBaseUrl: widget.apiBaseUrl,
            showRestoreButton: isAdmin,
            onPageChanged: (index) => setState(() => _currentPage = index),
            onOpenCourse: widget.onOpenCourse,
            onRestoreTemplateCourses: widget.onRestoreTemplateCourses,
          ),
        if (greetingName != null && greetingName.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Hello, $greetingName',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ],
        const SizedBox(height: 20),
        if (heatmap != null)
          _HeatmapCard(heatmap: heatmap)
        else
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child:
                  Text('Sign in to see the progress heatmap and future plan.'),
            ),
          ),
        const SizedBox(height: 24),
        Text(
          'Recent public notes',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (recommendedNotes.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No public notes are cached yet. Connect to the backend to refresh recommendations.',
              ),
            ),
          ),
        for (final note in recommendedNotes)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _FrontNoteCard(
              note: note,
              apiBaseUrl: widget.apiBaseUrl,
              onTap: () {
                widget.onOpenNote(note);
              },
            ),
          ),
      ],
    );
  }
}

class _CourseCarousel extends StatelessWidget {
  const _CourseCarousel({
    required this.courses,
    required this.pageController,
    required this.currentPage,
    required this.apiBaseUrl,
    required this.showRestoreButton,
    required this.onPageChanged,
    required this.onOpenCourse,
    required this.onRestoreTemplateCourses,
  });

  final List<Map<String, dynamic>> courses;
  final PageController pageController;
  final int currentPage;
  final String? apiBaseUrl;
  final bool showRestoreButton;
  final ValueChanged<int> onPageChanged;
  final Future<void> Function(Map<String, dynamic> course) onOpenCourse;
  final Future<ActionFeedback> Function() onRestoreTemplateCourses;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showRestoreButton)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final feedback = await onRestoreTemplateCourses();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(feedback.message)),
                    );
                  }
                },
                icon: const Icon(Icons.restart_alt_outlined),
                label: const Text('Restore templates'),
              ),
            ),
          ),
        SizedBox(
          height: 320,
          child: PageView.builder(
            controller: pageController,
            itemCount: courses.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, index) {
              final course = courses[index];
              final coverUrl = _resolveRemoteUrl(
                course['cover_image_url']?.toString() ?? '',
                apiBaseUrl: apiBaseUrl,
              );
              final owner =
                  Map<String, dynamic>.from(course['owner'] as Map? ?? const {});
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () {
                    onOpenCourse(course);
                  },
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF0F172A),
                          Color(0xFF0F766E),
                          Color(0xFFF59E0B),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final compact = constraints.maxWidth < 340;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: compact ? 8 : 10,
                                        vertical: compact ? 5 : 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.14),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        course['is_subscribed'] == true
                                            ? 'Subscribed'
                                            : 'Course Preview',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    SizedBox(height: compact ? 12 : 18),
                                    Text(
                                      course['title']?.toString() ?? 'Course',
                                      maxLines: compact ? 2 : 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: (compact
                                              ? Theme.of(context)
                                                  .textTheme
                                                  .headlineSmall
                                              : Theme.of(context)
                                                  .textTheme
                                                  .headlineMedium)
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    SizedBox(height: compact ? 8 : 12),
                                    Text(
                                      course['description']?.toString() ??
                                          'Open the course to read notes and previews.',
                                      maxLines: compact ? 3 : 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: (compact
                                              ? Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                              : Theme.of(context)
                                                  .textTheme
                                                  .bodyLarge)
                                          ?.copyWith(
                                            color: const Color(0xFFF8FAFC),
                                            height: compact ? 1.3 : 1.45,
                                          ),
                                    ),
                                    const Spacer(),
                                    Wrap(
                                      spacing: compact ? 8 : 12,
                                      runSpacing: compact ? 6 : 8,
                                      children: [
                                        _CarouselMetric(
                                          label: 'Subscribers',
                                          value:
                                              '${course['subscriber_count'] ?? 0}',
                                          compact: compact,
                                        ),
                                        if ((owner['username']?.toString() ?? '')
                                            .isNotEmpty)
                                          _CarouselMetric(
                                            label: 'By',
                                            value: owner['username'].toString(),
                                            compact: compact,
                                          ),
                                        if ((course['last_opened_at']?.toString() ?? '')
                                            .isNotEmpty)
                                          _CarouselMetric(
                                            label: 'Last Opened',
                                            value: _formatCompactTimestamp(
                                              course['last_opened_at']
                                                  .toString(),
                                            ),
                                            compact: compact,
                                          ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: Container(
                                color: Colors.white.withOpacity(0.1),
                                child: coverUrl.isEmpty
                                    ? Center(
                                        child: Icon(
                                          Icons.auto_stories_outlined,
                                          size: 72,
                                          color: Colors.white.withOpacity(0.9),
                                        ),
                                      )
                                    : Image.network(
                                        coverUrl,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < courses.length; index++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 8,
                width: currentPage == index ? 28 : 8,
                decoration: BoxDecoration(
                  color: currentPage == index
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CarouselMetric extends StatelessWidget {
  const _CarouselMetric({
    required this.label,
    required this.value,
    this.compact = false,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: (compact
                  ? Theme.of(context).textTheme.labelSmall
                  : Theme.of(context).textTheme.labelMedium)
              ?.copyWith(
                color: Colors.white.withOpacity(0.8),
              ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (compact
                  ? Theme.of(context).textTheme.titleSmall
                  : Theme.of(context).textTheme.titleMedium)
              ?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _FrontNoteCard extends StatelessWidget {
  const _FrontNoteCard({
    required this.note,
    required this.apiBaseUrl,
    required this.onTap,
  });

  final Map<String, dynamic> note;
  final String? apiBaseUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final author = Map<String, dynamic>.from(note['author'] as Map? ?? const {});
    final course = Map<String, dynamic>.from(note['course'] as Map? ?? const {});
    final previewLines = (note['preview_lines'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList();
    final authorName = author['username']?.toString() ?? '';
    final avatarFallback = authorName.isEmpty ? 'N' : authorName.substring(0, 1);
    final avatarUrl = _resolveRemoteUrl(
      author['image_url']?.toString() ?? '',
      apiBaseUrl: apiBaseUrl,
    );
    final subtitleParts = <String>[
      if ((course['title']?.toString() ?? '').isNotEmpty) course['title'].toString(),
    ];
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.brightness == Brightness.dark
          ? theme.colorScheme.surfaceVariant.withOpacity(0.42)
          : theme.colorScheme.surfaceVariant.withOpacity(0.22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _RemoteAvatar(
                    radius: 18,
                    imageUrl: avatarUrl,
                    fallbackLabel: avatarFallback,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      authorName.isEmpty ? 'Anonymous' : authorName,
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    _formatCompactTimestamp(note['last_edit']?.toString() ?? ''),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                note['title']?.toString() ?? 'Untitled note',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
              ),
              if (subtitleParts.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtitleParts.join(' · '),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              if ((note['description']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  note['description'].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                previewLines.isEmpty
                    ? (note['excerpt']?.toString() ?? '')
                    : previewLines.join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.55,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card container for the centered progress-and-plan heatmap.
class _HeatmapCard extends StatelessWidget {
  const _HeatmapCard({required this.heatmap});

  final Map<String, dynamic> heatmap;

  @override
  Widget build(BuildContext context) {
    final cells = (heatmap['cells'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progress + plan heatmap',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text(
              'Past note creation and edit volume is blue. Future registered events are green. Today is centered.',
            ),
            const SizedBox(height: 14),
            _HeatmapGrid(cells: cells),
          ],
        ),
      ),
    );
  }
}

/// Scrollable GitHub-style heatmap grid that auto-centers on today.
class _HeatmapGrid extends StatefulWidget {
  const _HeatmapGrid({required this.cells});

  final List<Map<String, dynamic>> cells;

  @override
  State<_HeatmapGrid> createState() => _HeatmapGridState();
}

class _HeatmapGridState extends State<_HeatmapGrid> {
  final ScrollController _controller = ScrollController();
  bool _didCenter = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cellSize = 14.0;
    const gap = 4.0;
    final columns = _buildColumns(widget.cells);
    final todayColumn = _todayColumnIndex(columns);

    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_didCenter || !_controller.hasClients || todayColumn < 0) {
            return;
          }
          final cellSpan = cellSize + gap;
          final targetOffset = math.max(
            0.0,
            (todayColumn * cellSpan) -
                (constraints.maxWidth / 2) +
                (cellSpan / 2),
          );
          _controller.jumpTo(
            math.min(targetOffset, _controller.position.maxScrollExtent),
          );
          _didCenter = true;
        });

        return SizedBox(
          height: 7 * (cellSize + gap) + 28,
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final column in columns)
                  Padding(
                    padding: const EdgeInsets.only(right: gap),
                    child: Column(
                      children: [
                        for (final cell in column)
                          Padding(
                            padding: const EdgeInsets.only(bottom: gap),
                            child: Tooltip(
                              message: _tooltip(cell),
                              child: Container(
                                width: cellSize,
                                height: cellSize,
                                decoration: BoxDecoration(
                                  color: _cellColor(cell),
                                  borderRadius: BorderRadius.circular(3),
                                  border: cell['is_today'] == true
                                      ? Border.all(
                                          color: Colors.black87, width: 1.3)
                                      : null,
                                ),
                              ),
                            ),
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

  List<List<Map<String, dynamic>>> _buildColumns(
      List<Map<String, dynamic>> cells) {
    final sorted = List<Map<String, dynamic>>.from(cells)
      ..sort((a, b) => a['date'].toString().compareTo(b['date'].toString()));
    final columns = <List<Map<String, dynamic>>>[];
    for (var index = 0; index < sorted.length; index += 7) {
      final slice = sorted.skip(index).take(7).toList();
      while (slice.length < 7) {
        slice.add({
          'date': '',
          'kind': 'empty',
          'past_value': 0,
          'future_value': 0,
          'is_today': false,
        });
      }
      columns.add(slice);
    }
    return columns;
  }

  int _todayColumnIndex(List<List<Map<String, dynamic>>> columns) {
    for (var index = 0; index < columns.length; index++) {
      if (columns[index].any((cell) => cell['is_today'] == true)) {
        return index;
      }
    }
    return -1;
  }

  Color _cellColor(Map<String, dynamic> cell) {
    final kind = cell['kind']?.toString() ?? 'empty';
    if (kind == 'empty') {
      return const Color(0xFFF1F5F9);
    }
    if (kind == 'future') {
      final value = (cell['future_value'] as num?)?.toDouble() ?? 0;
      return Color.lerp(
        const Color(0xFFD1FAE5),
        const Color(0xFF166534),
        math.min(value / 4, 1),
      )!;
    }
    final value = (cell['past_value'] as num?)?.toDouble() ?? 0;
    return Color.lerp(
      const Color(0xFFE0F2FE),
      const Color(0xFF1D4ED8),
      math.min(value / 4, 1),
    )!;
  }

  String _tooltip(Map<String, dynamic> cell) {
    if ((cell['date']?.toString() ?? '').isEmpty) {
      return '';
    }
    return '${cell['date']}\nPast words: ${cell['past_value']}\nFuture weight: ${cell['future_value']}';
  }
}
