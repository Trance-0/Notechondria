import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'js_bindings_web.dart';
import 'qualification.dart';

/// Reads the main 1.2 probe inputs through `dart:js_interop`. No call here
/// prompts or needs a user gesture; any failure counts as "missing".
LocalFolderProbeInputs readLocalFolderProbeInputs() {
  bool safe(bool Function() check) {
    try {
      return check();
    } catch (_) {
      return false;
    }
  }

  bool? mobile;
  var brands = const <(String, String)>[];
  var userAgent = '';
  try {
    userAgent = web.window.navigator.userAgent;
  } catch (_) {
    userAgent = '';
  }
  try {
    final data = web.window.navigator.userAgentData;
    if (data != null) {
      mobile = data.mobile;
      brands = [for (final b in data.brands.toDart) (b.brand, b.version)];
    }
  } catch (_) {
    mobile = null;
  }
  return LocalFolderProbeInputs(
    hasDirectoryPicker: safe(() => hasShowDirectoryPicker),
    isSecureContext: safe(() => web.window.isSecureContext),
    hasPermissionApi: safe(() =>
        prototypeHas('FileSystemHandle', 'queryPermission') &&
        prototypeHas('FileSystemHandle', 'requestPermission')),
    hasDirectoryIteration: safe(() =>
        prototypeHas('FileSystemDirectoryHandle', 'values') ||
        prototypeHas('FileSystemDirectoryHandle', 'entries')),
    hasWebLocks: safe(() => hasWebLocks),
    userAgent: userAgent,
    uaDataMobile: mobile,
    brands: brands,
  );
}
