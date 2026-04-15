library notechondria_frontend;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

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
part 'components/error_state.dart';
part 'components/note_viewer.dart';
part 'components/splash_screen.dart';
part 'modules/front.dart';
part 'modules/learner.dart';
part 'modules/course.dart';
part 'modules/activity.dart';
part 'modules/settings.dart';

void main() {
  runApp(
    const NotechondriaApp(
      initialIndex: 0,
      title: 'Notechondria Portal',
      // 0=Front page, 1=Learner (from editor), 2=Course (from planner),
      // 3=Activity (from planner), 4=Settings. All five visible in portal.
      visibleIndices: <int>[0, 1, 2, 3, 4],
    ),
  );
}
