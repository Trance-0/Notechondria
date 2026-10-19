import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/src/local_folder/qualification.dart';

LocalFolderProbeInputs _inputs({
  bool picker = true,
  bool secure = true,
  bool permission = true,
  bool iteration = true,
  bool locks = true,
  String ua = 'Mozilla/5.0 (X11; Linux x86_64) Chrome/130.0 Safari/537.36',
  bool? uaMobile = false,
  List<(String, String)> brands = const [],
}) =>
    LocalFolderProbeInputs(
      hasDirectoryPicker: picker,
      isSecureContext: secure,
      hasPermissionApi: permission,
      hasDirectoryIteration: iteration,
      hasWebLocks: locks,
      userAgent: ua,
      uaDataMobile: uaMobile,
      brands: brands,
    );

void main() {
  test('desktop Chrome qualifies; brands are only a label', () {
    final q = evaluateLocalFolderSupport(_inputs(brands: const [
      ('Not A(Brand', '8'),
      ('Chromium', '130'),
      ('Google Chrome', '130'),
    ]));
    expect(q.qualified, isTrue);
    expect(q.message, isNull);
    expect(q.browserLabel, 'Google Chrome 130');
  });

  test('Edge, Opera, and Brave qualify on capability alone', () {
    final q = evaluateLocalFolderSupport(
        _inputs(brands: const [('Brave', '130'), ('Chromium', '130')]));
    expect(q.qualified, isTrue);
    expect(q.browserLabel, 'Brave 130');
    expect(localFolderBrowserLabel(const [('Chromium', '130')]), 'Chromium 130');
    expect(localFolderBrowserLabel(const []), isNull);
  });

  test('gaps come in the 1.2 table order and the first one is shown', () {
    final q = evaluateLocalFolderSupport(_inputs(
        picker: false,
        secure: false,
        permission: false,
        iteration: false,
        locks: false,
        uaMobile: true));
    expect(q.gaps, LocalFolderGap.values);
    expect(q.message, localFolderGapMessage(LocalFolderGap.noDirectoryPicker));
  });

  test('without userAgentData the user agent decides mobile', () {
    final android = evaluateLocalFolderSupport(_inputs(
        uaMobile: null,
        ua: 'Mozilla/5.0 (Linux; Android 14) Chrome/130.0 Mobile Safari'));
    expect(android.gaps, [LocalFolderGap.mobile]);
    final desktop = evaluateLocalFolderSupport(_inputs(uaMobile: null));
    expect(desktop.qualified, isTrue);
    final uaDataWins = evaluateLocalFolderSupport(_inputs(
        uaMobile: false, ua: 'Mozilla/5.0 (iPad) Mobile'));
    expect(uaDataWins.qualified, isTrue);
  });

  test('native builds report every API missing', () {
    final q = evaluateLocalFolderSupport(
        const LocalFolderProbeInputs.unsupported());
    expect(q.qualified, isFalse);
    expect(q.gaps.first, LocalFolderGap.noDirectoryPicker);
  });

  test('the 1.3 gap messages, verbatim', () {
    const prefix =
        'Local folder mode unavailable: Shared.LocalFolder/qualify — ';
    expect(localFolderGapMessage(LocalFolderGap.noDirectoryPicker),
        '${prefix}this browser does not provide window.showDirectoryPicker '
        '(File System Access API). Firefox and Safari do not offer it.');
    expect(localFolderGapMessage(LocalFolderGap.insecureContext),
        '${prefix}the page is not a secure context (window.isSecureContext is '
        'false). Open the app over https or from http://127.0.0.1.');
    const permission = '${prefix}this browser exposes the folder picker but '
        'not FileSystemHandle.requestPermission (or directory iteration), so a '
        'folder could not be reopened or scanned.';
    expect(localFolderGapMessage(LocalFolderGap.noPermissionApi), permission);
    expect(localFolderGapMessage(LocalFolderGap.noDirectoryIteration),
        permission);
    expect(localFolderGapMessage(LocalFolderGap.noWebLocks),
        '${prefix}navigator.locks (Web Locks API) is missing, so two tabs '
        'could corrupt the folder.');
    expect(localFolderGapMessage(LocalFolderGap.mobile),
        '${prefix}a mobile browser was detected '
        '(navigator.userAgentData.mobile, or the user agent when that is '
        'missing). Folder mode is desktop-only in this release.');
    expect(kLocalFolderFallbackLine,
        'Keep working signed out in browser-local mode and back up with the '
        'local-data export (.nchron), or use the Notechondria desktop build.');
  });
}
