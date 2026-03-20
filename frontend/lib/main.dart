import 'package:flutter/material.dart';

void main() {
  runApp(const NotechondriaApp());
}

class NotechondriaApp extends StatelessWidget {
  const NotechondriaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notechondria Learning Canvas',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  late String _selectedCourse;

  final List<String> _courses = const [
    'Python Foundations',
    'System Design Reading Sprint',
    'Data Structures Interview Plan',
  ];

  static const List<String> _titles = [
    'Front Page',
    'Learner View',
    'Course View',
    'Activity View',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    _selectedCourse = _courses.first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
      ),
      body: _buildPage(_selectedIndex),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Front'),
          NavigationDestination(icon: Icon(Icons.school_outlined), label: 'Learner'),
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Course'),
          NavigationDestination(icon: Icon(Icons.timeline_outlined), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return _FrontPage(courses: _courses);
      case 1:
        return _LearnerPage(currentCourse: _selectedCourse);
      case 2:
        return _CoursePage(
          courses: _courses,
          selectedCourse: _selectedCourse,
          onCourseChanged: (course) {
            setState(() {
              _selectedCourse = course;
            });
          },
        );
      case 3:
        return _ActivityPage(selectedCourse: _selectedCourse);
      case 4:
        return const _SettingsPage();
      default:
        return const SizedBox.shrink();
    }
  }
}

class _FrontPage extends StatelessWidget {
  const _FrontPage({required this.courses});

  final List<String> courses;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Recommended First Course',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Card(
          child: ListTile(
            title: Text('Learn with Git-Backed Notes'),
            subtitle: Text('4 weeks | 1 credit pace | starts today'),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Current Courses',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...courses.map((course) => Card(
              child: ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(course),
                subtitle: const Text('Open canvas and calendar'),
              ),
            )),
      ],
    );
  }
}

class _LearnerPage extends StatelessWidget {
  const _LearnerPage({required this.currentCourse});

  final String currentCourse;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current focus: $currentCourse'),
          const SizedBox(height: 12),
          const LinearProgressIndicator(value: 0.58),
          const SizedBox(height: 8),
          const Text('58% of tasks completed'),
          const SizedBox(height: 24),
          const Text(
            'This Week Calendar',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const _CalendarStrip(entries: [
            'Mon: Read chapter 2',
            'Wed: Submit reflection',
            'Fri: Push practice repo',
          ]),
        ],
      ),
    );
  }
}

class _CoursePage extends StatelessWidget {
  const _CoursePage({
    required this.courses,
    required this.selectedCourse,
    required this.onCourseChanged,
  });

  final List<String> courses;
  final String selectedCourse;
  final ValueChanged<String> onCourseChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Course Selection', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: selectedCourse,
          items: courses
              .map((course) => DropdownMenuItem(value: course, child: Text(course)))
              .toList(),
          onChanged: (value) {
            if (value != null) {
              onCourseChanged(value);
            }
          },
        ),
        const SizedBox(height: 16),
        const Text('Canvas Snapshot', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text('Node map: Intro -> Assignment A1 -> Reflection -> Portfolio'),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Current Course Calendar', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const _CalendarStrip(entries: [
          '04/03: Lecture notes sync',
          '04/06: Deadline check-in',
          '04/09: Assignment A1 review',
        ]),
      ],
    );
  }
}

class _ActivityPage extends StatelessWidget {
  const _ActivityPage({required this.selectedCourse});

  final String selectedCourse;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Recent activity for $selectedCourse'),
        const SizedBox(height: 8),
        const Card(
          child: ListTile(
            title: Text('Task done: Implement parser'),
            subtitle: Text('Evidence: https://github.com/example/repo/commit/abc123'),
          ),
        ),
        const Card(
          child: ListTile(
            title: Text('Reflection added'),
            subtitle: Text('"Need to split work into 45-minute blocks."'),
          ),
        ),
      ],
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ListTile(
          leading: Icon(Icons.public_outlined),
          title: Text('Default visibility'),
          subtitle: Text('Unlisted'),
        ),
        ListTile(
          leading: Icon(Icons.schedule_outlined),
          title: Text('Planning horizon'),
          subtitle: Text('90 days'),
        ),
        ListTile(
          leading: Icon(Icons.link_outlined),
          title: Text('GitHub integration'),
          subtitle: Text('Not connected'),
        ),
      ],
    );
  }
}

class _CalendarStrip extends StatelessWidget {
  const _CalendarStrip({required this.entries});

  final List<String> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: entries
          .map((entry) => Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.event_note_outlined),
                  title: Text(entry),
                ),
              ))
          .toList(),
    );
  }
}
