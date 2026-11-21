/// The version of the command line interface, and of the framework it writes
/// the projects with.
///
/// The packages of the framework move in lockstep, so the version of the
/// command is the version of the framework. The value is the version of the
/// pubspec of the package: the gate of the repository checks that the two
/// agree, so the constant cannot drift away from the release it belongs to.
///
/// The version is a constant and not a value read at runtime, because the
/// command runs in ways where the pubspec of the package is not to be found:
/// the bundle of the release, for instance, carries the code and not the
/// pubspec.
const String laskaVersion = '0.3.0';
