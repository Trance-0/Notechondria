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
part 'core/auth_flows.dart';
part 'core/build_helpers.dart';
part 'core/category_actions.dart';
part 'core/client.dart';
part 'core/course_helpers.dart';
part 'core/draft_helpers.dart';
part 'core/draft_sync.dart';
part 'core/helpers.dart';
part 'core/http_client.dart';
part 'core/http_client_internals.dart';
part 'core/initial_data.dart';
part 'core/load_local_state.dart';
part 'core/local_archive_io.dart';
part 'core/local_course_builders.dart';
part 'core/maintenance_actions.dart';
part 'core/note_crud.dart';
part 'core/local_persist.dart';
part 'core/local_starter.dart';
part 'core/local_store.dart';
part 'core/local_trash.dart';
part 'core/note_loading.dart';
part 'core/note_sessions.dart';
part 'core/settings_actions.dart';
part 'core/settings_helpers.dart';
part 'components/avatar.dart';
part 'components/note_viewer.dart';
part 'modules/learner.dart';
part 'modules/note_editor.dart';
part 'modules/note_editor_attachments.dart';
part 'modules/note_editor_widgets.dart';
part 'modules/note_metadata.dart';
part 'modules/settings.dart';
part 'modules/settings_build.dart';
part 'modules/settings_pages.dart';
part 'modules/settings_sections.dart';

void main() {
  runApp(
    const NotechondriaApp(
      initialIndex: 1,
      title: 'Notechondria Editor',
      visibleIndices: <int>[1, 4],
    ),
  );
}
