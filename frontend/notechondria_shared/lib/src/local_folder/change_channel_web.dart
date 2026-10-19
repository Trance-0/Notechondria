import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'change_channel.dart';
import 'js_bindings_web.dart';

/// [FolderChangeChannel] over `BroadcastChannel`. Messages travel as JSON
/// text, so no structured clone of Dart objects is involved. The `message`
/// listener is a void listener bound with the captured zone's guarded
/// wrapper (main 2.5): a throwing listener reaches `runGuardedApp`'s
/// handler, and a refresh it starts never runs inside a startup budget.
class WebFolderChangeChannel implements FolderChangeChannel {
  WebFolderChangeChannel(Zone zone)
      : _channel = web.BroadcastChannel(kFolderChangeChannelName) {
    _channel.onmessage = bindListener<web.MessageEvent>(zone, (event) {
      final data = event.data;
      if (data == null || !data.isA<JSString>()) return;
      final Object? decoded;
      try {
        decoded = jsonDecode((data as JSString).toDart);
      } on FormatException {
        return;
      }
      if (decoded is Map) {
        _messages.add(Map<String, Object?>.from(decoded));
      }
    }).toJS;
  }

  final web.BroadcastChannel _channel;
  final StreamController<Map<String, Object?>> _messages =
      StreamController<Map<String, Object?>>.broadcast(sync: true);

  @override
  void post(Map<String, Object?> message) =>
      _channel.postMessage(jsonEncode(message).toJS);

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  void close() {
    _channel.close();
    _messages.close();
  }
}
