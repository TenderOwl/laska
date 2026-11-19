/// A file produced by a generator.
class GeneratedFile {
  /// Creates a generated file.
  GeneratedFile(this.path, this.content);

  /// Path of the file, relative to the output directory.
  final String path;

  /// Content of the file.
  final String content;
}
