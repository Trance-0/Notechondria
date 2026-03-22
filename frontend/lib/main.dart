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
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;
import 'package:shared_preferences/shared_preferences.dart';

part 'app_shell.dart';
part 'core/client.dart';
part 'core/helpers.dart';
part 'core/local_store.dart';
part 'components/navigation.dart';
part 'components/avatar.dart';
part 'components/debug_widgets.dart';
part 'components/error_state.dart';
part 'components/note_viewer.dart';
part 'modules/front.dart';
part 'modules/learner.dart';
part 'modules/course.dart';
part 'modules/activity.dart';
part 'modules/settings.dart';

void main() {
  runApp(const NotechondriaApp());
}
