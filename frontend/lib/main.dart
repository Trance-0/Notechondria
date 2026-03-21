import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_selector/file_selector.dart';
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
  Future<Map<String, dynamic>> listNotes({String? token, String query = '', int offset = 0, int limit = 20});
  Future<Map<String, dynamic>> createNote(String token, Map<String, dynamic> payload);
  Future<Map<String, dynamic>> updateNote(String token, int noteId, Map<String, dynamic> payload);
  Future<List<Map<String, dynamic>>> getNoteHistory(String token, int noteId);
  Future<Map<String, dynamic>> snapshotNote(String token, int noteId, {String reason = 'manual'});
  Future<Map<String, dynamic>> restoreNoteVersion(String token, int noteId, int versionId);
  Future<List<Map<String, dynamic>>> getActivity({String? token});
  Future<Map<String, dynamic>> getActivityWeek(String token);
  Future<List<Map<String, dynamic>>> getCalendarFeeds(String token);
  Future<Map<String, dynamic>> createCalendarFeed(String token, Map<String, dynamic> payload);
  Future<Map<String, dynamic>> updateCalendarFeed(String token, int feedId, Map<String, dynamic> payload);
  Future<void> deleteCalendarFeed(String token, int feedId);
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
  Future<Map<String, dynamic>> listNotes({String? token, String query = '', int offset = 0, int limit = 20}) async {
    final uri = _uri('/notes/').replace(
      queryParameters: {
        'limit': '$limit',
        'offset': '$offset',
        if (query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
    final response = await _httpClient.get(uri, headers: _headers(token: token));
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'GET'));
  }

  @override
  Future<Map<String, dynamic>> createNote(String token, Map<String, dynamic> payload) async {
    final uri = _uri('/notes/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'POST'));
  }

  @override
  Future<Map<String, dynamic>> updateNote(String token, int noteId, Map<String, dynamic> payload) async {
    final uri = _uri('/notes/$noteId/');
    final response = await _httpClient.patch(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'PATCH'));
  }

  @override
  Future<List<Map<String, dynamic>>> getNoteHistory(String token, int noteId) async {
    final uri = _uri('/notes/$noteId/history/');
    final response = await _httpClient.get(uri, headers: _headers(token: token));
    final data = await _decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> snapshotNote(String token, int noteId, {String reason = 'manual'}) async {
    final uri = _uri('/notes/$noteId/snapshot/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode({'reason': reason}),
    );
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'POST'));
  }

  @override
  Future<Map<String, dynamic>> restoreNoteVersion(String token, int noteId, int versionId) async {
    final uri = _uri('/notes/$noteId/restore/$versionId/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode({}),
    );
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'POST'));
  }

  @override
  Future<List<Map<String, dynamic>>> getActivity({String? token}) async {
    final uri = _uri('/activity/');
    final response = await _httpClient.get(uri, headers: _headers(token: token));
    final data = await _decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> getActivityWeek(String token) async {
    final uri = _uri('/activity/week/');
    final response = await _httpClient.get(uri, headers: _headers(token: token));
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'GET'));
  }

  @override
  Future<List<Map<String, dynamic>>> getCalendarFeeds(String token) async {
    final uri = _uri('/calendar-feeds/');
    final response = await _httpClient.get(uri, headers: _headers(token: token));
    final data = await _decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> createCalendarFeed(String token, Map<String, dynamic> payload) async {
    final uri = _uri('/calendar-feeds/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'POST'));
  }

  @override
  Future<Map<String, dynamic>> updateCalendarFeed(String token, int feedId, Map<String, dynamic> payload) async {
    final uri = _uri('/calendar-feeds/$feedId/');
    final response = await _httpClient.patch(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(await _decode(response, uri: uri, method: 'PATCH'));
  }

  @override
  Future<void> deleteCalendarFeed(String token, int feedId) async {
    final uri = _uri('/calendar-feeds/$feedId/');
    final response = await _httpClient.delete(uri, headers: _headers(token: token));
    await _decode(response, uri: uri, method: 'DELETE');
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
  List<Map<String, dynamic>> _learnerNotes = const [];
  List<Map<String, dynamic>> _activity = const [];
  List<Map<String, dynamic>> _plannerEvents = const [];
  List<Map<String, dynamic>> _calendarFeeds = const [];
  Map<String, dynamic>? _activityWeek;
  Map<String, dynamic>? _selectedCourse;
  Map<String, dynamic>? _selectedNote;
  bool _hasMoreLearnerNotes = true;
  bool _isLoadingMoreNotes = false;
  int _learnerNotesOffset = 0;
  String _learnerSearchQuery = '';

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
      List<Map<String, dynamic>> learnerNotes = const [];
      List<Map<String, dynamic>> calendarFeeds = const [];
      Map<String, dynamic>? activityWeek;
      if (_token != null && _token!.isNotEmpty) {
        plannerEvents = await widget.client.getPlannerEvents(_token!);
        calendarFeeds = await widget.client.getCalendarFeeds(_token!);
        activityWeek = await widget.client.getActivityWeek(_token!);
      }
      final notePage = await widget.client.listNotes(token: _token, limit: 20, offset: 0);
      learnerNotes = (notePage['results'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      setState(() {
        _frontPage = frontPage;
        _courses = courses;
        _activity = activity;
        _selectedCourse = selectedCourse;
        _courseNotes = courseNotes;
        _learnerNotes = learnerNotes;
        _selectedNote = selectedNote;
        _plannerEvents = plannerEvents;
        _calendarFeeds = calendarFeeds;
        _activityWeek = activityWeek;
        _hasMoreLearnerNotes = notePage['has_more'] == true;
        _learnerNotesOffset = learnerNotes.length;
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

  Future<void> _loadLearnerNotes({bool reset = false, String? query}) async {
    if (_isLoadingMoreNotes) {
      return;
    }
    final effectiveQuery = query ?? _learnerSearchQuery;
    final nextOffset = reset ? 0 : _learnerNotesOffset;
    setState(() {
      _isLoadingMoreNotes = true;
      if (reset) {
        _learnerSearchQuery = effectiveQuery;
      }
    });
    try {
      final page = await widget.client.listNotes(
        token: _token,
        query: effectiveQuery,
        offset: nextOffset,
        limit: 20,
      );
      final rows = (page['results'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      setState(() {
        _learnerNotes = reset ? rows : [..._learnerNotes, ...rows];
        _hasMoreLearnerNotes = page['has_more'] == true;
        _learnerNotesOffset = (reset ? 0 : _learnerNotesOffset) + rows.length;
        _isLoadingMoreNotes = false;
      });
    } catch (error) {
      setState(() {
        _isLoadingMoreNotes = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
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
      final detail = await _fetchNoteDetail(noteSummary['id'] as int);
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

  Future<Map<String, dynamic>> _fetchNoteDetail(int noteId) async {
    final detail = await widget.client.getNoteDetail(noteId);
    setState(() {
      _selectedNote = detail;
    });
    return detail;
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

  Future<void> _updateSettings(String motto, String socialLink, String editorMode) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    final updated = await widget.client.updateSettings(token, {
      'motto': motto,
      'social_link': socialLink,
      'editor_mode': editorMode,
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

  Future<Map<String, dynamic>> _createNote({
    String? markdown,
    String? title,
  }) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to create notes.');
    }
    final mode = _settings?['editor_mode']?.toString() ?? 'P';
    final initialMarkdown = (markdown ?? '# ${title ?? 'Untitled note'}\n\n').trim();
    final created = await widget.client.createNote(token, {
      'title': title ?? _extractTitleFromMarkdown(initialMarkdown),
      'description': _excerptFromMarkdown(initialMarkdown),
      'content': initialMarkdown,
      'editor_mode': mode,
      'course_id': _selectedCourse?['id'],
      'metadata_json': jsonEncode({'section': '', 'autosave': false}),
    });
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    setState(() {
      _selectedNote = created;
      _selectedIndex = 1;
    });
    return created;
  }

  Future<Map<String, dynamic>> _saveNote(int noteId, Map<String, dynamic> payload) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to save notes.');
    }
    final updated = await widget.client.updateNote(token, noteId, payload);
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    setState(() {
      _selectedNote = updated;
    });
    return updated;
  }

  Future<List<Map<String, dynamic>>> _getNoteHistory(int noteId) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const [];
    }
    return widget.client.getNoteHistory(token, noteId);
  }

  Future<Map<String, dynamic>> _snapshotNote(int noteId, {String reason = 'manual'}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to snapshot notes.');
    }
    return widget.client.snapshotNote(token, noteId, reason: reason);
  }

  Future<Map<String, dynamic>> _restoreNoteVersion(int noteId, int versionId) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to restore notes.');
    }
    final restored = await widget.client.restoreNoteVersion(token, noteId, versionId);
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
    setState(() {
      _selectedNote = restored;
    });
    return restored;
  }

  Future<void> _importMarkdownNote() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Markdown', extensions: ['md', 'markdown', 'txt']),
        ],
      );
      if (file == null) {
        return;
      }
      final contents = await file.readAsString();
      final created = await _createNote(markdown: contents, title: _extractTitleFromMarkdown(contents));
      _showMessage("Imported '${created['title']}'.");
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _exportNote(Map<String, dynamic> note) async {
    try {
      final detail = note['content'] != null ? note : await widget.client.getNoteDetail(note['id'] as int);
      final location = await getSaveLocation(
        suggestedName: '${detail['title'] ?? 'note'}.md',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Markdown', extensions: ['md']),
        ],
      );
      if (location == null) {
        return;
      }
      final bytes = Uint8List.fromList(utf8.encode(detail['content']?.toString() ?? _noteToMarkdown(detail)));
      final file = XFile.fromData(bytes, name: '${detail['title'] ?? 'note'}.md', mimeType: 'text/markdown');
      await file.saveTo(location.path);
      _showMessage("Exported '${detail['title'] ?? 'note'}'.");
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _refreshCalendarState() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    final feeds = await widget.client.getCalendarFeeds(token);
    final week = await widget.client.getActivityWeek(token);
    setState(() {
      _calendarFeeds = feeds;
      _activityWeek = week;
    });
  }

  Future<void> _importCalendarFeed(String rawIcal, String title, {int? courseId}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to import calendars.');
    }
    await widget.client.createCalendarFeed(token, {
      'title': title,
      'source_kind': 'I',
      'raw_ical': rawIcal,
      'course_id': courseId,
    });
    await _refreshCalendarState();
  }

  Future<void> _subscribeCalendarFeed(String title, String url, {int? courseId}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Sign in to subscribe calendars.');
    }
    await widget.client.createCalendarFeed(token, {
      'title': title,
      'source_kind': 'S',
      'source_url': url,
      'course_id': courseId,
    });
    await _refreshCalendarState();
  }

  Future<void> _toggleCalendarFeed(Map<String, dynamic> feed, bool enabled) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    await widget.client.updateCalendarFeed(token, feed['id'] as int, {'is_enabled': enabled});
    await _refreshCalendarState();
  }

  Future<void> _deleteCalendarFeed(Map<String, dynamic> feed) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    await widget.client.deleteCalendarFeed(token, feed['id'] as int);
    await _refreshCalendarState();
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        children: [
                          _SidebarItem(
                            icon: Icons.home_outlined,
                            label: 'Front',
                            selected: _selectedIndex == 0,
                            onTap: () => _handleDestinationSelected(0),
                          ),
                          _SidebarItem(
                            icon: Icons.menu_book_outlined,
                            label: 'Learner',
                            selected: _selectedIndex == 1,
                            onTap: () => _handleDestinationSelected(1),
                          ),
                          _SidebarItem(
                            icon: Icons.school_outlined,
                            label: 'Course',
                            selected: _selectedIndex == 2,
                            onTap: () => _handleDestinationSelected(2),
                          ),
                          _SidebarItem(
                            icon: Icons.timeline_outlined,
                            label: 'Activity',
                            selected: _selectedIndex == 3,
                            onTap: () => _handleDestinationSelected(3),
                          ),
                          const Spacer(),
                          _SidebarItem(
                            icon: Icons.settings_outlined,
                            label: 'Settings',
                            selected: _selectedIndex == 4,
                            onTap: () => _handleDestinationSelected(4),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
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
          notes: _learnerNotes,
          courses: _courses,
          selectedNote: _selectedNote,
          editorMode: _settings?['editor_mode']?.toString() ?? 'P',
          hasMoreNotes: _hasMoreLearnerNotes,
          isLoadingMore: _isLoadingMoreNotes,
          searchQuery: _learnerSearchQuery,
          isAuthenticated: _token != null && _token!.isNotEmpty,
          onSearchChanged: (value) => _loadLearnerNotes(reset: true, query: value),
          onLoadMore: () => _loadLearnerNotes(),
          onOpenNote: _selectNote,
          onFetchNoteDetail: _fetchNoteDetail,
          onCreateNote: _createNote,
          onImportMarkdown: _importMarkdownNote,
          onExportNote: _exportNote,
          onSaveNote: _saveNote,
          onGetNoteHistory: _getNoteHistory,
          onSnapshotNote: _snapshotNote,
          onRestoreNoteVersion: _restoreNoteVersion,
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
        return _ActivityPage(
          activity: _activity,
          activityWeek: _activityWeek,
          isAuthenticated: _token != null && _token!.isNotEmpty,
          onOpenNote: _selectNote,
          onImportCalendar: _importCalendarFeed,
          onSubscribeCalendar: _subscribeCalendarFeed,
        );
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
          calendarFeeds: _calendarFeeds,
          courses: _courses,
          onToggleCalendarFeed: _toggleCalendarFeed,
          onDeleteCalendarFeed: _deleteCalendarFeed,
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

class _LearnerPage extends StatefulWidget {
  const _LearnerPage({
    required this.notes,
    required this.courses,
    required this.selectedNote,
    required this.editorMode,
    required this.hasMoreNotes,
    required this.isLoadingMore,
    required this.searchQuery,
    required this.isAuthenticated,
    required this.onSearchChanged,
    required this.onLoadMore,
    required this.onOpenNote,
    required this.onFetchNoteDetail,
    required this.onCreateNote,
    required this.onImportMarkdown,
    required this.onExportNote,
    required this.onSaveNote,
    required this.onGetNoteHistory,
    required this.onSnapshotNote,
    required this.onRestoreNoteVersion,
  });

  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> courses;
  final Map<String, dynamic>? selectedNote;
  final String editorMode;
  final bool hasMoreNotes;
  final bool isLoadingMore;
  final String searchQuery;
  final bool isAuthenticated;
  final ValueChanged<String> onSearchChanged;
  final Future<void> Function() onLoadMore;
  final ValueChanged<Map<String, dynamic>> onOpenNote;
  final Future<Map<String, dynamic>> Function(int noteId) onFetchNoteDetail;
  final Future<Map<String, dynamic>> Function({String? markdown, String? title}) onCreateNote;
  final Future<void> Function() onImportMarkdown;
  final Future<void> Function(Map<String, dynamic> note) onExportNote;
  final Future<Map<String, dynamic>> Function(int noteId, Map<String, dynamic> payload) onSaveNote;
  final Future<List<Map<String, dynamic>>> Function(int noteId) onGetNoteHistory;
  final Future<Map<String, dynamic>> Function(int noteId, {String reason}) onSnapshotNote;
  final Future<Map<String, dynamic>> Function(int noteId, int versionId) onRestoreNoteVersion;

  @override
  State<_LearnerPage> createState() => _LearnerPageState();
}

class _LearnerPageState extends State<_LearnerPage> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchQuery);
  }

  @override
  void didUpdateWidget(covariant _LearnerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery && _searchController.text != widget.searchQuery) {
      _searchController.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openEditor(Map<String, dynamic> noteSummary) async {
    final detail = await widget.onFetchNoteDetail(noteSummary['id'] as int);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _NoteEditorDialog(
        note: detail,
        courses: widget.courses,
        editorMode: widget.editorMode,
        onSave: widget.onSaveNote,
        onSnapshot: widget.onSnapshotNote,
        onGetHistory: widget.onGetNoteHistory,
        onRestoreVersion: widget.onRestoreNoteVersion,
      ),
    );
  }

  Future<void> _createAndOpenNote() async {
    final created = await widget.onCreateNote(title: 'Untitled note');
    if (!mounted) {
      return;
    }
    await _openEditor(created);
  }

  Future<void> _showComposerMenu(TapDownDetails? details) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          details?.globalPosition ?? const Offset(0, 0),
          details?.globalPosition ?? const Offset(0, 0),
        ),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'new', child: Text('Create note')),
        PopupMenuItem(value: 'import', child: Text('Import markdown')),
      ],
    );
    if (selected == 'import') {
      await widget.onImportMarkdown();
    } else if (selected == 'new') {
      await _createAndOpenNote();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          children: [
            TextField(
              controller: _searchController,
              onChanged: widget.onSearchChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search recent notes',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.selectedNote != null) ...[
              _SelectedNotePanel(
                note: widget.selectedNote!,
                canEdit: widget.isAuthenticated,
                onEdit: widget.isAuthenticated ? () => _openEditor(widget.selectedNote!) : null,
              ),
              const SizedBox(height: 20),
            ],
            Text('Recent notes', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (widget.notes.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    widget.isAuthenticated
                        ? 'No notes yet. Use the add button to create one.'
                        : 'Sign in to create and sync notes. Public course materials stay available without login.',
                  ),
                ),
              ),
            for (final note in widget.notes)
              _LearnerNoteCard(
                note: note,
                canEdit: widget.isAuthenticated,
                onOpen: () => widget.onOpenNote(note),
                onEdit: () => _openEditor(note),
                onExport: () => widget.onExportNote(note),
              ),
            if (widget.hasMoreNotes) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: widget.isLoadingMore ? null : widget.onLoadMore,
                  child: Text(widget.isLoadingMore ? 'Loading...' : 'Load more'),
                ),
              ),
            ],
          ],
        ),
        Positioned(
          right: 24,
          bottom: 24,
          child: GestureDetector(
            onLongPress: widget.isAuthenticated ? widget.onImportMarkdown : null,
            onSecondaryTapDown: widget.isAuthenticated ? _showComposerMenu : null,
            child: FloatingActionButton.extended(
              onPressed: widget.isAuthenticated ? _createAndOpenNote : null,
              icon: const Icon(Icons.add),
              label: const Text('Add note'),
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

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFD1FAE5) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? const Color(0xFF065F46) : const Color(0xFF374151)),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? const Color(0xFF065F46) : const Color(0xFF374151),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LearnerNoteCard extends StatelessWidget {
  const _LearnerNoteCard({
    required this.note,
    required this.canEdit,
    required this.onOpen,
    required this.onEdit,
    required this.onExport,
  });

  final Map<String, dynamic> note;
  final bool canEdit;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final Future<void> Function() onExport;

  @override
  Widget build(BuildContext context) {
    final previewLines = (note['preview_lines'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .take(3)
        .toList();
    return Card(
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      note['title']?.toString() ?? 'Untitled note',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        onEdit();
                      } else if (value == 'export') {
                        await onExport();
                      }
                    },
                    itemBuilder: (context) => [
                      if (canEdit) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'export', child: Text('Export markdown')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                previewLines.isEmpty ? (note['excerpt']?.toString() ?? '') : previewLines.join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  _formatCompactTimestamp(note['last_edit']?.toString() ?? ''),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedNotePanel extends StatelessWidget {
  const _SelectedNotePanel({
    required this.note,
    required this.canEdit,
    this.onEdit,
  });

  final Map<String, dynamic> note;
  final bool canEdit;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final content = note['content']?.toString().trim();
    final body = (content == null || content.isEmpty) ? _noteToMarkdown(note) : content;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note['title']?.toString() ?? 'Untitled note',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatCompactTimestamp(note['last_edit']?.toString() ?? ''),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ),
                if (canEdit && onEdit != null)
                  FilledButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            MarkdownBody(data: body),
          ],
        ),
      ),
    );
  }
}

class _NoteEditorDialog extends StatefulWidget {
  const _NoteEditorDialog({
    required this.note,
    required this.courses,
    required this.editorMode,
    required this.onSave,
    required this.onSnapshot,
    required this.onGetHistory,
    required this.onRestoreVersion,
  });

  final Map<String, dynamic> note;
  final List<Map<String, dynamic>> courses;
  final String editorMode;
  final Future<Map<String, dynamic>> Function(int noteId, Map<String, dynamic> payload) onSave;
  final Future<Map<String, dynamic>> Function(int noteId, {String reason}) onSnapshot;
  final Future<List<Map<String, dynamic>>> Function(int noteId) onGetHistory;
  final Future<Map<String, dynamic>> Function(int noteId, int versionId) onRestoreVersion;

  @override
  State<_NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<_NoteEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  Timer? _autosaveTimer;
  DateTime? _lastSavedAt;
  String? _saveError;
  bool _dirty = false;
  bool _saving = false;
  late Map<String, dynamic> _note;
  late Map<String, dynamic> _metadata;

  @override
  void initState() {
    super.initState();
    _note = Map<String, dynamic>.from(widget.note);
    _metadata = _decodeNoteMetadata(_note['metadata_json']?.toString() ?? '');
    _titleController = TextEditingController(text: _note['title']?.toString() ?? 'Untitled note');
    _bodyController = TextEditingController(text: _bodyWithoutTitle(_note['content']?.toString() ?? ''));
    _titleController.addListener(_handleChanged);
    _bodyController.addListener(_handleChanged);
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _handleChanged() {
    _dirty = true;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(seconds: 10), () {
      _save(reason: 'autosave');
    });
    setState(() {});
  }

  Future<void> _save({String reason = 'manual'}) async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final updated = await widget.onSave(
        _note['id'] as int,
        {
          'title': _titleController.text.trim().isEmpty ? 'Untitled note' : _titleController.text.trim(),
          'description': _metadata['description'] ?? '',
          'course_id': _metadata['course_id'],
          'content': _composeMarkdown(_titleController.text, _bodyController.text),
          'metadata_json': jsonEncode(_metadata),
          'editor_mode': widget.editorMode,
        },
      );
      _note = updated;
      _dirty = false;
      _lastSavedAt = DateTime.now();
    } catch (error) {
      _saveError = error.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) {
      setState(() {
        _saving = false;
      });
    }
  }

  Future<void> _openDetails() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _NoteMetadataDialog(
        note: _note,
        courses: widget.courses,
        metadata: _metadata,
        onGetHistory: widget.onGetHistory,
        onRestoreVersion: widget.onRestoreVersion,
      ),
    );
    if (result == null) {
      return;
    }
    final restoredRaw = result['restored_note'];
    if (restoredRaw is Map) {
      final restored = Map<String, dynamic>.from(restoredRaw);
      final restoredMetadata = _decodeNoteMetadata(restored['metadata_json']?.toString() ?? '');
      _autosaveTimer?.cancel();
      setState(() {
        _note = restored;
        _metadata = restoredMetadata;
        _titleController.text = restored['title']?.toString() ?? 'Untitled note';
        _bodyController.text = _bodyWithoutTitle(restored['content']?.toString() ?? '');
        _dirty = false;
        _saveError = null;
        _lastSavedAt = DateTime.now();
      });
      return;
    }
    final metadata = Map<String, dynamic>.from(result['metadata'] as Map? ?? result);
    setState(() {
      _metadata = metadata;
    });
    await _save(reason: 'metadata');
  }

  @override
  Widget build(BuildContext context) {
    final showPreview = widget.editorMode == 'G';
    final showFallbackBanner = widget.editorMode == 'B';
    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 8,
                    child: TextField(
                      controller: _titleController,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      decoration: const InputDecoration(border: InputBorder.none, hintText: 'Title'),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _SaveStatus(
                        lastSavedAt: _lastSavedAt,
                        errorMessage: _saveError,
                        saving: _saving,
                      ),
                    ),
                  ),
                  IconButton(onPressed: _openDetails, icon: const Icon(Icons.more_horiz)),
                  IconButton(
                    onPressed: () async {
                      _autosaveTimer?.cancel();
                      if (_dirty) {
                        await _save(reason: 'close');
                        await widget.onSnapshot(_note['id'] as int, reason: 'quit');
                      }
                      if (mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (showFallbackBanner)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Blocks mode currently uses the plain-text fallback editor.'),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _bodyController,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: const InputDecoration(
                          hintText: 'Write your note...',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ),
                    if (showPreview) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: MarkdownBody(data: _composeMarkdown(_titleController.text, _bodyController.text)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteMetadataDialog extends StatefulWidget {
  const _NoteMetadataDialog({
    required this.note,
    required this.courses,
    required this.metadata,
    required this.onGetHistory,
    required this.onRestoreVersion,
  });

  final Map<String, dynamic> note;
  final List<Map<String, dynamic>> courses;
  final Map<String, dynamic> metadata;
  final Future<List<Map<String, dynamic>>> Function(int noteId) onGetHistory;
  final Future<Map<String, dynamic>> Function(int noteId, int versionId) onRestoreVersion;

  @override
  State<_NoteMetadataDialog> createState() => _NoteMetadataDialogState();
}

class _NoteMetadataDialogState extends State<_NoteMetadataDialog> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _sectionController;
  int? _courseId;
  late Future<List<Map<String, dynamic>>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(text: widget.metadata['description']?.toString() ?? widget.note['description']?.toString() ?? '');
    _sectionController = TextEditingController(text: widget.metadata['section']?.toString() ?? '');
    _courseId = (widget.metadata['course_id'] as num?)?.toInt() ?? (widget.note['course']?['id'] as num?)?.toInt();
    _historyFuture = widget.onGetHistory(widget.note['id'] as int);
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Note details'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int?>(
                value: _courseId,
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('No assigned course')),
                  ...widget.courses.map(
                    (course) => DropdownMenuItem<int?>(
                      value: course['id'] as int,
                      child: Text(course['title']?.toString() ?? 'Course'),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _courseId = value),
                decoration: const InputDecoration(labelText: 'Assigned course / plan', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sectionController,
                decoration: const InputDecoration(labelText: 'Section', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Short description / comments', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Text('Version history', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _historyFuture,
                  builder: (context, snapshot) {
                    final rows = snapshot.data ?? const [];
                    if (rows.isEmpty) {
                      return const Text('No saved versions yet.');
                    }
                    return ListView(
                      children: [
                        for (final version in rows)
                          ListTile(
                            dense: true,
                            title: Text(version['reason']?.toString() ?? 'Version'),
                            subtitle: Text(_formatCompactTimestamp(version['date_created']?.toString() ?? '')),
                            trailing: TextButton(
                              onPressed: () async {
                                final restored = await widget.onRestoreVersion(widget.note['id'] as int, version['id'] as int);
                                if (mounted) {
                                  Navigator.of(context).pop({
                                    'metadata': {
                                      'description': _descriptionController.text,
                                      'section': _sectionController.text,
                                      'course_id': _courseId,
                                    },
                                    'restored_note': restored,
                                  });
                                }
                              },
                              child: const Text('Restore'),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'description': _descriptionController.text,
            'section': _sectionController.text,
            'course_id': _courseId,
          }),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _SaveStatus extends StatelessWidget {
  const _SaveStatus({
    required this.lastSavedAt,
    required this.errorMessage,
    required this.saving,
  });

  final DateTime? lastSavedAt;
  final String? errorMessage;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    if (saving) {
      return const Text('Saving...');
    }
    if (errorMessage != null && errorMessage!.isNotEmpty) {
      return Tooltip(
        message: errorMessage!,
        child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
      );
    }
    return Text(
      lastSavedAt == null ? 'Not saved' : 'Saved ${_formatTime(lastSavedAt!)}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _ActivityPage extends StatelessWidget {
  const _ActivityPage({
    required this.activity,
    required this.activityWeek,
    required this.isAuthenticated,
    required this.onOpenNote,
    required this.onImportCalendar,
    required this.onSubscribeCalendar,
  });

  final List<Map<String, dynamic>> activity;
  final Map<String, dynamic>? activityWeek;
  final bool isAuthenticated;
  final ValueChanged<Map<String, dynamic>> onOpenNote;
  final Future<void> Function(String rawIcal, String title, {int? courseId}) onImportCalendar;
  final Future<void> Function(String title, String url, {int? courseId}) onSubscribeCalendar;

  @override
  Widget build(BuildContext context) {
    final weekDays = (activityWeek?['days'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Text('Week calendar', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            if (isAuthenticated) ...[
              OutlinedButton(
                onPressed: () => _showImportCalendarDialog(context, onImportCalendar),
                child: const Text('Import iCal'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _showSubscribeCalendarDialog(context, onSubscribeCalendar),
                child: const Text('Subscribe'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (weekDays.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sign in to see your study week calendar and subscribed calendars.'),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final day in weekDays)
                  Container(
                    width: 180,
                    margin: const EdgeInsets.only(right: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatWeekDay(day['date']?.toString() ?? ''),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            for (final event in (day['events'] as List<dynamic>? ?? const []))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: event['kind'] == 'plan' ? const Color(0xFFDFF6E9) : const Color(0xFFE0F2FE),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(event['title']?.toString() ?? 'Event'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
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
    required this.calendarFeeds,
    required this.courses,
    required this.onToggleCalendarFeed,
    required this.onDeleteCalendarFeed,
    this.apiBaseUrl,
    this.debugSnapshotListenable,
  });

  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? settings;
  final Future<void> Function(String motto, String socialLink, String editorMode) onSave;
  final Future<void> Function() onLogout;
  final Future<ActionFeedback> Function(String email, String password) onRegister;
  final Future<ActionFeedback> Function(String email, String code) onVerify;
  final Future<ActionFeedback> Function(String email, String password) onLogin;
  final Future<ActionFeedback> Function(String email) onRequestPasswordReset;
  final Future<ActionFeedback> Function(String email, String code, String password) onConfirmPasswordReset;
  final List<Map<String, dynamic>> calendarFeeds;
  final List<Map<String, dynamic>> courses;
  final Future<void> Function(Map<String, dynamic> feed, bool enabled) onToggleCalendarFeed;
  final Future<void> Function(Map<String, dynamic> feed) onDeleteCalendarFeed;
  final String? apiBaseUrl;
  final ValueListenable<ApiDebugSnapshot?>? debugSnapshotListenable;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late final TextEditingController _mottoController;
  late final TextEditingController _socialController;
  String _editorMode = 'P';

  @override
  void initState() {
    super.initState();
    _mottoController = TextEditingController(text: widget.settings?['motto']?.toString() ?? '');
    _socialController = TextEditingController(text: widget.settings?['social_link']?.toString() ?? '');
    _editorMode = widget.settings?['editor_mode']?.toString() ?? 'P';
  }

  @override
  void didUpdateWidget(covariant _SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _mottoController.text = widget.settings?['motto']?.toString() ?? '';
      _socialController.text = widget.settings?['social_link']?.toString() ?? '';
      _editorMode = widget.settings?['editor_mode']?.toString() ?? 'P';
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
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _editorMode,
            items: const [
              DropdownMenuItem(value: 'G', child: Text('GFM live preview')),
              DropdownMenuItem(value: 'B', child: Text('Blocks fallback')),
              DropdownMenuItem(value: 'P', child: Text('Plain text')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _editorMode = value;
                });
              }
            },
            decoration: const InputDecoration(labelText: 'Editor mode', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => widget.onSave(_mottoController.text, _socialController.text, _editorMode),
            child: const Text('Save settings'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: widget.onLogout,
            child: const Text('Logout'),
          ),
          const SizedBox(height: 24),
          Text('Calendars', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (widget.calendarFeeds.isEmpty)
            const Text('No imported or subscribed calendars yet.')
          else
            for (final feed in widget.calendarFeeds)
              Card(
                child: ListTile(
                  title: Text(feed['title']?.toString() ?? 'Calendar'),
                  subtitle: Text(feed['source_kind']?.toString() == 'S' ? 'Subscription' : 'Imported iCal'),
                  leading: Switch(
                    value: feed['is_enabled'] == true,
                    onChanged: (value) => widget.onToggleCalendarFeed(feed, value),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => widget.onDeleteCalendarFeed(feed),
                  ),
                ),
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
                      description: 'Sign in with your email and password. Admin username also works for the bootstrapped Django admin account.',
                      submitLabel: 'Login',
                      emailLabel: 'Email or username',
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
    this.emailLabel = 'Email',
  });

  final String title;
  final String description;
  final String submitLabel;
  final Future<ActionFeedback> Function(String email, String password) onSubmit;
  final String emailLabel;

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
              decoration: InputDecoration(labelText: widget.emailLabel, border: const OutlineInputBorder()),
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

String _composeMarkdown(String title, String body) {
  final normalizedTitle = title.trim().isEmpty ? 'Untitled note' : title.trim();
  final normalizedBody = _bodyWithoutTitle(body);
  return '# $normalizedTitle\n\n$normalizedBody'.trim();
}

String _bodyWithoutTitle(String markdown) {
  final lines = markdown.split('\n');
  if (lines.isNotEmpty && lines.first.trim().startsWith('# ')) {
    return lines.skip(1).join('\n').trimLeft();
  }
  return markdown;
}

String _extractTitleFromMarkdown(String markdown) {
  for (final line in markdown.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('# ')) {
      return trimmed.substring(2).trim();
    }
  }
  return 'Untitled note';
}

String _excerptFromMarkdown(String markdown) {
  final body = _bodyWithoutTitle(markdown).trim();
  return body.length <= 180 ? body : '${body.substring(0, 180)}...';
}

Map<String, dynamic> _decodeNoteMetadata(String raw) {
  if (raw.trim().isEmpty) {
    return {};
  }
  try {
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  } catch (_) {
    return {};
  }
}

String _formatCompactTimestamp(String raw) {
  if (raw.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  final now = DateTime.now();
  final local = parsed.toLocal();
  final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
  if (local.isAfter(startOfWeek) && local.year == now.year) {
    return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][local.weekday - 1];
  }
  if (local.year == now.year) {
    return '${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }
  return '${(local.year % 100).toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
}

String _formatTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:${value.minute.toString().padLeft(2, '0')} $suffix';
}

String _formatWeekDay(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  return '${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][parsed.weekday - 1]} ${parsed.month.toString().padLeft(2, '0')}/${parsed.day.toString().padLeft(2, '0')}';
}

Future<void> _showImportCalendarDialog(
  BuildContext context,
  Future<void> Function(String rawIcal, String title, {int? courseId}) onImport,
) async {
  final file = await openFile(
    acceptedTypeGroups: [const XTypeGroup(label: 'iCal', extensions: ['ics'])],
  );
  if (file == null) {
    return;
  }
  final rawIcal = await file.readAsString();
  if (!context.mounted) {
    return;
  }
  await onImport(rawIcal, file.name);
}

Future<void> _showSubscribeCalendarDialog(
  BuildContext context,
  Future<void> Function(String title, String url, {int? courseId}) onSubscribe,
) async {
  final titleController = TextEditingController();
  final urlController = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Subscribe to calendar'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: 'iCal URL', border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            await onSubscribe(titleController.text.trim().isEmpty ? 'Subscribed calendar' : titleController.text.trim(), urlController.text.trim());
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Text('Subscribe'),
        ),
      ],
    ),
  );
}
