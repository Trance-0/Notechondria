import '../folder_fs.dart';
import '../folder_index.dart';
import '../folder_journal.dart';
import '../folder_layout.dart';
import '../folder_messages.dart';
import '../note_codec.dart';
import '../router.dart';
import 'notes.dart' show frontmatterWith;
import 'records.dart';

// Course routes (4.1 "Courses"): list, create with the `client_course_id`
// upsert and the per-owner title rule (F12), detail, update, reorder (F13),
// course notes with paging (F14), the "opened" marker (F15), and the
// chunked delete over notes, trashed notes, events, and feeds (3.5, R4).

/// Notes rewritten per chunk of a course delete (6.2 R4).
const int kCourseDeleteChunk = 50;

/// Django's `slugify` for ASCII: lower case, word characters and hyphens,
/// whitespace runs to one hyphen. Other characters are dropped.
String slugifyTitle(String title) {
  final out = StringBuffer();
  for (final c in title.toLowerCase().split('')) {
    if (RegExp(r'[a-z0-9_]').hasMatch(c)) {
      out.write(c);
    } else if (RegExp(r'[\s-]').hasMatch(c)) {
      out.write('-');
    }
  }
  return out
      .toString()
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^[-_]+|[-_]+$'), '');
}

/// `unique_course_slug`: the slug of [title], or `local-course`, with a
/// `-2`, `-3`, ... suffix while `courses/<slug>.json` exists.
Future<String> uniqueCourseSlug(FolderFs fs, String title) async {
  var base = slugifyTitle(title);
  if (base.length > 100) base = base.substring(0, 100);
  if (base.isEmpty) base = 'local-course';
  var candidate = base;
  for (var n = 2; await fs.stat('$kCoursesDir/$candidate.json') != null; n++) {
    candidate = '$base-$n';
  }
  return candidate;
}

Future<CourseRecord> _courseById(LocalHandlerContext ctx, int id) async {
  for (final c in await readCourses(ctx.fs, skip: ctx.skipPaths)) {
    if (c.id == id) return c;
  }
  throw LocalHttpError(404, LocalFolderMessages.courseNotFound(id));
}

Future<Map<String, Object?>> _payload(
        LocalHandlerContext ctx, CourseRecord course) async =>
    (await coursePayloads(ctx, [course])).single;

void _checkTitle(List<CourseRecord> courses, String title,
    {CourseRecord? except}) {
  final lower = title.toLowerCase();
  if (courses.any((c) => c.path != except?.path && c.title.toLowerCase() == lower)) {
    throw LocalHttpError(400, LocalFolderMessages.courseTitleTaken(title));
  }
}

int? _hue(BodyFields b) {
  final hue = b.integer('color_hue');
  if (hue != null && (hue < 0 || hue > 359)) {
    throw b.bad('color_hue must be between 0 and 359');
  }
  return hue;
}

Future<LocalResponse> _list(LocalHandlerContext ctx) async {
  final courses = await readCourses(ctx.fs, skip: ctx.skipPaths)
    ..sort(compareCourses);
  return LocalResponse(200, await coursePayloads(ctx, courses));
}

Future<LocalResponse> _create(LocalHandlerContext ctx) async {
  final b = BodyFields(ctx.request.body,
      consequence: 'Category not saved', process: 'courses');
  final title = b.string('title', maxLength: 120, required: true)!.trim();
  final description = b.string('description') ?? '';
  final client = b.string('client_course_id', maxLength: 64);
  final clientId = client == null || client.isEmpty ? null : client;
  final icon = b.integer('icon');
  final hue = _hue(b);
  final courses = await readCourses(ctx.fs);
  CourseRecord? existing;
  for (final c in courses) {
    if (clientId != null && c.clientCourseId == clientId) existing = c;
  }
  _checkTitle(courses, title, except: existing);
  if (existing != null) {
    final updated = existing.copyWith({
      'title': title,
      'description': description,
      if (b.has('icon')) 'icon': icon,
      'updated_at': ctx.now().toUtc().toIso8601String(),
    });
    await ctx.writeText(updated.path, updated.encode());
    return LocalResponse(200, await _payload(ctx, updated));
  }
  final manifest = await readFolderManifest(ctx.fs);
  if (manifest == null) {
    throw LocalHttpError(503,
        LocalFolderMessages.manifestMissing(ctx.folderName, importPending: false));
  }
  final (next, id) = manifest.allocate('course');
  final slug = await uniqueCourseSlug(ctx.fs, title);
  final course = CourseRecord('$kCoursesDir/$slug.json', {
    'id': id,
    'client_course_id': clientId ?? '',
    'slug': slug,
    'title': title,
    'description': description,
    'icon': icon,
    'color_hue': hue,
    'sort_order': 0,
    'cover_image_url': '',
    'created_at': ctx.now().toUtc().toIso8601String(),
  });
  await ctx.commit(ctx.journal.newRecord([
    JournalWrite(course.path, course.encode()),
    JournalWrite(kManifestPath, next.encode()),
  ]));
  return LocalResponse(201, await _payload(ctx, course));
}

Future<LocalResponse> _update(LocalHandlerContext ctx) async {
  final course = await _courseById(ctx, ctx.request.intParam('id'));
  final b = BodyFields(ctx.request.body,
      consequence: 'Category not saved', process: 'courses');
  final changes = <String, Object?>{};
  if (b.has('title')) {
    final title = b.string('title', maxLength: 120, required: true)!.trim();
    if (title != course.title) {
      _checkTitle(await readCourses(ctx.fs), title, except: course);
    }
    changes['title'] = title;
  }
  if (b.has('description')) changes['description'] = b.string('description') ?? '';
  if (b.has('icon')) changes['icon'] = b.integer('icon');
  if (b.has('color_hue')) changes['color_hue'] = _hue(b);
  final updated = course.copyWith(
      {...changes, 'updated_at': ctx.now().toUtc().toIso8601String()});
  await ctx.writeText(updated.path, updated.encode());
  return LocalResponse(200, await _payload(ctx, updated));
}

Future<LocalResponse> _detail(LocalHandlerContext ctx) async => LocalResponse(
    200, await _payload(ctx, await _courseById(ctx, ctx.request.intParam('id'))));

Future<LocalResponse> _open(LocalHandlerContext ctx) async {
  final course = await _courseById(ctx, ctx.request.intParam('id'));
  final updated = course
      .copyWith({'last_opened_at': ctx.now().toUtc().toIso8601String()});
  await ctx.writeText(updated.path, updated.encode());
  return LocalResponse(200, await _payload(ctx, updated));
}

Future<LocalResponse> _reorder(LocalHandlerContext ctx) async {
  final ids = ctx.request.body['course_ids'];
  if (ids is! List) {
    throw LocalHttpError(
        400,
        LocalFolderMessages.invalidField('Categories not reordered', 'courses',
            'course_ids must be a list of integers'));
  }
  final courses = await readCourses(ctx.fs);
  final byId = {for (final c in courses) c.id!: c};
  final order = <int>[];
  for (final raw in ids) {
    final id = raw is int ? raw : int.tryParse('$raw');
    if (id != null && byId.containsKey(id) && !order.contains(id)) order.add(id);
  }
  final writes = <JournalWrite>[];
  for (var i = 0; i < order.length; i++) {
    final c = byId[order[i]]!;
    if (c.sortOrder == i + 1) continue;
    final updated = c.copyWith({'sort_order': i + 1});
    byId[order[i]] = updated;
    writes.add(JournalWrite(updated.path, updated.encode()));
  }
  if (writes.length == 1) {
    await ctx.writeText(writes.single.path, writes.single.text);
  } else if (writes.isNotEmpty) {
    await ctx.commit(ctx.journal.newRecord(writes));
  }
  final sorted = byId.values.toList()..sort(compareCourses);
  return LocalResponse(200, await coursePayloads(ctx, sorted));
}

Future<LocalResponse> _courseNotes(LocalHandlerContext ctx) async {
  final course = await _courseById(ctx, ctx.request.intParam('id'));
  final notes = (await readNotes(ctx.fs, skip: ctx.skipPaths))
      .where((n) => n.frontmatter.courseSlug == course.slug)
      .toList()
    ..sort(byLastEditDesc);
  final profile = await FolderProfile.read(ctx.fs, folderName: ctx.folderName);
  final lookup = CourseLookup(await readCourses(ctx.fs, skip: ctx.skipPaths));
  List<Map<String, Object?>> rows(Iterable<NoteRecord> list) =>
      [for (final n in list) noteSummary(n, lookup, profile.author)];
  final b = BodyFields(ctx.request.query,
      consequence: 'Category notes not listed', process: 'courses');
  final limit = b.integer('limit');
  if (limit == null) return LocalResponse(200, rows(notes));
  final size = limit.clamp(1, 100);
  final offset = (b.integer('offset') ?? 0) < 0 ? 0 : (b.integer('offset') ?? 0);
  return LocalResponse(200, {
    'results': rows(notes.skip(offset).take(size)),
    'total': notes.length,
    'offset': offset,
    'limit': size,
    'has_more': offset + size < notes.length,
  });
}

/// Nulls `course_id` in every record of [path] that names [id]; one file
/// per chunk (R4). The file keeps its shape (a list, or a keyed list).
Future<void> _detachRecords(LocalHandlerContext ctx, String path, int id) async {
  final text = await readTextOrNull(ctx.fs, path);
  if (text == null) return;
  final json = decodeJsonValue(text);
  final records = recordListOf(json);
  if (records == null || !records.any((r) => r['course_id'] == id)) return;
  final updated = [
    for (final r in records) r['course_id'] == id ? {...r, 'course_id': null} : r,
  ];
  final key = json is Map ? recordListKeyOf(json) : null;
  final out = key == null ? updated : {...(json as Map), key: updated};
  await ctx.writeText(path, encodeFolderJson(out));
}

/// 3.5 delete course, in journaled chunks: notes under `notes/` and
/// `trash/notes/` lose `course_slug`, then `planner/events.json` and
/// `planner/feeds.json` lose `course_id`, then the course file goes. An
/// interrupted delete leaves the course in place; repeating it continues.
Future<LocalResponse> _delete(LocalHandlerContext ctx) async {
  final id = ctx.request.intParam('id');
  final first = await ctx.chunk(() async {
    final course = await _courseById(ctx, id);
    final total = (await readAllNotes(ctx.fs))
        .where((n) => n.frontmatter.courseSlug == course.slug)
        .length;
    return (course: course, total: total);
  });
  final course = first.course;
  final label = "Deleting category '${course.title}'";
  var done = 0;
  try {
    while (await ctx.chunk(() async {
      final named = (await readAllNotes(ctx.fs))
          .where((n) => n.frontmatter.courseSlug == course.slug)
          .take(kCourseDeleteChunk)
          .toList();
      if (named.isEmpty) return false;
      await ctx.commit(ctx.journal.newRecord([
        for (final n in named)
          JournalWrite(
              n.path,
              encodeNoteFile(frontmatterWith(n.frontmatter, courseSlug: null),
                  n.note.body,
                  path: n.path),
              expect: n.expect),
      ]));
      done += named.length;
      ctx.setBusy(LocalFolderMessages.folderBusy(
          'write', label, done, first.total < done ? done : first.total));
      return true;
    })) {}
    for (final path in const [kPlannerEventsPath, kPlannerFeedsPath]) {
      await ctx.chunk(() => _detachRecords(ctx, path, id));
    }
    await ctx.chunk(() => ctx.commit(
        ctx.journal.newRecord(const [], [JournalRemoval(course.path)])));
  } finally {
    ctx.setBusy(null);
  }
  return LocalResponse.noContent;
}

List<LocalRoute> courseRoutes() => [
      LocalRoute('GET', 'courses', _list),
      LocalRoute('POST', 'courses', _create),
      LocalRoute('POST', 'courses/reorder', _reorder),
      LocalRoute('GET', 'courses/{id}', _detail),
      LocalRoute('PATCH', 'courses/{id}', _update),
      LocalRoute('DELETE', 'courses/{id}', _delete, chunked: true),
      LocalRoute('GET', 'courses/{id}/notes', _courseNotes),
      LocalRoute('POST', 'courses/{id}/open', _open),
    ];
