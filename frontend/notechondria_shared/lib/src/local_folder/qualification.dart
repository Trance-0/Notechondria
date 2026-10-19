// Capability probe and gap messages for the sign-in option (main 1.2, 1.3).
// Qualification is feature detection; brands are only a label.

enum LocalFolderGap {
  noDirectoryPicker,
  insecureContext,
  noPermissionApi,
  noDirectoryIteration,
  noWebLocks,
  mobile,
}

/// Raw browser facts, read by `qualification_web.dart` with no prompt and no
/// user gesture. Kept separate so the rules below run in VM tests.
class LocalFolderProbeInputs {
  const LocalFolderProbeInputs({
    required this.hasDirectoryPicker,
    required this.isSecureContext,
    required this.hasPermissionApi,
    required this.hasDirectoryIteration,
    required this.hasWebLocks,
    required this.userAgent,
    this.uaDataMobile,
    this.brands = const [],
  });

  /// What a native build reports: nothing is available.
  const LocalFolderProbeInputs.unsupported()
      : hasDirectoryPicker = false,
        isSecureContext = false,
        hasPermissionApi = false,
        hasDirectoryIteration = false,
        hasWebLocks = false,
        userAgent = '',
        uaDataMobile = null,
        brands = const [];

  final bool hasDirectoryPicker;
  final bool isSecureContext;

  /// `queryPermission` and `requestPermission` on `FileSystemHandle`.
  final bool hasPermissionApi;

  /// `values` or `entries` on `FileSystemDirectoryHandle`.
  final bool hasDirectoryIteration;
  final bool hasWebLocks;
  final String userAgent;

  /// `navigator.userAgentData.mobile`; null when `userAgentData` is absent.
  final bool? uaDataMobile;

  /// `navigator.userAgentData.brands` as (brand, version).
  final List<(String, String)> brands;
}

class LocalFolderQualification {
  const LocalFolderQualification({required this.gaps, this.browserLabel});

  /// Ordered as in the 1.2 table; the first one is shown.
  final List<LocalFolderGap> gaps;

  /// For example "Google Chrome 130"; logs and the status card only.
  final String? browserLabel;

  bool get qualified => gaps.isEmpty;

  /// The 1.3 message for the first gap, or null when qualified.
  String? get message =>
      gaps.isEmpty ? null : localFolderGapMessage(gaps.first);
}

final RegExp _mobileUa = RegExp(r'iphone|ipad|ipod|android|mobile');

LocalFolderQualification evaluateLocalFolderSupport(
    LocalFolderProbeInputs inputs) {
  final mobile = inputs.uaDataMobile ??
      _mobileUa.hasMatch(inputs.userAgent.toLowerCase());
  return LocalFolderQualification(
    gaps: [
      if (!inputs.hasDirectoryPicker) LocalFolderGap.noDirectoryPicker,
      if (!inputs.isSecureContext) LocalFolderGap.insecureContext,
      if (!inputs.hasPermissionApi) LocalFolderGap.noPermissionApi,
      if (!inputs.hasDirectoryIteration) LocalFolderGap.noDirectoryIteration,
      if (!inputs.hasWebLocks) LocalFolderGap.noWebLocks,
      if (mobile) LocalFolderGap.mobile,
    ],
    browserLabel: localFolderBrowserLabel(inputs.brands),
  );
}

final RegExp _greaseBrand = RegExp(r'not.?a.?brand', caseSensitive: false);

/// The most specific brand: GREASE entries ("Not A(Brand") are skipped and
/// "Chromium" is used only when nothing else is listed.
String? localFolderBrowserLabel(List<(String, String)> brands) {
  final real = brands.where((b) => !_greaseBrand.hasMatch(b.$1)).toList();
  if (real.isEmpty) return null;
  final pick = real.firstWhere((b) => b.$1 != 'Chromium',
      orElse: () => real.first);
  return '${pick.$1} ${pick.$2}';
}

const String _prefix =
    'Local folder mode unavailable: Shared.LocalFolder/qualify — ';

String localFolderGapMessage(LocalFolderGap gap) => switch (gap) {
      LocalFolderGap.noDirectoryPicker => '${_prefix}this browser does not '
          'provide window.showDirectoryPicker (File System Access API). '
          'Firefox and Safari do not offer it.',
      LocalFolderGap.insecureContext => '${_prefix}the page is not a secure '
          'context (window.isSecureContext is false). Open the app over '
          'https or from http://127.0.0.1.',
      LocalFolderGap.noPermissionApi ||
      LocalFolderGap.noDirectoryIteration =>
        '${_prefix}this browser exposes the folder picker but not '
            'FileSystemHandle.requestPermission (or directory iteration), so '
            'a folder could not be reopened or scanned.',
      LocalFolderGap.noWebLocks => '${_prefix}navigator.locks (Web Locks API) '
          'is missing, so two tabs could corrupt the folder.',
      LocalFolderGap.mobile => '${_prefix}a mobile browser was detected '
          '(navigator.userAgentData.mobile, or the user agent when that is '
          'missing). Folder mode is desktop-only in this release.',
    };

/// Shown under every gap message (1.3).
const String kLocalFolderFallbackLine =
    'Keep working signed out in browser-local mode and back up with the '
    'local-data export (.nchron), or use the Notechondria desktop build.';
