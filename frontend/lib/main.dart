import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const NotechondriaApp());
}

class ActionFeedback {
  const ActionFeedback({
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;
}

class ApiDebugSnapshot {
  const ApiDebugSnapshot({
    required this.method,
    required this.url,
    required this.statusCode,
    required this.contentType,
    required this.bodyPreview,
    required this.looksLikeHtml,
    this.note,
  });

  final String method;
  final String url;
  final int statusCode;
  final String contentType;
  final String bodyPreview;
  final bool looksLikeHtml;
  final String? note;
}

abstract class NotechondriaClient {
  Future<Map<String, dynamic>> getFrontPage({String? token});
  Future<List<Map<String, dynamic>>> getCourses();
  Future<List<Map<String, dynamic>>> getCourseNotes(int courseId);
  Future<Map<String, dynamic>> getNoteDetail(int noteId);
  Future<List<Map<String, dynamic>>> getActivity({String? token});
  Future<Map<String, dynamic>> register(String email, String password);
  Future<Map<String, dynamic>> verifyEmail(String email, String code);
  Future<Map<String, dynamic>> login(String email, String password);
  Future<Map<String, dynamic>> requestPasswordReset(String email);
  Future<Map<String, dynamic>> confirmPasswordReset(String email, String code, String password);
  Future<void> logout(String token);
  Future<Map<String, dynamic>> getSettings(String token);
  Future<Map<String, dynamic>> updateSettings(String token, Map<String, dynamic> payload);
  Future<List<Map<String, dynamic>>> getPlannerEvents(String token);
  Future<Map<String, dynamic>> createPlannerEvent(String token, Map<String, dynamic> payload);
  Future<Map<String, dynamic>> updatePlannerEvent(
    String token,
    int eventId,
    Map<String, dynamic> payload,
  );
}

class HttpNotechondriaClient implements NotechondriaClient {
  HttpNotechondriaClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client(),
        baseUrl = _normalizeBaseUrl(_resolveBaseUrl());

  final http.Client _httpClient;
  final String baseUrl;
  final ValueNotifier<ApiDebugSnapshot?> debugSnapshot = ValueNotifier(null);

  static String _resolveBaseUrl() {
    const configured = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (configured.isNotEmpty) {
      return configured;
    }
    if (kIsWeb && Uri.base.scheme.startsWith('http')) {
      final isLocalHost = Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1';
      if (!isLocalHost) {
        return Uri.base.origin;
      }
    }
    return 'http://localhost:9080';
  }

  static String _normalizeBaseUrl(String raw) {
    var value = raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith('/api/v1')) {
      return value;
    }
    if (value.endsWith('/api')) {
      return '$value/v1';
    }
    return '$value/api/v1';
  }

  Uri _uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath');
  }

  String _stringifyErrors(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (data['detail'] != null) {
        return data['detail'].toString();
      }
      return data.entries.map((entry) {
        final value = entry.value;
        if (value is List) {
          return '${entry.key}: ${value.join(", ")}';
        }
        return '${entry.key}: $value';
      }).join('\n');
    }
    return data.toString();
  }

  String _previewBody(String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 240) {
      return compact;
    }
    return '${compact.substring(0, 240)}...';
  }

  String _formatDecodeError(Uri uri, http.Response response, bool looksLikeHtml) {
    final target = '${response.request?.method ?? 'REQUEST'} ${uri.toString()}';
    if (looksLikeHtml) {
      return 'Expected JSON from $target but received HTML. Check API_BASE_URL and backend routing.';
    }
    return 'Expected JSON from $target but received an invalid response.';
  }

  Future<dynamic> _decode(
    http.Response response, {
    required Uri uri,
    required String method,
  }) async {
    final body = response.body;
    final contentType = response.headers['content-type'] ?? '';
    final trimmed = body.trimLeft();
    final looksLikeHtml = trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<html') || trimmed.startsWith('<');
    if (response.body.isEmpty) {
      if (response.statusCode >= 400) {
        throw Exception('Request failed with ${response.statusCode}');
      }
      return {};
    }
    dynamic data;
    try {
      data = jsonDecode(body);
    } on FormatException {
      debugSnapshot.value = ApiDebugSnapshot(
        method: method,
        url: uri.toString(),
        statusCode: response.statusCode,
        contentType: contentType,
        bodyPreview: _previewBody(body),
        looksLikeHtml: looksLikeHtml,
        note: looksLikeHtml ? 'The response body looks like HTML, not JSON.' : 'The response body is not valid JSON.',
      );
      throw Exception(_formatDecodeError(uri, response, looksLikeHtml));
    }
    debugSnapshot.value = ApiDebugSnapshot(
      method: method,
      url: uri.toString(),
      statusCode: response.statusCode,
      contentType: contentType,
      bodyPreview: _previewBody(body),
      looksLikeHtml: looksLikeHtml,
    );
    if (response.statusCode >= 400) {
      throw Exception(_stringifyErrors(data));
    }
    return data;
  }

  Map<String, String> _headers({
    String? token,
    bool includeJsonContentType = false,
  }) {
    final headers = {
      'Accept': 'application/json',
    };
    if (includeJsonContentType) {
      headers['Content-Type'] = 'application/json';
    }
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Token $token';
    }
    return headers;
  }

  @override
  Future<Map<String, dynamic>> getFrontPage({String? token}) async {
    final uri = _uri('/front-page/');
    final response = await _httpClient.get(uri, headers: _headers(token: token));
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'GET'));
  }

  @override
  Future<List<Map<String, dynamic>>> getCourses() async {
    final uri = _uri('/courses/');
    final response = await _httpClient.get(uri, headers: _headers());
    final data = await _decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getCourseNotes(int courseId) async {
    final uri = _uri('/courses/$courseId/notes/');
    final response = await _httpClient.get(uri, headers: _headers());
    final data = await _decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> getNoteDetail(int noteId) async {
    final uri = _uri('/notes/$noteId/');
    final response = await _httpClient.get(uri, headers: _headers());
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'GET'));
  }

  @override
  Future<List<Map<String, dynamic>>> getActivity({String? token}) async {
    final uri = _uri('/activity/');
    final response = await _httpClient.get(uri, headers: _headers(token: token));
    final data = await _decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> register(String email, String password) async {
    final uri = _uri('/auth/register/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(includeJsonContentType: true),
      body: jsonEncode({'email': email, 'password': password}),
    );
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'POST'));
  }

  @override
  Future<Map<String, dynamic>> verifyEmail(String email, String code) async {
    final uri = _uri('/auth/verify-email/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(includeJsonContentType: true),
      body: jsonEncode({'email': email, 'code': code}),
    );
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'POST'));
  }

  @override
  Future<Map<String, dynamic>> login(String email, String password) async {
    final uri = _uri('/auth/login/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(includeJsonContentType: true),
      body: jsonEncode({'email': email, 'password': password}),
    );
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'POST'));
  }

  @override
  Future<Map<String, dynamic>> requestPasswordReset(String email) async {
    final uri = _uri('/auth/password-reset/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(includeJsonContentType: true),
      body: jsonEncode({'email': email}),
    );
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'POST'));
  }

  @override
  Future<Map<String, dynamic>> confirmPasswordReset(String email, String code, String password) async {
    final uri = _uri('/auth/password-reset/confirm/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(includeJsonContentType: true),
      body: jsonEncode({'email': email, 'code': code, 'password': password}),
    );
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'POST'));
  }

  @override
  Future<void> logout(String token) async {
    final uri = _uri('/auth/logout/');
    final response = await _httpClient.post(uri, headers: _headers(token: token));
    await _decode(response, uri: uri, method: 'POST');
  }

  @override
  Future<Map<String, dynamic>> getSettings(String token) async {
    final uri = _uri('/settings/');
    final response = await _httpClient.get(uri, headers: _headers(token: token));
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'GET'));
  }

  @override
  Future<Map<String, dynamic>> updateSettings(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/settings/');
    final response = await _httpClient.patch(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'PATCH'));
  }

  @override
  Future<List<Map<String, dynamic>>> getPlannerEvents(String token) async {
    final uri = _uri('/planner-events/');
    final response = await _httpClient.get(
      uri,
      headers: _headers(token: token),
    );
    final data = await _decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> createPlannerEvent(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/planner-events/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'POST'));
  }

  @override
  Future<Map<String, dynamic>> updatePlannerEvent(
    String token,
    int eventId,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/planner-events/$eventId/');
    final response = await _httpClient.patch(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'PATCH'));
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
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFAF8F1),
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
  List<Map<String, dynamic>> _plannerEvents = const [];
  Map<String, dynamic>? _selectedCourse;
  Map<String, dynamic>? _selectedNote;

  HttpNotechondriaClient? get _httpClient =>
      widget.client is HttpNotechondriaClient ? widget.client as HttpNotechondriaClient : null;

  static const List<String> _titles = [
    'Front Page',
    'Learner View',
    'Course View',
    'Activity View',
    'Settings',
  ];

  static const List<NavigationDestination> _destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Front'),
    NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'Learner'),
    NavigationDestination(icon: Icon(Icons.school_outlined), label: 'Course'),
    NavigationDestination(icon: Icon(Icons.timeline_outlined), label: 'Activity'),
    NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
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
      final frontPage = await widget.client.getFrontPage(token: _token);
      final courses = await widget.client.getCourses();
      final activity = await widget.client.getActivity(token: _token);
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
      List<Map<String, dynamic>> plannerEvents = const [];
      if (_token != null && _token!.isNotEmpty) {
        plannerEvents = await widget.client.getPlannerEvents(_token!);
      }
      setState(() {
        _frontPage = frontPage;
        _courses = courses;
        _activity = activity;
        _selectedCourse = selectedCourse;
        _courseNotes = courseNotes;
        _selectedNote = selectedNote;
        _plannerEvents = plannerEvents;
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshFrontPageData() async {
    final frontPage = await widget.client.getFrontPage(token: _token);
    List<Map<String, dynamic>> plannerEvents = _plannerEvents;
    if (_token != null && _token!.isNotEmpty) {
      plannerEvents = await widget.client.getPlannerEvents(_token!);
    }
    setState(() {
      _frontPage = frontPage;
      _plannerEvents = plannerEvents;
    });
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
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
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
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<ActionFeedback> _register(String email, String password) async {
    try {
      final result = await widget.client.register(email, password);
      return ActionFeedback(message: result['message']?.toString() ?? 'Verification email sent.');
    } catch (error) {
      return ActionFeedback(
        message: error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<ActionFeedback> _verify(String email, String code) async {
    try {
      final result = await widget.client.verifyEmail(email, code);
      await _applyAuthPayload(result);
      return const ActionFeedback(message: 'Email verified. You are now signed in.');
    } catch (error) {
      return ActionFeedback(
        message: error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<ActionFeedback> _login(String email, String password) async {
    try {
      final result = await widget.client.login(email, password);
      await _applyAuthPayload(result);
      return const ActionFeedback(message: 'Login successful.');
    } catch (error) {
      return ActionFeedback(
        message: error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<ActionFeedback> _requestPasswordReset(String email) async {
    try {
      final result = await widget.client.requestPasswordReset(email);
      return ActionFeedback(message: result['message']?.toString() ?? 'Password reset email sent.');
    } catch (error) {
      return ActionFeedback(
        message: error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<ActionFeedback> _confirmPasswordReset(String email, String code, String password) async {
    try {
      final result = await widget.client.confirmPasswordReset(email, code, password);
      return ActionFeedback(message: result['message']?.toString() ?? 'Password updated.');
    } catch (error) {
      return ActionFeedback(
        message: error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
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
    await _loadInitialData();
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
      _plannerEvents = const [];
    });
    await _loadInitialData();
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

  Future<ActionFeedback> _createPlannerEvent(
    String title,
    DateTime eventDate,
    int difficultyWeight,
    String description,
  ) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const ActionFeedback(
        message: 'Sign in first to create planning events.',
        isError: true,
      );
    }
    try {
      await widget.client.createPlannerEvent(token, {
        'title': title,
        'event_date': _dateOnly(eventDate).toIso8601String().split('T').first,
        'difficulty_weight': difficultyWeight,
        'description': description,
        'course_id': _selectedCourse?['id'],
      });
      await _refreshFrontPageData();
      return const ActionFeedback(message: 'Future event added to the heatmap.');
    } catch (error) {
      return ActionFeedback(
        message: error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideLayout = constraints.maxWidth >= 960;
        if (isWideLayout) {
          return _buildWideScaffold(context);
        }
        return _buildCompactScaffold();
      },
    );
  }

  Widget _buildCompactScaffold() {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(_titles[_selectedIndex]),
        backgroundColor: Colors.transparent,
      ),
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _handleDestinationSelected,
        destinations: _destinations,
      ),
    );
  }

  Widget _buildWideScaffold(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 240,
              decoration: const BoxDecoration(
                color: Color(0xFFF3F4F6),
                border: Border(
                  right: BorderSide(color: Color(0xFFE5E7EB)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notechondria',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Wide layout',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF6B7280),
                              ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: NavigationRail(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _handleDestinationSelected,
                      labelType: NavigationRailLabelType.all,
                      backgroundColor: Colors.transparent,
                      leading: const SizedBox.shrink(),
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.home_outlined),
                          label: Text('Front'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.menu_book_outlined),
                          label: Text('Learner'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.school_outlined),
                          label: Text('Course'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.timeline_outlined),
                          label: Text('Activity'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.settings_outlined),
                          label: Text('Settings'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Text(
                      _titles[_selectedIndex],
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: SelectionArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _ErrorState(
                    message: _errorMessage!,
                    onRetry: _loadInitialData,
                    apiBaseUrl: _httpClient?.baseUrl,
                    debugSnapshot: _httpClient?.debugSnapshot.value,
                  )
                : _buildPage(),
      ),
    );
  }

  void _handleDestinationSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildPage() {
    switch (_selectedIndex) {
      case 0:
        return _FrontPage(
          frontPage: _frontPage ?? const {},
          plannerEvents: _plannerEvents,
          isAuthenticated: _token != null,
          onCreatePlannerEvent: _createPlannerEvent,
          onOpenNote: _selectNote,
          onOpenCourse: _selectCourse,
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
          onRegister: _register,
          onVerify: _verify,
          onLogin: _login,
          onRequestPasswordReset: _requestPasswordReset,
          onConfirmPasswordReset: _confirmPasswordReset,
          apiBaseUrl: _httpClient?.baseUrl,
          debugSnapshotListenable: _httpClient?.debugSnapshot,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _FrontPage extends StatelessWidget {
  const _FrontPage({
    required this.frontPage,
    required this.plannerEvents,
    required this.isAuthenticated,
    required this.onCreatePlannerEvent,
    required this.onOpenNote,
    required this.onOpenCourse,
  });

  final Map<String, dynamic> frontPage;
  final List<Map<String, dynamic>> plannerEvents;
  final bool isAuthenticated;
  final Future<ActionFeedback> Function(
    String title,
    DateTime eventDate,
    int difficultyWeight,
    String description,
  ) onCreatePlannerEvent;
  final ValueChanged<Map<String, dynamic>> onOpenNote;
  final ValueChanged<Map<String, dynamic>> onOpenCourse;

  @override
  Widget build(BuildContext context) {
    final defaultCourse = frontPage['default_course'] as Map<String, dynamic>? ?? const {};
    final heatmap = frontPage['heatmap'] as Map<String, dynamic>?;
    final recentNotes = (frontPage['recent_notes'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final collections = (frontPage['collections'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _FrontHero(defaultCourse: defaultCourse),
        const SizedBox(height: 20),
        if (heatmap != null)
          _HeatmapCard(heatmap: heatmap)
        else
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sign in to see the progress heatmap and future plan.'),
            ),
          ),
        const SizedBox(height: 20),
        if (isAuthenticated)
          _PlannerEventComposer(
            plannerEvents: plannerEvents,
            onCreatePlannerEvent: onCreatePlannerEvent,
          )
        else
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Course materials are open to everyone. Use the Settings tab if you want to register, verify email, or log in.',
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text('Collections', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final collection in collections)
          Card(
            child: ListTile(
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: Text(collection['title']?.toString() ?? 'Collection'),
              subtitle: Text(collection['description']?.toString() ?? ''),
              onTap: () => onOpenCourse(collection),
            ),
          ),
        const SizedBox(height: 20),
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
      ],
    );
  }
}

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
            defaultCourse['description']?.toString() ?? 'Sample course data will appear here.',
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
            Text('Progress + plan heatmap', style: Theme.of(context).textTheme.titleLarge),
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
          final targetOffset =
              math.max(0.0, (todayColumn * cellSpan) - (constraints.maxWidth / 2) + (cellSpan / 2));
          _controller.jumpTo(math.min(targetOffset, _controller.position.maxScrollExtent));
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
                                      ? Border.all(color: Colors.black87, width: 1.3)
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

  List<List<Map<String, dynamic>>> _buildColumns(List<Map<String, dynamic>> cells) {
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
      return Color.lerp(const Color(0xFFD1FAE5), const Color(0xFF166534), math.min(value / 6, 1))!;
    }
    final value = (cell['past_value'] as num?)?.toDouble() ?? 0;
    return Color.lerp(const Color(0xFFDBEAFE), const Color(0xFF1D4ED8), math.min(value / 1200, 1))!;
  }

  String _tooltip(Map<String, dynamic> cell) {
    if ((cell['date']?.toString() ?? '').isEmpty) {
      return '';
    }
    return '${cell['date']}\nPast words: ${cell['past_value']}\nFuture weight: ${cell['future_value']}';
  }
}

class _PlannerEventComposer extends StatefulWidget {
  const _PlannerEventComposer({
    required this.plannerEvents,
    required this.onCreatePlannerEvent,
  });

  final List<Map<String, dynamic>> plannerEvents;
  final Future<ActionFeedback> Function(
    String title,
    DateTime eventDate,
    int difficultyWeight,
    String description,
  ) onCreatePlannerEvent;

  @override
  State<_PlannerEventComposer> createState() => _PlannerEventComposerState();
}

class _PlannerEventComposerState extends State<_PlannerEventComposer> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime _selectedDate = _dateOnly(DateTime.now()).add(const Duration(days: 1));
  int _weight = 1;
  bool _submitting = false;
  ActionFeedback? _feedback;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    final feedback = await widget.onCreatePlannerEvent(
      _titleController.text,
      _selectedDate,
      _weight,
      _descriptionController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _feedback = feedback;
      if (!feedback.isError) {
        _titleController.clear();
        _descriptionController.clear();
        _weight = 1;
        _selectedDate = _dateOnly(DateTime.now()).add(const Duration(days: 1));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Register future events', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('These events feed the green half of the heatmap. Default difficulty is 1.'),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Event title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: _dateOnly(DateTime.now()),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null && mounted) {
                        setState(() {
                          _selectedDate = _dateOnly(picked);
                        });
                      }
                    },
                    child: Text('Date: ${_selectedDate.toIso8601String().split('T').first}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _weight,
                    items: List.generate(
                      5,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('Weight ${index + 1}'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _weight = value;
                        });
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Difficulty',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Saving...' : 'Add event'),
            ),
            if (_feedback != null) ...[
              const SizedBox(height: 10),
              Text(
                _feedback!.message,
                style: TextStyle(
                  color: _feedback!.isError ? const Color(0xFFB91C1C) : const Color(0xFF166534),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (widget.plannerEvents.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Upcoming events', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final event in widget.plannerEvents.take(6))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: const Color(0xFFD1FAE5),
                    child: Text(
                      '${event['difficulty_weight'] ?? 1}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF166534)),
                    ),
                  ),
                  title: Text(event['title']?.toString() ?? 'Event'),
                  subtitle: Text(event['event_date']?.toString() ?? ''),
                ),
            ],
          ],
        ),
      ),
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
            child: SelectionArea(
              child: MarkdownBody(data: _noteToMarkdown(selectedNote!)),
            ),
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
        Text('Collections', style: Theme.of(context).textTheme.titleLarge),
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
    required this.onRegister,
    required this.onVerify,
    required this.onLogin,
    required this.onRequestPasswordReset,
    required this.onConfirmPasswordReset,
    this.apiBaseUrl,
    this.debugSnapshotListenable,
  });

  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? settings;
  final Future<void> Function(String motto, String socialLink) onSave;
  final Future<void> Function() onLogout;
  final Future<ActionFeedback> Function(String email, String password) onRegister;
  final Future<ActionFeedback> Function(String email, String code) onVerify;
  final Future<ActionFeedback> Function(String email, String password) onLogin;
  final Future<ActionFeedback> Function(String email) onRequestPasswordReset;
  final Future<ActionFeedback> Function(String email, String code, String password) onConfirmPasswordReset;
  final String? apiBaseUrl;
  final ValueListenable<ApiDebugSnapshot?>? debugSnapshotListenable;

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
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.profile == null || widget.settings == null) ...[
          const Text('Use this tab to register, verify email, and log in. Course materials remain available without an account.'),
          const SizedBox(height: 16),
          _AuthHub(
            onRegister: widget.onRegister,
            onVerify: widget.onVerify,
            onLogin: widget.onLogin,
            onRequestPasswordReset: widget.onRequestPasswordReset,
            onConfirmPasswordReset: widget.onConfirmPasswordReset,
          ),
        ] else ...[
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
        const SizedBox(height: 24),
        Text('API debug', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _ApiDebugCard(
          apiBaseUrl: widget.apiBaseUrl,
          snapshotListenable: widget.debugSnapshotListenable,
        ),
      ],
    );
  }
}

class _AuthHub extends StatelessWidget {
  const _AuthHub({
    required this.onRegister,
    required this.onVerify,
    required this.onLogin,
    required this.onRequestPasswordReset,
    required this.onConfirmPasswordReset,
  });

  final Future<ActionFeedback> Function(String email, String password) onRegister;
  final Future<ActionFeedback> Function(String email, String code) onVerify;
  final Future<ActionFeedback> Function(String email, String password) onLogin;
  final Future<ActionFeedback> Function(String email) onRequestPasswordReset;
  final Future<ActionFeedback> Function(String email, String code, String password) onConfirmPasswordReset;

  Future<void> _openDialog(BuildContext context, Widget dialog) {
    return showDialog<void>(
      context: context,
      builder: (context) => dialog,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFFF6F0E6),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Account', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Use small dialogs for sign up, verification, login, and password reset.'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(
                  onPressed: () => _openDialog(
                    context,
                    _EmailPasswordDialog(
                      title: 'Sign up',
                      description: 'Create an account with email and password. Verification code arrives by email or server log fallback.',
                      submitLabel: 'Create account',
                      onSubmit: onRegister,
                    ),
                  ),
                  child: const Text('Sign up'),
                ),
                OutlinedButton(
                  onPressed: () => _openDialog(
                    context,
                    _EmailCodeDialog(
                      title: 'Verify email',
                      description: 'Enter the verification code sent to your email.',
                      submitLabel: 'Verify',
                      onSubmit: onVerify,
                    ),
                  ),
                  child: const Text('Verify email'),
                ),
                OutlinedButton(
                  onPressed: () => _openDialog(
                    context,
                    _EmailPasswordDialog(
                      title: 'Login',
                      description: 'Sign in with your email and password.',
                      submitLabel: 'Login',
                      onSubmit: onLogin,
                    ),
                  ),
                  child: const Text('Login'),
                ),
                TextButton(
                  onPressed: () => _openDialog(
                    context,
                    _PasswordResetDialog(
                      onRequestPasswordReset: onRequestPasswordReset,
                      onConfirmPasswordReset: onConfirmPasswordReset,
                    ),
                  ),
                  child: const Text('Forgot password'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmailPasswordDialog extends StatefulWidget {
  const _EmailPasswordDialog({
    required this.title,
    required this.description,
    required this.submitLabel,
    required this.onSubmit,
  });

  final String title;
  final String description;
  final String submitLabel;
  final Future<ActionFeedback> Function(String email, String password) onSubmit;

  @override
  State<_EmailPasswordDialog> createState() => _EmailPasswordDialogState();
}

class _EmailPasswordDialogState extends State<_EmailPasswordDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  ActionFeedback? _feedback;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    final feedback = await widget.onSubmit(_emailController.text, _passwordController.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _feedback = feedback;
    });
    if (!feedback.isError && widget.title == 'Login') {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.description),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
            ),
            if (_feedback != null) ...[
              const SizedBox(height: 12),
              _FeedbackText(feedback: _feedback!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(), child: const Text('Close')),
        FilledButton(onPressed: _submitting ? null : _submit, child: Text(_submitting ? 'Working...' : widget.submitLabel)),
      ],
    );
  }
}

class _EmailCodeDialog extends StatefulWidget {
  const _EmailCodeDialog({
    required this.title,
    required this.description,
    required this.submitLabel,
    required this.onSubmit,
  });

  final String title;
  final String description;
  final String submitLabel;
  final Future<ActionFeedback> Function(String email, String code) onSubmit;

  @override
  State<_EmailCodeDialog> createState() => _EmailCodeDialogState();
}

class _EmailCodeDialogState extends State<_EmailCodeDialog> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  ActionFeedback? _feedback;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    final feedback = await widget.onSubmit(_emailController.text, _codeController.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _feedback = feedback;
    });
    if (!feedback.isError) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.description),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(labelText: 'Code', border: OutlineInputBorder()),
            ),
            if (_feedback != null) ...[
              const SizedBox(height: 12),
              _FeedbackText(feedback: _feedback!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(), child: const Text('Close')),
        FilledButton(onPressed: _submitting ? null : _submit, child: Text(_submitting ? 'Working...' : widget.submitLabel)),
      ],
    );
  }
}

class _PasswordResetDialog extends StatefulWidget {
  const _PasswordResetDialog({
    required this.onRequestPasswordReset,
    required this.onConfirmPasswordReset,
  });

  final Future<ActionFeedback> Function(String email) onRequestPasswordReset;
  final Future<ActionFeedback> Function(String email, String code, String password) onConfirmPasswordReset;

  @override
  State<_PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<_PasswordResetDialog> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  ActionFeedback? _feedback;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<ActionFeedback> Function() action, {bool closeOnSuccess = false}) async {
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    final feedback = await action();
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _feedback = feedback;
    });
    if (closeOnSuccess && !feedback.isError) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Forgot password'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Request a reset code, then set a new password in the same dialog.'),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _submitting
                  ? null
                  : () => _run(() => widget.onRequestPasswordReset(_emailController.text)),
              child: Text(_submitting ? 'Working...' : 'Send reset code'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(labelText: 'Reset code', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password', border: OutlineInputBorder()),
            ),
            if (_feedback != null) ...[
              const SizedBox(height: 12),
              _FeedbackText(feedback: _feedback!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(), child: const Text('Close')),
        FilledButton(
          onPressed: _submitting
              ? null
              : () => _run(
                    () => widget.onConfirmPasswordReset(
                      _emailController.text,
                      _codeController.text,
                      _passwordController.text,
                    ),
                    closeOnSuccess: true,
                  ),
          child: Text(_submitting ? 'Working...' : 'Update password'),
        ),
      ],
    );
  }
}

class _FeedbackText extends StatelessWidget {
  const _FeedbackText({required this.feedback});

  final ActionFeedback feedback;

  @override
  Widget build(BuildContext context) {
    return Text(
      feedback.message,
      style: TextStyle(
        color: feedback.isError ? const Color(0xFFB91C1C) : const Color(0xFF166534),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
    this.apiBaseUrl,
    this.debugSnapshot,
  });

  final String message;
  final Future<void> Function() onRetry;
  final String? apiBaseUrl;
  final ApiDebugSnapshot? debugSnapshot;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            _ApiDebugSummary(
              apiBaseUrl: apiBaseUrl,
              snapshot: debugSnapshot,
            ),
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

class _ApiDebugCard extends StatelessWidget {
  const _ApiDebugCard({
    required this.apiBaseUrl,
    required this.snapshotListenable,
  });

  final String? apiBaseUrl;
  final ValueListenable<ApiDebugSnapshot?>? snapshotListenable;

  @override
  Widget build(BuildContext context) {
    if (snapshotListenable == null) {
      return _ApiDebugSummary(apiBaseUrl: apiBaseUrl, snapshot: null);
    }
    return ValueListenableBuilder<ApiDebugSnapshot?>(
      valueListenable: snapshotListenable!,
      builder: (context, snapshot, child) {
        return _ApiDebugSummary(apiBaseUrl: apiBaseUrl, snapshot: snapshot);
      },
    );
  }
}

class _ApiDebugSummary extends StatelessWidget {
  const _ApiDebugSummary({
    required this.apiBaseUrl,
    required this.snapshot,
  });

  final String? apiBaseUrl;
  final ApiDebugSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: const Color(0xFFF3F4F6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('API base: ${apiBaseUrl ?? 'custom client'}', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            if (snapshot == null)
              const Text('No API response captured yet.')
            else ...[
              Text('${snapshot!.method} ${snapshot!.url}', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(
                'Status ${snapshot!.statusCode} | Content-Type: ${snapshot!.contentType.isEmpty ? 'unknown' : snapshot!.contentType}',
                style: theme.textTheme.bodySmall,
              ),
              if (snapshot!.note != null) ...[
                const SizedBox(height: 8),
                Text(
                  snapshot!.note!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: snapshot!.looksLikeHtml ? const Color(0xFFB91C1C) : const Color(0xFF92400E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SelectableText(
                snapshot!.bodyPreview.isEmpty ? '(empty body)' : snapshot!.bodyPreview,
                style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ],
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

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
