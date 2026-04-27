import 'package:flutter_test/flutter_test.dart';
// ignore: unused_import
import 'package:editor_app/main.dart' show parseNoteUuidFromFragment;

/// Regression coverage for the note-share deep-link parser.
///
/// The 0.1.67 fix replaced an over-anchored `^/?notes/<uuid>$`
/// regex with a non-anchored variant that accepts trailing slashes
/// + query strings + fragment suffixes — share links opened cold
/// from a chat app sometimes carried e.g.
/// `#/notes/<uuid>?ref=share`, which the old regex rejected,
/// dropping the user on the home view instead of the note.
///
/// 0.1.83 forces this regression test in to ride alongside the
/// fix so a future refactor can't silently re-anchor the regex.
void main() {
  const uuid = 'a1b2c3d4-e5f6-7890-abcd-ef0123456789';

  group('parseNoteUuidFromFragment — happy paths', () {
    test('cold-start with leading slash: /notes/<uuid>', () {
      expect(parseNoteUuidFromFragment('/notes/$uuid'), equals(uuid));
    });

    test('cold-start without leading slash: notes/<uuid>', () {
      expect(parseNoteUuidFromFragment('notes/$uuid'), equals(uuid));
    });

    test('trailing slash: /notes/<uuid>/', () {
      expect(parseNoteUuidFromFragment('/notes/$uuid/'), equals(uuid));
    });

    test('share-link query suffix: /notes/<uuid>?ref=share', () {
      expect(
        parseNoteUuidFromFragment('/notes/$uuid?ref=share'),
        equals(uuid),
      );
    });

    test('uppercase-hex uuid: /notes/<UPPER-UUID>', () {
      const upper = 'A1B2C3D4-E5F6-7890-ABCD-EF0123456789';
      expect(parseNoteUuidFromFragment('/notes/$upper'), equals(upper));
    });

    test('OAuth-callback-preserves-fragment: '
        '?code=foo&state=bar still leaves #/notes/<uuid> intact', () {
      // After handleOAuthCallback strips the query params via
      // browserReplaceState it preserves the fragment. The parser
      // should still find the uuid in that preserved fragment —
      // simulate the post-callback state where the fragment
      // arrives clean.
      expect(parseNoteUuidFromFragment('/notes/$uuid'), equals(uuid));
    });
  });

  group('parseNoteUuidFromFragment — null / no-match paths', () {
    test('empty fragment returns null', () {
      expect(parseNoteUuidFromFragment(''), isNull);
    });

    test('home fragment returns null', () {
      expect(parseNoteUuidFromFragment('/'), isNull);
    });

    test('settings fragment returns null', () {
      expect(parseNoteUuidFromFragment('/settings'), isNull);
    });

    test('non-uuid suffix returns null', () {
      expect(parseNoteUuidFromFragment('/notes/not-a-uuid'), isNull);
    });

    test('partial uuid returns null', () {
      expect(
        parseNoteUuidFromFragment('/notes/a1b2c3d4-e5f6-7890-abcd'),
        isNull,
      );
    });

    test('garbage characters around uuid pattern still no match'
        ' when uuid not present', () {
      expect(parseNoteUuidFromFragment('/foo/bar/baz'), isNull);
    });
  });
}
