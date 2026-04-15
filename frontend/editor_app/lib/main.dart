library notechondria_frontend;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;
import 'package:notechondria_shared/notechondria_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/url_strategy.dart'
    if (dart.library.html) 'core/url_strategy_web.dart' as url_strategy;

part 'app_shell.dart';
part 'core/client.dart';
part 'core/helpers.dart';
part 'core/local_store.dart';
part 'components/avatar.dart';
part 'components/auth_dialogs.dart';
part 'components/error_state.dart';
part 'components/note_viewer.dart';
part 'components/splash_screen.dart';
part 'modules/learner.dart';
part 'modules/note_editor.dart';
part 'modules/note_metadata.dart';
part 'modules/settings.dart';

void main() {
  runApp(
    const NotechondriaApp(
      initialIndex: 1,
      title: 'Notechondria Editor',
      visibleIndices: <int>[1, 4],
    ),
  );
}
