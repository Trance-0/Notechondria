import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/src/local_folder/note_codec.dart';

void main() {
  const uuid = '1b4e28ba-2fa1-41d2-883f-0016d3cca427';
  const fm = NoteFrontmatter(
    title: 'Krebs "TCA" cycle',
    uuid: uuid,
    courseSlug: 'bio-101',
    isPublic: true,
    editorMode: 'G',
    lastEdit: '2026-10-19T10:00:00+00:00',
    dateCreated: '2026-10-01T09:00:00+00:00',
  );
  const appBody = 'Intro\n\n![diagram](nc-folder:///assets/notes/abc/attachments/a.png)\n'
      '<img src="nc-folder:///assets/notes/abc/attachments/b.svg">\n'
      '[external](https://example.com/x.png)\n';

  group('round trip', () {
    test('frontmatter, body, and links survive encode then decode', () {
      final text = encodeNoteFile(fm, appBody, path: 'notes/abc.md');
      final back = decodeNoteFile(text, path: 'notes/abc.md');
      expect(back.hasFrontmatter, isTrue);
      expect(back.body, appBody);
      expect(back.frontmatter.title, fm.title);
      expect(back.frontmatter.uuid, uuid);
      expect(back.frontmatter.courseSlug, 'bio-101');
      expect(back.frontmatter.isPublic, isTrue);
      expect(back.frontmatter.editorMode, 'G');
      expect(back.frontmatter.lastEdit, fm.lastEdit);
      expect(back.frontmatter.dateCreated, fm.dateCreated);
      expect(encodeNoteFile(back.frontmatter, back.body, path: 'notes/abc.md'),
          text);
    });

    test('on disk, links are relative to the note file (3.2, 3.6)', () {
      final live = encodeNoteFile(fm, appBody, path: 'notes/abc.md');
      expect(live, contains('](../assets/notes/abc/attachments/a.png)'));
      expect(live, contains('src="../assets/notes/abc/attachments/b.svg"'));
      expect(live, isNot(contains('nc-folder:')));
      expect(live, contains('https://example.com/x.png'));
      final trashed = encodeNoteFile(fm, appBody, path: 'trash/notes/abc.md');
      expect(trashed, contains('](../../assets/notes/abc/attachments/a.png)'));
      expect(decodeNoteFile(trashed, path: 'trash/notes/abc.md').body, appBody);
    });

    test('the frontmatter uses the github_sync quoted-scalar subset', () {
      final text = encodeNoteFile(fm, 'x', path: 'notes/abc.md');
      final lines = const LineSplitter().convert(text);
      expect(lines.take(9).toList(), [
        '---',
        r'title: "Krebs \"TCA\" cycle"',
        'uuid: "$uuid"',
        'course_slug: "bio-101"',
        'is_public: true',
        'editor_mode: "G"',
        'last_edit: "2026-10-19T10:00:00+00:00"',
        'date_created: "2026-10-01T09:00:00+00:00"',
        '---',
      ]);
      expect(text.endsWith('\n\nx\n'), isTrue);
    });

    test('backslashes and quotes round-trip; newlines in titles become spaces',
        () {
      const tricky = NoteFrontmatter(title: r'a\b "c"' '\nd');
      final back = decodeNoteFile(
          encodeNoteFile(tricky, '', path: 'notes/x.md'),
          path: 'notes/x.md');
      expect(back.frontmatter.title, r'a\b "c" d');
      expect(back.frontmatter.courseSlug, isNull);
    });

    test('a body ending in a newline keeps it', () {
      final back = decodeNoteFile(
          encodeNoteFile(fm, 'line\n', path: 'notes/a.md'),
          path: 'notes/a.md');
      expect(back.body, 'line\n');
    });
  });

  group('reading files written elsewhere', () {
    test('a github_sync file with custom keys after the system keys', () {
      const text = '---\n'
          'title: "Week 1"\n'
          'uuid: "$uuid"\n'
          'course_slug: null\n'
          'is_public: false\n'
          'editor_mode: "P"\n'
          'last_edit: "2026-01-01T00:00:00+00:00"\n'
          'date_created: "2026-01-01T00:00:00+00:00"\n'
          'title_override: "ignored"\n'
          '---\n\nBody line\n';
      final note = decodeNoteFile(text, path: 'notes/$uuid.md');
      expect(note.frontmatter.title, 'Week 1');
      expect(note.frontmatter.courseSlug, isNull);
      expect(note.frontmatter.isPublic, isFalse);
      expect(note.body, 'Body line');
      expect(note.rawFrontmatter['title_override'], 'ignored');
      final rewritten =
          encodeNoteFile(note.frontmatter, note.body, path: 'notes/$uuid.md');
      expect(rewritten, isNot(contains('title_override')));
    });

    test('hand-edited unquoted and single-quoted values', () {
      const text = "---\ntitle: My plain title\nis_public: true\ncourse_slug: 'it''s'\n---\nBody";
      final note = decodeNoteFile(text, path: 'notes/plain.md');
      expect(note.frontmatter.title, 'My plain title');
      expect(note.frontmatter.isPublic, isTrue);
      expect(note.frontmatter.courseSlug, "it's");
      expect(note.frontmatter.uuid, isNull);
      expect(note.body, 'Body');
    });

    test('a file without frontmatter is all body; title from # or stem', () {
      final a = decodeNoteFile('# Heading\ntext', path: 'notes/hand.md');
      expect(a.hasFrontmatter, isFalse);
      expect(a.frontmatter.title, 'Heading');
      expect(a.body, '# Heading\ntext');
      expect(decodeNoteFile('text', path: 'notes/hand.md').frontmatter.title,
          'hand');
    });

    test('CRLF files decode', () {
      const text = '---\r\ntitle: "W"\r\nuuid: "$uuid"\r\n---\r\n\r\nBody\r\n';
      final note = decodeNoteFile(text, path: 'notes/w.md');
      expect(note.frontmatter.title, 'W');
      expect(note.frontmatter.uuid, uuid);
      expect(note.body.trimRight(), 'Body');
    });

    test('frontmatterUuidOf and replaceFrontmatterUuid', () {
      final text = encodeNoteFile(fm, appBody, path: 'notes/abc.md');
      expect(frontmatterUuidOf(text), uuid);
      const fresh = '2c5ea4c0-4067-41fb-8f04-0c0f1e8cbe00';
      final replaced = replaceFrontmatterUuid(text, fresh)!;
      expect(frontmatterUuidOf(replaced), fresh);
      expect(replaced.replaceFirst(fresh, uuid), text);
      expect(replaceFrontmatterUuid('no frontmatter', fresh), isNull);
      expect(frontmatterUuidOf('no frontmatter'), isNull);
    });
  });

  group('sidecar', () {
    test('known and unknown keys round-trip', () {
      final sidecar = decodeSidecar(jsonEncode({
        'schema_version': 1,
        'id': 7,
        'uuid': uuid,
        'sharing_id': 'share-1',
        'metadata_json': '{"k":1}',
        'custom_meta': '{"tag":"x"}',
        'client_draft_id': 'fld_abc',
        'note_type': 'comment',
        'source_note_uuid': null,
        'cover_image_url': '',
        'md_size': 10,
        'md_last_modified': 99,
        'later_field': [1, 2],
      }))!;
      expect(sidecar.id, 7);
      expect(sidecar.mdSize, 10);
      final again = decodeSidecar(sidecar.encode())!;
      expect(again.toJson(), sidecar.toJson());
      expect(again.extra['later_field'], [1, 2]);
    });

    test('forCopy drops the shared draft and sharing ids', () {
      final original = NoteSidecar(
          id: 1, uuid: uuid, sharingId: 's', clientDraftId: 'fld_old');
      const fresh = '2c5ea4c0-4067-41fb-8f04-0c0f1e8cbe00';
      final copy = original.forCopy(id: 2, uuid: fresh);
      expect(copy.id, 2);
      expect(copy.uuid, fresh);
      expect(copy.sharingId, isNull);
      expect(copy.clientDraftId, 'fld_2c5ea4c0406741fb8f040c0f1e8cbe00');
    });

    test('a broken sidecar decodes as null', () {
      expect(decodeSidecar('{'), isNull);
      expect(decodeSidecar('[]'), isNull);
    });
  });
}
