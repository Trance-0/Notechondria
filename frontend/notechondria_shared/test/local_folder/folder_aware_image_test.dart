// folderAwareImageProvider and folderAwareSvg (storage_rules 3.6, T4).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/components/note_cover_image.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_controller.dart';
import 'package:notechondria_shared/src/utils/folder_aware_image.dart';

import 'backend_harness.dart';

/// A 1x1 transparent PNG.
final Uint8List kPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

const String kSvg = '<svg xmlns="http://www.w3.org/2000/svg" width="4" '
    'height="4"><rect width="4" height="4" fill="#123456"/></svg>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('folderPathForUrl', () {
    test('maps assets URLs and drops the query', () {
      expect(folderPathForUrl('nc-folder:///assets/notes/ab/cover.png?v=12'),
          'assets/notes/ab/cover.png');
      expect(folderPathForUrl('nc-folder:///assets/notes/ab/attachments/a%20b.png'),
          'assets/notes/ab/attachments/a b.png');
    });

    test('refuses paths outside assets/ and invalid segments', () {
      expect(folderPathForUrl('nc-folder:///.notechondria/index.json'), isNull);
      expect(folderPathForUrl('nc-folder:///profile/settings.json'), isNull);
      expect(folderPathForUrl('nc-folder:///assets/../manifest.json'), isNull);
      expect(folderPathForUrl('https://example.com/a.png'), isNull);
    });
  });

  test('non-folder URLs get a NetworkImage', () {
    final p = folderAwareImageProvider('https://example.com/a.png');
    expect(p, isA<NetworkImage>());
    expect(folderAwareImageProvider('nc-folder:///assets/avatar.png'),
        isA<FolderImage>());
  });

  test('a folder URL reads its bytes through the controller', () async {
    final (c, fs) = await folderApp();
    await fs.writeBytes('assets/notes/ab/cover.png', kPng);
    expect(await readFolderUrlBytes('nc-folder:///assets/notes/ab/cover.png', c),
        kPng);
    await expectLater(
        readFolderUrlBytes('nc-folder:///assets/missing.png', c),
        throwsA(isA<FolderImageException>().having((e) => e.message, 'message',
            startsWith('Image not shown: Shared.LocalFolder/read — '))));
    await expectLater(
        readFolderUrlBytes('nc-folder:///assets/notes/ab/cover.png', null),
        throwsA(isA<FolderImageException>()));
  });

  testWidgets('Image with a folder provider decodes the folder bytes',
      (tester) async {
    late (LocalFolderController, MemoryFolderFs) app;
    await tester.runAsync(() async {
      app = await folderApp();
      await app.$2.writeBytes('assets/avatar.png', kPng);
    });
    final provider =
        folderAwareImageProvider('nc-folder:///assets/avatar.png', folder: app.$1);
    ImageInfo? info;
    Object? error;
    await tester.runAsync(() async {
      final stream = provider.resolve(ImageConfiguration.empty);
      final done = Completer<void>();
      stream.addListener(ImageStreamListener((i, _) {
        info = i;
        done.complete();
      }, onError: (e, _) {
        error = e;
        done.complete();
      }));
      await done.future.timeout(const Duration(seconds: 5));
    });
    expect(error, isNull);
    expect(info!.image.width, 1);
  });

  testWidgets('NoteCoverImage shows an nc-folder: cover from the folder (202-N15)',
      (tester) async {
    late (LocalFolderController, MemoryFolderFs) app;
    await tester.runAsync(() async {
      app = await folderApp();
      await app.$2.writeBytes('assets/notes/ab/cover.png', kPng);
    });
    Widget cover(String url) => MaterialApp(
          home: SizedBox(
            width: 320,
            child: NoteCoverImage(
                seed: 'n1',
                imageUrl: url,
                caption: 'Cover fallback',
                showCaption: true,
                folder: app.$1),
          ),
        );
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
    }

    await tester.pumpWidget(cover('nc-folder:///assets/notes/ab/cover.png?v=1'));
    await settle();
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<FolderImage>());
    expect(find.text('Cover fallback'), findsNothing, reason: 'the folder bytes decoded');

    await tester.pumpWidget(cover('nc-folder:///assets/notes/ab/missing.png'));
    await settle();
    expect(find.text('Cover fallback'), findsOneWidget, reason: 'a missing file shows the barcode');
  });

  testWidgets('folderAwareSvg renders SvgPicture.memory for folder URLs',
      (tester) async {
    late (LocalFolderController, MemoryFolderFs) app;
    await tester.runAsync(() async {
      app = await folderApp();
      await app.$2.writeText('assets/notes/ab/cover.svg', kSvg);
    });
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: folderAwareSvg('nc-folder:///assets/notes/ab/cover.svg',
          folder: app.$1,
          fit: BoxFit.cover,
          placeholderBuilder: (_) => const Text('placeholder')),
    ));
    expect(find.text('placeholder'), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('folderAwareSvg falls back to the placeholder on a read error',
      (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: folderAwareSvg('nc-folder:///assets/none.svg',
          placeholderBuilder: (_) => const Text('placeholder')),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('placeholder'), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('folderAwareSvg uses SvgPicture.network for other URLs',
      (tester) async {
    final w = folderAwareSvg('https://example.com/a.svg', fit: BoxFit.cover);
    expect(w, isA<SvgPicture>());
    expect((w as SvgPicture).fit, BoxFit.cover);
  });
}
