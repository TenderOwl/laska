/// The paths of a package and of the files it carries.
library;

import 'dart:io';
import 'dart:isolate';

/// The directory of the package the [packageUri] points into.
///
/// The [packageUri] is a package URI, e.g.
/// `package:users_service/users_service.dart`. The runtime resolves it against
/// the package configuration of the running program, so the directory is found
/// no matter the directory the process was started from.
///
/// The value is `null` when the runtime does not know the package, e.g. when
/// the program was compiled into a single file without a package
/// configuration.
Future<String?> packageDirectory(Uri packageUri) async {
  final resolved = await Isolate.resolvePackageUri(packageUri);
  if (resolved == null) {
    return null;
  }

  // The URI of a package points into the `lib` directory of the package, so
  // the package is the directory above it.
  final file = File.fromUri(resolved);
  return file.parent.parent.path;
}

/// The directory with the files of a frontend.
///
/// The directory is the [directory] inside of the package of [packageUri], so
/// the files are found no matter the directory the process was started from.
///
/// The [configured] value overrules it: it is the path the environment of the
/// process named, e.g. the value of `LASKA_WEB_ROOT`. An absolute path is
/// taken as it is, and a relative one is read against the package of the
/// [packageUri] as well.
///
/// The value is the [directory] itself when the runtime does not know the
/// package, so the directory of the process is used then.
Future<String> frontendDirectory({
  required Uri packageUri,
  String directory = 'web',
  String? configured,
}) async {
  final package = await packageDirectory(packageUri);
  final path = configured?.trim();

  if (path == null || path.isEmpty) {
    if (package == null) {
      return directory;
    }
    return _join(package, directory);
  }

  if (package == null || _isAbsolute(path)) {
    return path;
  }
  return _join(package, path);
}

/// Whether the [path] is an absolute path.
///
/// The paths of POSIX start with a slash, and the paths of Windows start with
/// a drive letter or with the name of a share.
bool _isAbsolute(String path) {
  if (path.startsWith('/')) {
    return true;
  }
  if (Platform.isWindows) {
    if (path.length > 2 && path[1] == ':') {
      return true;
    }
    if (path.startsWith(r'\\')) {
      return true;
    }
  }
  return false;
}

/// The path of [path] inside of [directory].
String _join(String directory, String path) =>
    '$directory${Platform.pathSeparator}$path';
