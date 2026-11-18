/// The versions of the packages and of the contracts.
///
/// Laska follows the semantic versioning: the version tells the consumer of a
/// package whether an update breaks his code or not. The version of a
/// contract follows the same rules, but it is written in the name of the
/// package of the `.proto` file, e.g. `users.v1`.
library;

import 'model.dart';

/// The version of the API of the [contract], or `null` when the contract
/// holds no versioned package.
ApiVersion? apiVersionOf(Contract contract) {
  for (final file in contract.files) {
    final version = ApiVersion.of(file.package);
    if (version != null) {
      return version;
    }
  }
  return null;
}

/// A version of a package or of a contract.
///
/// The version is `major.minor.patch`, with an optional pre-release and an
/// optional build number, as the semantic versioning defines it.
class Version implements Comparable<Version> {
  /// Creates a version.
  const Version({
    required this.major,
    required this.minor,
    required this.patch,
    this.preRelease = '',
    this.build = '',
  });

  /// Reads the version out of [text].
  ///
  /// Throws a [FormatException] when the text is not a version.
  factory Version.parse(String text) {
    final version = Version.tryParse(text);
    if (version == null) {
      throw FormatException('"$text" is not a version', text);
    }
    return version;
  }

  /// Reads the version out of [text], or returns `null` when the text is not a
  /// version.
  static Version? tryParse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    var rest = trimmed;
    String build = '';
    final plus = rest.indexOf('+');
    if (plus != -1) {
      build = rest.substring(plus + 1);
      rest = rest.substring(0, plus);
    }

    String preRelease = '';
    final dash = rest.indexOf('-');
    if (dash != -1) {
      preRelease = rest.substring(dash + 1);
      rest = rest.substring(0, dash);
    }

    final parts = rest.split('.');
    if (parts.length != 3) {
      return null;
    }

    final numbers = <int>[];
    for (final part in parts) {
      final number = int.tryParse(part);
      if (number == null || number < 0) {
        return null;
      }
      numbers.add(number);
    }

    if (preRelease.isNotEmpty && !_isValidPreRelease(preRelease)) {
      return null;
    }

    return Version(
      major: numbers[0],
      minor: numbers[1],
      patch: numbers[2],
      preRelease: preRelease,
      build: build,
    );
  }

  /// The major version.
  ///
  /// The major version goes up when the change breaks the consumers.
  final int major;

  /// The minor version.
  ///
  /// The minor version goes up when the change adds something and breaks
  /// nobody.
  final int minor;

  /// The patch version.
  ///
  /// The patch version goes up when the change fixes something.
  final int patch;

  /// The pre-release part, e.g. `rc.1`. Empty when the version is final.
  final String preRelease;

  /// The build part. It never takes part in the comparison.
  final String build;

  /// Whether the version is a pre-release.
  bool get isPreRelease => preRelease.isNotEmpty;

  /// The version in the text form.
  String get text => <String>[
        '$major.$minor.$patch',
        if (isPreRelease) preRelease,
        if (build.isNotEmpty) build,
      ].join('-');

  /// The version with the major part one higher.
  Version get nextMajor => Version(
        major: major + 1,
        minor: 0,
        patch: 0,
      );

  /// The version with the minor part one higher.
  Version get nextMinor => Version(
        major: major,
        minor: minor + 1,
        patch: 0,
      );

  /// The version with the patch part one higher.
  Version get nextPatch => Version(
        major: major,
        minor: minor,
        patch: patch + 1,
      );

  @override
  int compareTo(Version other) {
    if (major != other.major) {
      return major.compareTo(other.major);
    }
    if (minor != other.minor) {
      return minor.compareTo(other.minor);
    }
    if (patch != other.patch) {
      return patch.compareTo(other.patch);
    }

    // A pre-release is lower than the version it leads to.
    if (isPreRelease != other.isPreRelease) {
      return isPreRelease ? -1 : 1;
    }
    if (!isPreRelease) {
      return 0;
    }

    return _comparePreRelease(preRelease, other.preRelease);
  }

  /// Whether the version is at least [other].
  bool isAtLeast(Version other) => compareTo(other) >= 0;

  /// Whether the version is lower than [other].
  bool isLowerThan(Version other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) => other is Version && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  @override
  String toString() => text;

  static bool _isValidPreRelease(String preRelease) {
    for (final part in preRelease.split('.')) {
      if (part.isEmpty) {
        return false;
      }
      if (int.tryParse(part) != null) {
        continue;
      }
      for (final code in part.codeUnits) {
        final isLetter =
            (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);
        final isDigit = code >= 0x30 && code <= 0x39;
        if (!isLetter && !isDigit && code != 0x2d) {
          return false;
        }
      }
    }
    return true;
  }

  /// Compares two pre-release parts.
  static int _comparePreRelease(String left, String right) {
    final leftParts = left.split('.');
    final rightParts = right.split('.');

    for (var index = 0; index < leftParts.length; index++) {
      if (index >= rightParts.length) {
        return 1;
      }

      final leftPart = leftParts[index];
      final rightPart = rightParts[index];
      final leftNumber = int.tryParse(leftPart);
      final rightNumber = int.tryParse(rightPart);

      if (leftNumber != null && rightNumber != null) {
        final comparison = leftNumber.compareTo(rightNumber);
        if (comparison != 0) {
          return comparison;
        }
        continue;
      }

      if (leftNumber != null) {
        return -1;
      }
      if (rightNumber != null) {
        return 1;
      }

      final comparison = leftPart.compareTo(rightPart);
      if (comparison != 0) {
        return comparison;
      }
    }

    if (leftParts.length < rightParts.length) {
      return -1;
    }
    return 0;
  }
}

/// The version of the API of a contract.
///
/// The version of an API lives in the name of the package of the `.proto`
/// file, e.g. `users.v1`. The major part goes up when the change breaks the
/// consumers of the API; the minor part goes up when the change adds
/// something.
class ApiVersion {
  /// Creates the version [major] of the API [name].
  const ApiVersion({required this.name, required this.major});

  /// Reads the version out of the package [packageName], e.g. `users.v1`.
  ///
  /// Returns `null` when the package holds no version.
  static ApiVersion? of(String packageName) {
    final separator = packageName.lastIndexOf('.');
    if (separator == -1) {
      return null;
    }

    final name = packageName.substring(0, separator);
    final label = packageName.substring(separator + 1);
    if (name.isEmpty || !label.startsWith('v')) {
      return null;
    }

    final major = int.tryParse(label.substring(1));
    if (major == null) {
      return null;
    }

    return ApiVersion(name: name, major: major);
  }

  /// The name of the API, e.g. `users`.
  final String name;

  /// The major part of the version of the API.
  final int major;

  /// The label of the version, e.g. `v1`.
  String get label => 'v$major';

  /// The package of the contract, e.g. `users.v1`.
  String get package => '$name.$label';

  /// The version with the major part one higher.
  ApiVersion get nextMajor => ApiVersion(name: name, major: major + 1);

  @override
  bool operator ==(Object other) =>
      other is ApiVersion && other.name == name && other.major == major;

  @override
  int get hashCode => Object.hash(name, major);

  @override
  String toString() => package;
}
