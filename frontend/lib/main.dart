import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const NotechondriaApp());
}

abstract class NotechondriaClient {
  Future<Map<String, dynamic>> getFrontPage();
  Future<List<Map<String, dynamic>>> getCourses();
  Future<List<Map<String, dynamic>>> getCourseNotes(int courseId);
  Future<Map<String, dynamic>> getNoteDetail(int noteId);
  Future<List<Map<String, dynamic>>> getActivity();
  Future<Map<String, dynamic>> register(String email, String password);
  Future<Map<String, dynamic>> verifyEmail(String email, String code);
  Future<Map<String, dynamic>> login(String email, String password);
  Future<void> logout(String token);
  Future<Map<String, dynamic>> getSettings(String token);
  Future<Map<String, dynamic>> updateSettings(String token, Map<String, dynamic> payload);
}

class HttpNotechondriaClient implements NotechondriaClient {
  HttpNotechondriaClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  static const String _baseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: '/api/v1');

  final http.Client _httpClient;

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<dynamic> _decode(http.Response response) async {
    if (response.body.isEmpty) {
      if (response.statusCode >= 400) {
        throw Exception('Request failed with ${response.statusCode}');
      }
      return {};
    }
    final data = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(data is Map<String, dynamic> ? data['detail'] ?? data.toString() : data.toString());
    }
    return data;
  }

  Map<String, String> _headers({String? token}) {
    final headers = {'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Token $token';
    }
    return headers;
  }

  @override
  Future<Map<String, dynamic>> getFrontPage() async {
    final response = await _httpClient.get(_uri('/front-page/'));
    return Map<String, dynamic>.from(await _decode(response));
  }

  @override
  Future<List<Map<String, dynamic>>> getCourses() async {
    final response = await _httpClient.get(_uri('/courses/'));
    final data = await _decode(response) as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getCourseNotes(int courseId) async {
    final response = await _httpClient.get(_uri('/courses/$courseId/notes/'));
    final data = await _decode(response) as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> getNoteDetail(int noteId) async {
    final response = await _httpClient.get(_uri('/notes/$noteId/'));
    return Map<String, dynamic>.from(await _decode(response));
  }

  @override
  Future<List<Map<String, dynamic>>> getActivity() async {
    final response = await _httpClient.get(_uri('/activity/'));
    final data = await _decode(response) as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> register(String email, String password) async {
    final response = await _httpClient.post(
      _uri('/auth/register/'),
      headers: _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    return Map<String, dynamic>.from(await _decode(response));
  }

  @override
  Future<Map<String, dynamic>> verifyEmail(String email, String code) async {
    final response = await _httpClient.post(
      _uri('/auth/verify-email/'),
      headers: _headers(),
      body: jsonEncode({'email': email, 'code': code}),
    );
    return Map<String, dynamic>.from(await _decode(response));
  }

  @override
  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _httpClient.post(
      _uri('/auth/login/'),
      headers: _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    return Map<String, dynamic>.from(await _decode(response));
  }

  @override
  Future<void> logout(String token) async {
    final response = await _httpClient.post(_uri('/auth/logout/'), headers: _headers(token: token));
    await _decode(response);
  }

  @override
  Future<Map<String, dynamic>> getSettings(String token) async {
    final response = await _httpClient.get(_uri('/settings/'), headers: _headers(token: token));
    return Map<String, dynamic>.from(await _decode(response));
  }

  @override
  Future<Map<String, dynamic>> updateSettings(String token, Map<String, dynamic> payload) async {
    final response = await _httpClient.patch(
      _uri('/settings/'),
      headers: _headers(token: token),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(await _decode(response));
  }
}

class NotechondriaApp extends StatelessWidget {
  const NotechondriaApp({super.key, this.client});

  final NotechondriaClient? client;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notechondria',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF97316),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFFFBF5),
      ),
      home: AppShell(client: client ?? HttpNotechondriaClient()),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.client});

  final NotechondriaClient client;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;
  String? _token;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _settings;
  Map<String, dynamic>? _frontPage;
  List<Map<String, dynamic>> _courses = const [];
  List<Map<String, dynamic>> _courseNotes = const [];
  List<Map<String, dynamic>> _activity = const [];
  Map<String, dynamic>? _selectedCourse;
  Map<String, dynamic>? _selectedNote;

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
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final frontPage = await widget.client.getFrontPage();
      final courses = await widget.client.getCourses();
      final activity = await widget.client.getActivity();
      final defaultCourse = frontPage['default_course'] as Map<String, dynamic>?;
      final selectedCourse = defaultCourse ??
          (courses.isNotEmpty ? Map<String, dynamic>.from(courses.first) : null);
      List<Map<String, dynamic>> courseNotes = const [];
      Map<String, dynamic>? selectedNote;
      if (selectedCourse != null) {
        courseNotes = await widget.client.getCourseNotes(selectedCourse['id'] as int);
        if (courseNotes.isNotEmpty) {
          selectedNote = await widget.client.getNoteDetail(courseNotes.first['id'] as int);
        }
      }
      setState(() {
        _frontPage = frontPage;
        _courses = courses;
        _activity = activity;
        _selectedCourse = selectedCourse;
        _courseNotes = courseNotes;
        _selectedNote = selectedNote;
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _selectCourse(Map<String, dynamic> course) async {
    setState(() {
      _selectedCourse = course;
      _isLoading = true;
    });
    try {
      final notes = await widget.client.getCourseNotes(course['id'] as int);
      Map<String, dynamic>? detail;
      if (notes.isNotEmpty) {
        detail = await widget.client.getNoteDetail(notes.first['id'] as int);
      }
      setState(() {
        _courseNotes = notes;
        _selectedNote = detail;
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _selectNote(Map<String, dynamic> noteSummary) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final detail = await widget.client.getNoteDetail(noteSummary['id'] as int);
      setState(() {
        _selectedNote = detail;
        _selectedIndex = 1;
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _register(String email, String password) async {
    final result = await widget.client.register(email, password);
    _showMessage(result['message']?.toString() ?? 'Verification email sent.');
  }

  Future<void> _verify(String email, String code) async {
    final result = await widget.client.verifyEmail(email, code);
    await _applyAuthPayload(result);
  }

  Future<void> _login(String email, String password) async {
    final result = await widget.client.login(email, password);
    await _applyAuthPayload(result);
  }

  Future<void> _applyAuthPayload(Map<String, dynamic> payload) async {
    final token = payload['token']?.toString() ?? '';
    final user = Map<String, dynamic>.from(payload['user'] as Map? ?? {});
    final settings = await widget.client.getSettings(token);
    setState(() {
      _token = token;
      _profile = user;
      _settings = settings;
    });
    _showMessage('Signed in as ${user['email'] ?? 'account'}.');
  }

  Future<void> _logout() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    await widget.client.logout(token);
    setState(() {
      _token = null;
      _profile = null;
      _settings = null;
    });
    _showMessage('Signed out.');
  }

  Future<void> _updateSettings(String motto, String socialLink) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    final updated = await widget.client.updateSettings(token, {
      'motto': motto,
      'social_link': socialLink,
    });
    setState(() {
      _settings = updated;
    });
    _showMessage('Settings updated.');
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(_titles[_selectedIndex]),
        backgroundColor: Colors.transparent,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _ErrorState(message: _errorMessage!, onRetry: _loadInitialData)
                : _buildPage(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Front'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'Learner'),
          NavigationDestination(icon: Icon(Icons.school_outlined), label: 'Course'),
          NavigationDestination(icon: Icon(Icons.timeline_outlined), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildPage() {
    switch (_selectedIndex) {
      case 0:
        return _FrontPage(
          frontPage: _frontPage ?? const {},
          isAuthenticated: _token != null,
          onRegister: _register,
          onVerify: _verify,
          onLogin: _login,
          onOpenNote: _selectNote,
        );
      case 1:
        return _LearnerPage(
          selectedCourse: _selectedCourse,
          selectedNote: _selectedNote,
          onOpenCourse: () => setState(() => _selectedIndex = 2),
        );
      case 2:
        return _CoursePage(
          courses: _courses,
          selectedCourse: _selectedCourse,
          notes: _courseNotes,
          onCourseChanged: _selectCourse,
          onOpenNote: _selectNote,
        );
      case 3:
        return _ActivityPage(activity: _activity, onOpenNote: _selectNote);
      case 4:
        return _SettingsPage(
          profile: _profile,
          settings: _settings,
          onSave: _updateSettings,
          onLogout: _logout,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _FrontPage extends StatelessWidget {
  const _FrontPage({
    required this.frontPage,
    required this.isAuthenticated,
    required this.onRegister,
    required this.onVerify,
    required this.onLogin,
    required this.onOpenNote,
  });

  final Map<String, dynamic> frontPage;
  final bool isAuthenticated;
  final Future<void> Function(String email, String password) onRegister;
  final Future<void> Function(String email, String code) onVerify;
  final Future<void> Function(String email, String password) onLogin;
  final ValueChanged<Map<String, dynamic>> onOpenNote;

  @override
  Widget build(BuildContext context) {
    final defaultCourse = frontPage['default_course'] as Map<String, dynamic>? ?? const {};
    final recentNotes = (frontPage['recent_notes'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF172554), Color(0xFFF97316)],
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
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                defaultCourse['description']?.toString() ?? 'Sample course data will appear here.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: const Color(0xFFFFEDD5)),
              ),
              const SizedBox(height: 18),
              if ((defaultCourse['cover_image_url']?.toString() ?? '').isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.network(defaultCourse['cover_image_url'].toString(), height: 220, fit: BoxFit.cover),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Recent notes', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final note in recentNotes)
          Card(
            child: ListTile(
              title: Text(note['title']?.toString() ?? 'Untitled note'),
              subtitle: Text(note['excerpt']?.toString() ?? ''),
              trailing: const Icon(Icons.arrow_forward_outlined),
              onTap: () => onOpenNote(note),
            ),
          ),
        const SizedBox(height: 24),
        if (!isAuthenticated)
          _AuthPanel(
            onRegister: onRegister,
            onVerify: onVerify,
            onLogin: onLogin,
          ),
      ],
    );
  }
}

class _LearnerPage extends StatelessWidget {
  const _LearnerPage({
    required this.selectedCourse,
    required this.selectedNote,
    required this.onOpenCourse,
  });

  final Map<String, dynamic>? selectedCourse;
  final Map<String, dynamic>? selectedNote;
  final VoidCallback onOpenCourse;

  @override
  Widget build(BuildContext context) {
    if (selectedNote == null) {
      return Center(
        child: FilledButton(
          onPressed: onOpenCourse,
          child: const Text('Open course notes'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          selectedCourse?['title']?.toString() ?? 'Current course',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          selectedNote?['title']?.toString() ?? 'Selected note',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: MarkdownBody(data: _noteToMarkdown(selectedNote!)),
          ),
        ),
      ],
    );
  }
}

class _CoursePage extends StatelessWidget {
  const _CoursePage({
    required this.courses,
    required this.selectedCourse,
    required this.notes,
    required this.onCourseChanged,
    required this.onOpenNote,
  });

  final List<Map<String, dynamic>> courses;
  final Map<String, dynamic>? selectedCourse;
  final List<Map<String, dynamic>> notes;
  final ValueChanged<Map<String, dynamic>> onCourseChanged;
  final ValueChanged<Map<String, dynamic>> onOpenNote;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Course Selection', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: selectedCourse?['id'] as int?,
          items: courses
              .map(
                (course) => DropdownMenuItem<int>(
                  value: course['id'] as int,
                  child: Text(course['title']?.toString() ?? 'Course'),
                ),
              )
              .toList(),
          onChanged: (value) {
            for (final course in courses) {
              if (course['id'] == value) {
                onCourseChanged(course);
                break;
              }
            }
          },
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 20),
        Text('Notes', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        for (final note in notes)
          Card(
            child: ListTile(
              title: Text(note['title']?.toString() ?? 'Untitled note'),
              subtitle: Text(note['excerpt']?.toString() ?? ''),
              onTap: () => onOpenNote(note),
            ),
          ),
      ],
    );
  }
}

class _ActivityPage extends StatelessWidget {
  const _ActivityPage({
    required this.activity,
    required this.onOpenNote,
  });

  final List<Map<String, dynamic>> activity;
  final ValueChanged<Map<String, dynamic>> onOpenNote;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Recent note activity', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final entry in activity)
          Card(
            child: ListTile(
              leading: const Icon(Icons.history_edu_outlined),
              title: Text(entry['title']?.toString() ?? 'Untitled note'),
              subtitle: Text(entry['excerpt']?.toString() ?? ''),
              onTap: () => onOpenNote(entry),
            ),
          ),
      ],
    );
  }
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.profile,
    required this.settings,
    required this.onSave,
    required this.onLogout,
  });

  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? settings;
  final Future<void> Function(String motto, String socialLink) onSave;
  final Future<void> Function() onLogout;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late final TextEditingController _mottoController;
  late final TextEditingController _socialController;

  @override
  void initState() {
    super.initState();
    _mottoController = TextEditingController(text: widget.settings?['motto']?.toString() ?? '');
    _socialController = TextEditingController(text: widget.settings?['social_link']?.toString() ?? '');
  }

  @override
  void didUpdateWidget(covariant _SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _mottoController.text = widget.settings?['motto']?.toString() ?? '';
      _socialController.text = widget.settings?['social_link']?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _mottoController.dispose();
    _socialController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.profile == null || widget.settings == null) {
      return const Center(
        child: Text('Sign in from the front page to manage account settings.'),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(widget.profile?['email']?.toString() ?? ''),
          subtitle: const Text('Verified account'),
        ),
        TextField(
          controller: _mottoController,
          decoration: const InputDecoration(labelText: 'Motto'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _socialController,
          decoration: const InputDecoration(labelText: 'Social link'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => widget.onSave(_mottoController.text, _socialController.text),
          child: const Text('Save settings'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: widget.onLogout,
          child: const Text('Logout'),
        ),
      ],
    );
  }
}

class _AuthPanel extends StatefulWidget {
  const _AuthPanel({
    required this.onRegister,
    required this.onVerify,
    required this.onLogin,
  });

  final Future<void> Function(String email, String password) onRegister;
  final Future<void> Function(String email, String code) onVerify;
  final Future<void> Function(String email, String password) onLogin;

  @override
  State<_AuthPanel> createState() => _AuthPanelState();
}

class _AuthPanelState extends State<_AuthPanel> {
  final _registerEmail = TextEditingController();
  final _registerPassword = TextEditingController();
  final _verifyEmail = TextEditingController();
  final _verifyCode = TextEditingController();
  final _loginEmail = TextEditingController();
  final _loginPassword = TextEditingController();

  @override
  void dispose() {
    _registerEmail.dispose();
    _registerPassword.dispose();
    _verifyEmail.dispose();
    _verifyCode.dispose();
    _loginEmail.dispose();
    _loginPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFFFFF1E6),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Email-only account flow', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Register with email and password, verify with the code from SMTP, then sign in.'),
            const SizedBox(height: 16),
            _AuthSection(
              title: 'Register',
              fields: [
                _AuthField(controller: _registerEmail, label: 'Email'),
                _AuthField(controller: _registerPassword, label: 'Password', obscureText: true),
              ],
              actionLabel: 'Send verification email',
              onPressed: () => widget.onRegister(_registerEmail.text, _registerPassword.text),
            ),
            const SizedBox(height: 16),
            _AuthSection(
              title: 'Verify',
              fields: [
                _AuthField(controller: _verifyEmail, label: 'Email'),
                _AuthField(controller: _verifyCode, label: 'Verification code'),
              ],
              actionLabel: 'Verify email',
              onPressed: () => widget.onVerify(_verifyEmail.text, _verifyCode.text),
            ),
            const SizedBox(height: 16),
            _AuthSection(
              title: 'Login',
              fields: [
                _AuthField(controller: _loginEmail, label: 'Email'),
                _AuthField(controller: _loginPassword, label: 'Password', obscureText: true),
              ],
              actionLabel: 'Login',
              onPressed: () => widget.onLogin(_loginEmail.text, _loginPassword.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthSection extends StatelessWidget {
  const _AuthSection({
    required this.title,
    required this.fields,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final List<_AuthField> fields;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final field in fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: field.controller,
              obscureText: field.obscureText,
              decoration: InputDecoration(
                labelText: field.label,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        FilledButton(onPressed: onPressed, child: Text(actionLabel)),
      ],
    );
  }
}

class _AuthField {
  const _AuthField({
    required this.controller,
    required this.label,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

String _noteToMarkdown(Map<String, dynamic> note) {
  final blocks = (note['blocks'] as List<dynamic>? ?? const [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  if (blocks.isEmpty) {
    return '# ${note['title'] ?? 'Untitled'}\n\n${note['description'] ?? ''}';
  }
  final buffer = StringBuffer();
  for (final block in blocks) {
    final type = block['block_type']?.toString() ?? 'N';
    final text = block['text']?.toString() ?? '';
    switch (type) {
      case 'T':
        buffer.writeln('# $text');
        break;
      case 'S':
        buffer.writeln('${block['args'] ?? '##'} $text');
        break;
      case 'C':
        buffer.writeln('```');
        buffer.writeln(text);
        buffer.writeln('```');
        break;
      default:
        buffer.writeln(text);
    }
    buffer.writeln();
  }
  return buffer.toString();
}
