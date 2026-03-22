part of notechondria_frontend;

/// Front page module showing the hero, heatmap, and public recommendation feed.
class _FrontPage extends StatelessWidget {
  const _FrontPage({
    required this.frontPage,
    required this.profile,
    required this.onOpenNote,
  });

  final Map<String, dynamic> frontPage;
  final Map<String, dynamic>? profile;
  final Future<void> Function(Map<String, dynamic> note) onOpenNote;

  @override
  Widget build(BuildContext context) {
    final defaultCourse =
        frontPage['default_course'] as Map<String, dynamic>? ?? const {};
    final heatmap = frontPage['heatmap'] as Map<String, dynamic>?;
    final recommendedNotes =
        (frontPage['recommended_notes'] as List<dynamic>? ??
                frontPage['recent_notes'] as List<dynamic>? ??
                const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
    final greetingName =
        profile?['username']?.toString() ?? profile?['email']?.toString();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _FrontHero(defaultCourse: defaultCourse),
        if (greetingName != null && greetingName.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Hello, $greetingName',
              style: Theme.of(context).textTheme.headlineSmall),
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
        const SizedBox(height: 20),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Public notes shown here come from the current recommendation feed. Use Course for collections and Activity for future events.',
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Recommended public notes',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final note in recommendedNotes)
          Card(
            child: ListTile(
              title: Text(note['title']?.toString() ?? 'Untitled note'),
              subtitle: Text(note['excerpt']?.toString() ?? ''),
              trailing: const Icon(Icons.arrow_forward_outlined),
              onTap: () async => onOpenNote(note),
            ),
          ),
      ],
    );
  }
}

/// Hero banner for the seeded default course.
class _FrontHero extends StatelessWidget {
  const _FrontHero({required this.defaultCourse});

  final Map<String, dynamic> defaultCourse;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1D4ED8), Color(0xFFEA580C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            defaultCourse['title']?.toString() ?? 'Default course',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            defaultCourse['description']?.toString() ??
                'Sample course data will appear here.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFFE0F2FE),
                ),
          ),
          const SizedBox(height: 18),
          if ((defaultCourse['cover_image_url']?.toString() ?? '').isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.network(
                defaultCourse['cover_image_url'].toString(),
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
        ],
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
