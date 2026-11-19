import 'dart:convert';

import '../model.dart';
import '../naming.dart';
import '../types.dart';

/// Generates an OpenAPI 3.1 document out of a [Contract].
///
/// The document is derived from the same contract the Dart code is generated
/// from, so the documentation cannot drift away from the implementation.
class OpenApiGenerator {
  /// Creates a generator for [contract].
  OpenApiGenerator(
    this.contract, {
    this.title = 'Laska API',
    this.version = '0.1.0',
  });

  /// The contract to describe.
  final Contract contract;

  /// Title of the document.
  final String title;

  /// Version of the document.
  final String version;

  late final TypeResolver _types = TypeResolver(contract);

  /// Builds the OpenAPI document.
  Map<String, dynamic> generate() {
    final paths = <String, dynamic>{};
    for (final service in contract.services) {
      for (final method in service.methods) {
        for (final rule in method.httpRules) {
          _addOperation(paths, service, method, rule);
        }
      }
    }

    return <String, dynamic>{
      'openapi': '3.1.0',
      'info': <String, dynamic>{'title': title, 'version': version},
      'paths': paths,
      'components': <String, dynamic>{'schemas': _schemas()},
    };
  }

  /// Builds the document and encodes it as JSON.
  String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert(generate());

  void _addOperation(
    Map<String, dynamic> paths,
    Service service,
    Method method,
    HttpRule rule,
  ) {
    final path = paths.putIfAbsent(rule.path, () => <String, dynamic>{});
    final operation = <String, dynamic>{
      'operationId': '${service.name}.${method.name}',
      'tags': <String>[service.name],
      if (method.comment != null) 'summary': _summary(method.comment!),
      if (method.comment != null) 'description': method.comment,
      'responses': <String, dynamic>{
        '200': <String, dynamic>{
          'description': 'Successful response',
          'content': <String, dynamic>{
            'application/json': <String, dynamic>{
              'schema': _schemaOfType(method.responseType),
            },
          },
        },
        'default': <String, dynamic>{
          'description': 'Error response',
          'content': <String, dynamic>{
            'application/problem+json': <String, dynamic>{
              'schema': <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{
                  'type': <String, dynamic>{'type': 'string'},
                  'title': <String, dynamic>{'type': 'string'},
                  'status': <String, dynamic>{'type': 'integer'},
                  'detail': <String, dynamic>{'type': 'string'},
                },
                'required': <String>['type', 'title', 'status', 'detail'],
              },
            },
          },
        },
      },
    };

    final parameters = <Map<String, dynamic>>[];
    final requestMessage = _types.findMessage(method.requestType);
    final bodyFields = <Field>[];

    for (final parameter in rule.pathParameters) {
      final field =
          requestMessage?.fields.where((f) => f.name == parameter).firstOrNull;
      parameters.add(<String, dynamic>{
        'name': parameter,
        'in': 'path',
        'required': true,
        'schema': field == null
            ? <String, dynamic>{'type': 'string'}
            : _schemaOfField(field),
      });
    }

    if (requestMessage != null) {
      for (final field in requestMessage.fields) {
        if (rule.pathParameters.contains(field.name)) {
          continue;
        }
        if (rule.body == '*' || rule.body == field.name) {
          bodyFields.add(field);
          continue;
        }
        final type = _types.resolve(field);
        if (type.isMessage || type.isEnum) {
          continue;
        }
        parameters.add(<String, dynamic>{
          'name': camelCase(field.name),
          'in': 'query',
          'required': !field.optional,
          'schema': _schemaOfField(field),
        });
      }
    }

    if (parameters.isNotEmpty) {
      operation['parameters'] = parameters;
    }

    if (rule.body != null && rule.method != 'GET' && rule.method != 'DELETE') {
      final schema = rule.body == '*'
          ? _schemaOfType(method.requestType)
          : _schemaOfField(bodyFields.firstWhere(
              (field) => field.name == rule.body,
              orElse: () => bodyFields.first,
            ));
      operation['requestBody'] = <String, dynamic>{
        'required': true,
        'content': <String, dynamic>{
          'application/json': <String, dynamic>{'schema': schema},
        },
      };
    }

    path[rule.method.toLowerCase()] = operation;
  }

  Map<String, dynamic> _schemas() {
    final schemas = <String, dynamic>{};
    for (final message in contract.messages) {
      schemas[message.dartName] = _schemaOfMessage(message);
    }
    for (final enumType in contract.enums) {
      schemas[enumType.dartName] = <String, dynamic>{
        'type': 'string',
        'enum': enumType.values.map((value) => value.name).toList(),
      };
    }
    return schemas;
  }

  Map<String, dynamic> _schemaOfMessage(Message message) {
    final properties = <String, dynamic>{};
    final required = <String>[];

    for (final field in message.fields) {
      properties[camelCase(field.name)] = _schemaOfField(field);
      if (!field.optional && !field.repeated && !field.isMap) {
        required.add(camelCase(field.name));
      }
    }

    // The members of a group of a `oneof` are written under their own name,
    // the way protobuf writes them, and exactly one of them is set.
    final oneOf = <Map<String, dynamic>>[];
    for (final group in message.oneofs) {
      for (final member in group.fields) {
        properties[camelCase(member.name)] = _schemaOfField(member);
      }
      oneOf.add(<String, dynamic>{
        'required':
            group.fields.map((member) => camelCase(member.name)).toList(),
      });
    }

    return <String, dynamic>{
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
      if (oneOf.isNotEmpty) 'oneOf': oneOf,
      'additionalProperties': false,
    };
  }

  Map<String, dynamic> _schemaOfField(Field field) {
    final type = _types.resolve(field);

    if (type.isMap) {
      return <String, dynamic>{
        'type': 'object',
        'additionalProperties': _schemaOfType(type.mapValue!.protoType),
      };
    }

    if (type.isMessage) {
      return <String, dynamic>{
        r'$ref': '#/components/schemas/${type.messageName}',
      };
    }
    if (type.isEnum) {
      return <String, dynamic>{
        'type': 'string',
        r'$ref': '#/components/schemas/${type.enumName}',
      };
    }
    final scalar = _scalarSchema(type.dartType);
    if (field.repeated) {
      return <String, dynamic>{'type': 'array', 'items': scalar};
    }
    return scalar;
  }

  Map<String, dynamic> _schemaOfType(String reference) {
    final scalar = scalarTypes[reference];
    if (scalar != null) {
      return _scalarSchema(scalar);
    }
    final message = _types.findMessage(reference);
    if (message != null) {
      return <String, dynamic>{
        r'$ref': '#/components/schemas/${message.dartName}',
      };
    }
    final enumType = _types.findEnum(reference);
    if (enumType != null) {
      return <String, dynamic>{
        'type': 'string',
        r'$ref': '#/components/schemas/${enumType.dartName}',
      };
    }
    return <String, dynamic>{'type': 'string'};
  }

  Map<String, dynamic> _scalarSchema(String dartType) {
    switch (dartType) {
      case 'int':
        return <String, dynamic>{'type': 'integer', 'format': 'int64'};
      case 'double':
        return <String, dynamic>{'type': 'number', 'format': 'double'};
      case 'bool':
        return <String, dynamic>{'type': 'boolean'};
      default:
        return <String, dynamic>{'type': 'string'};
    }
  }

  String _summary(String comment) => comment.split('\n').first.trim();
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
