import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import 'generator/dart_generator.dart';
import 'generator/openapi_generator.dart';
import 'model.dart';
import 'naming.dart';
import 'parser.dart';
import 'types.dart';

/// A `.proto` source with the path it was read from.
class ProtoSource {
  /// Creates a source.
  ProtoSource(this.path, this.content);

  /// Path of the file, relative to the contract root.
  final String path;

  /// Content of the file.
  final String content;
}

/// Raised when a contract cannot be compiled.
class ContractCompileException implements Exception {
  /// Creates an exception with the list of [problems].
  ContractCompileException(this.problems);

  /// The problems that were found.
  final List<String> problems;

  @override
  String toString() =>
      'Contract compilation failed:\n${problems.map((p) => '  - $p').join('\n')}';
}

/// The result of compiling a contract.
class CompileResult {
  /// Creates a compile result.
  CompileResult({
    required this.contract,
    required this.files,
    required this.warnings,
    required this.openapi,
  });

  /// The parsed contract.
  final Contract contract;

  /// The generated Dart files.
  final List<GeneratedFile> files;

  /// Non fatal problems found while compiling.
  final List<String> warnings;

  /// The OpenAPI 3.1 document of the contract.
  final Map<String, dynamic> openapi;
}

/// Compiles contracts into Dart code and an OpenAPI document.
class ContractCompiler {
  /// Creates a compiler.
  ///
  /// The [languageVersion] is the version of the language the generated code
  /// is written for. It decides the style of the formatter, and the style has
  /// to be the one of the package the code goes into: `dart format` picks the
  /// style by the version of the SDK the package declares.
  ContractCompiler({
    this.title = 'Laska API',
    this.version = '0.1.0',
    this.languageVersion,
  });

  /// Title of the generated OpenAPI document.
  final String title;

  /// Version of the generated OpenAPI document.
  final String version;

  /// The version of the language the generated code is written for.
  final Version? languageVersion;

  /// Compiles [sources] into generated files.
  ///
  /// Throws [ContractCompileException] when the contract is inconsistent.
  CompileResult compile(List<ProtoSource> sources) {
    final parsed = <ProtoFile>[];
    for (final source in sources) {
      parsed.add(ProtoParser(source.content, fileName: source.path).parse());
    }

    final contract = Contract(parsed);
    final problems = validate(contract);
    if (problems.isNotEmpty) {
      throw ContractCompileException(problems);
    }

    final generated = DartGenerator(
      contract,
      languageVersion: languageVersion,
    ).generate();
    final openapi = OpenApiGenerator(
      contract,
      title: title,
      version: version,
    ).generate();

    return CompileResult(
      contract: contract,
      files: generated,
      warnings: warnings(contract),
      openapi: openapi,
    );
  }

  /// Checks the contract for inconsistencies.
  List<String> validate(Contract contract) {
    final problems = <String>[];
    final resolver = TypeResolver(contract);

    final messageNames = <String, String>{};
    for (final message in contract.messages) {
      final previous = messageNames[message.dartName];
      if (previous != null) {
        problems.add(
          'Message "${message.fullName}" is generated into the class '
          '"${message.dartName}", which "$previous" already uses; Dart class '
          'names must be unique.',
        );
      } else {
        messageNames[message.dartName] = message.fullName;
      }
    }

    final enumNames = <String, String>{};
    for (final enumType in contract.enums) {
      final previous = enumNames[enumType.dartName];
      if (previous != null) {
        problems.add(
          'Enum "${enumType.fullName}" is generated into the enum '
          '"${enumType.dartName}", which "$previous" already uses; Dart type '
          'names must be unique.',
        );
      } else {
        enumNames[enumType.dartName] = enumType.fullName;
      }
    }

    for (final message in contract.messages) {
      for (final group in message.oneofs) {
        final name = pascalCase('${message.dartName}.${group.name}');
        final owner = messageNames[name] ?? enumNames[name];
        if (owner != null) {
          problems.add(
            'The group "${group.name}" of "${message.fullName}" is generated '
            'into the class "$name", which "$owner" already uses; Dart type '
            'names must be unique.',
          );
        } else {
          messageNames[name] = '${message.fullName}.${group.name}';
        }
      }
    }

    for (final message in contract.messages) {
      final numbers = <int, String>{};
      for (final field in message.allFields) {
        final previous = numbers[field.number];
        if (previous != null) {
          problems.add(
            'Field number ${field.number} of "${message.fullName}" is used '
            'by both "$previous" and "${field.name}".',
          );
        } else {
          numbers[field.number] = field.name;
        }

        if (field.isMap) {
          if (!mapKeyTypes.containsKey(field.mapKeyType)) {
            problems.add(
              'Field "${message.fullName}.${field.name}" has a key of the type '
              '"${field.mapKeyType}"; a key of a map is a string, a boolean or '
              'an integer.',
            );
          }
          final value = field.mapValueType ?? '';
          if (!scalarTypes.containsKey(value) &&
              resolver.findMessage(value) == null &&
              resolver.findEnum(value) == null) {
            problems.add(
              'Field "${message.fullName}.${field.name}" has a value of the '
              'unknown type "$value".',
            );
          }
          continue;
        }

        if (scalarTypes.containsKey(field.type)) {
          continue;
        }
        if (resolver.findMessage(field.type) != null ||
            resolver.findEnum(field.type) != null) {
          continue;
        }
        problems.add(
          'Field "${message.fullName}.${field.name}" has an unknown type '
          '"${field.type}".',
        );
      }
    }

    for (final service in contract.services) {
      for (final method in service.methods) {
        final request = resolver.findMessage(method.requestType);
        if (request == null) {
          problems.add(
            'Method "${service.fullName}.${method.name}" has an unknown '
            'request type "${method.requestType}".',
          );
        }
        if (resolver.findMessage(method.responseType) == null &&
            resolver.findEnum(method.responseType) == null) {
          problems.add(
            'Method "${service.fullName}.${method.name}" has an unknown '
            'response type "${method.responseType}".',
          );
        }

        for (final rule in method.httpRules) {
          if (request == null) {
            continue;
          }
          for (final parameter in rule.pathParameters) {
            if (request.field(parameter) == null) {
              problems.add(
                'Path parameter "{$parameter}" of '
                '"${service.fullName}.${method.name}" is not a field of '
                '"${request.fullName}".',
              );
            }
          }
          if (rule.body != null &&
              rule.body != '*' &&
              request.field(rule.body!) == null) {
            problems.add(
              'Body "${rule.body}" of "${service.fullName}.${method.name}" '
              'is not a field of "${request.fullName}".',
            );
          }
        }
      }
    }

    return problems;
  }

  /// Collects non fatal observations about the contract.
  List<String> warnings(Contract contract) {
    final result = <String>[];
    for (final file in contract.files) {
      for (final import in file.imports) {
        result.add(
          'Import "$import" of "${file.path}" is recorded but not resolved; '
          'only the types declared in the compiled files are available.',
        );
      }
      for (final service in file.services) {
        for (final method in service.methods) {
          if (method.httpRules.isEmpty) {
            result.add(
              'Method "${service.fullName}.${method.name}" has no '
              'google.api.http binding and is therefore not exposed over HTTP.',
            );
          }
        }
      }
    }
    return result;
  }
}

/// Reads every `.proto` file below [directory].
///
/// The path of a source is relative to [root], which defaults to [directory].
Future<List<ProtoSource>> readProtoDirectory(
  String directory, {
  String? root,
}) async {
  final base = root ?? directory;
  final sources = <ProtoSource>[];
  final directory_ = Directory(directory);
  if (!directory_.existsSync()) {
    return sources;
  }

  final files = directory_
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.proto'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final relative = file.path
        .substring(base.length)
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    sources.add(ProtoSource(relative, file.readAsStringSync()));
  }
  return sources;
}

/// Writes the generated files of [result] into [outputDirectory].
///
/// Returns the paths of the written files.
Future<List<String>> writeGeneratedFiles(
  CompileResult result,
  String outputDirectory,
) async {
  final written = <String>[];
  final root = Directory(outputDirectory);

  for (final file in result.files) {
    final target = File('${root.path}/${file.path}');
    await target.parent.create(recursive: true);
    await target.writeAsString(file.content);
    written.add(target.path);
  }

  final openapiFile = File('${root.path}/openapi.json');
  await openapiFile.parent.create(recursive: true);
  await openapiFile.writeAsString(
    JsonEncoder.withIndent('  ').convert(result.openapi),
  );
  written.add(openapiFile.path);

  return written;
}
