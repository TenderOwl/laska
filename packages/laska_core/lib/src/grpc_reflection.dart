/// The reflection of a gRPC server.
///
/// The reflection service tells a tool what a running server serves: the names
/// of its services and the files of the contracts they come from. `grpcurl`
/// reads it, so a service of a contract is described and called without the
/// files of the contract on the machine of the reader.
///
/// The service is the one of the protocol of gRPC, in the version 1 and in the
/// version 1alpha: the tools of the ecosystem speak one of them, and both are
/// the same protocol with a different name.
library;

import 'dart:async';
import 'dart:convert';

import 'package:grpc/grpc.dart' as grpc;

import 'grpc.dart';
import 'protobuf.dart';

/// The name of the service of the reflection, the version 1.
const String reflectionServiceV1 = 'grpc.reflection.v1.ServerReflection';

/// The name of the service of the reflection, the version 1alpha.
const String reflectionServiceV1Alpha =
    'grpc.reflection.v1alpha.ServerReflection';

/// The name of the method of the reflection.
const String reflectionMethod = 'ServerReflectionInfo';

/// The bytes of the descriptor [encoded].
///
/// The descriptor travels with the generated code of a contract as a string of
/// the base64, so the file of the contract does not have to be read at the
/// start of a server.
List<int> descriptorBytes(String encoded) => base64Decode(encoded);

/// The index of the contracts of the services of a server.
///
/// The index holds the names of the services and the files of their contracts,
/// so the reflection service can answer the questions of a tool: which
/// services are there, and which file declares a symbol of them.
class GrpcReflectionIndex {
  /// Creates the index of the [services].
  GrpcReflectionIndex(List<GrpcService> services) {
    for (final service in services) {
      _services.add(service.name);

      final descriptor = service.descriptor;
      if (descriptor == null) {
        continue;
      }
      _read(descriptor);
    }
  }

  final List<String> _services = <String>[];
  final Map<String, List<int>> _files = <String, List<int>>{};
  final Map<String, List<String>> _dependencies = <String, List<String>>{};
  final Map<String, String> _symbols = <String, String>{};

  /// The names of the services of the server.
  List<String> get serviceNames => List<String>.unmodifiable(_services);

  /// The bytes of the file that declares the symbol [symbol].
  ///
  /// The bytes hold the file and the files it depends on, so a reader of them
  /// resolves every type of the file. The value is `null` when no file
  /// declares the symbol.
  List<int>? descriptorOfSymbol(String symbol) {
    final file = _symbols[symbol];
    if (file == null) {
      return null;
    }
    return _withDependencies(file);
  }

  /// The bytes of the file [path].
  ///
  /// The bytes hold the file and the files it depends on. The value is `null`
  /// when the server knows no file of that path.
  List<int>? descriptorOfFile(String path) {
    if (!_files.containsKey(path)) {
      return null;
    }
    return _withDependencies(path);
  }

  /// The bytes of the file [path] and of the files it depends on.
  ///
  /// The bytes are a `FileDescriptorSet`: the file and the files it depends
  /// on, one after the other.
  List<int> _withDependencies(String path) {
    final files = <List<int>>[];
    final seen = <String>{};

    void add(String file) {
      if (!seen.add(file)) {
        return;
      }
      final content = _files[file];
      if (content == null) {
        return;
      }
      files.add(content);
      for (final dependency in _dependencies[file] ?? const <String>[]) {
        add(dependency);
      }
    }

    add(path);

    final writer = ProtoWriter();
    for (final file in files) {
      writer.writeMessage(1, file);
    }
    return writer.toBytes();
  }

  /// Reads the files of the descriptor [descriptor].
  void _read(List<int> descriptor) {
    final reader = ProtoReader(descriptor);
    while (reader.hasNext) {
      final tag = reader.readTag();
      if (tag == 1 && reader.wireType == WireType.lengthDelimited) {
        _readFile(reader.readBytes());
      } else {
        reader.skipField();
      }
    }
  }

  /// Reads the file [file] of a descriptor.
  void _readFile(List<int> file) {
    final reader = ProtoReader(file);

    var name = '';
    var package = '';
    final dependencies = <String>[];
    final symbols = <String>[];

    while (reader.hasNext) {
      final tag = reader.readTag();
      switch (tag) {
        case 1:
          name = reader.readString();
        case 2:
          package = reader.readString();
        case 3:
          dependencies.add(reader.readString());
        case 4:
          symbols.addAll(_symbolsOfMessage(reader.readBytes(), package, ''));
        case 5:
          symbols.add(_symbolOfEnum(reader.readBytes(), package, ''));
        case 6:
          symbols.addAll(_symbolsOfService(reader.readBytes(), package));
        default:
          reader.skipField();
      }
    }

    _files[name] = file;
    _dependencies[name] = dependencies;
    for (final symbol in symbols) {
      _symbols[symbol] = name;
    }
  }

  /// The symbols the message [message] declares.
  ///
  /// The [scope] is the scope the message is declared in, e.g. `Order` for a
  /// message declared inside of the message `Order`.
  List<String> _symbolsOfMessage(
      List<int> message, String package, String scope) {
    final reader = ProtoReader(message);

    var name = '';
    final symbols = <String>[];
    final children = <List<int>>[];
    final enums = <List<int>>[];

    while (reader.hasNext) {
      final tag = reader.readTag();
      switch (tag) {
        case 1:
          name = reader.readString();
        case 3:
          children.add(reader.readBytes());
        case 4:
          enums.add(reader.readBytes());
        default:
          reader.skipField();
      }
    }

    final own = scope.isEmpty ? name : '$scope.$name';
    symbols.add(_qualify(package, own));

    for (final child in children) {
      symbols.addAll(_symbolsOfMessage(child, package, own));
    }
    for (final enumType in enums) {
      symbols.add(_symbolOfEnum(enumType, package, own));
    }

    return symbols;
  }

  /// The symbol the enum [enumType] declares.
  String _symbolOfEnum(List<int> enumType, String package, String scope) {
    final reader = ProtoReader(enumType);

    var name = '';
    while (reader.hasNext) {
      final tag = reader.readTag();
      if (tag == 1) {
        name = reader.readString();
      } else {
        reader.skipField();
      }
    }

    return _qualify(package, scope.isEmpty ? name : '$scope.$name');
  }

  /// The symbols the service [service] declares.
  ///
  /// A service declares its own name and the name of every method of it: a
  /// tool asks for the file of a method the way it asks for the file of the
  /// service.
  List<String> _symbolsOfService(List<int> service, String package) {
    final reader = ProtoReader(service);

    var name = '';
    final methods = <List<int>>[];

    while (reader.hasNext) {
      final tag = reader.readTag();
      switch (tag) {
        case 1:
          name = reader.readString();
        case 2:
          methods.add(reader.readBytes());
        default:
          reader.skipField();
      }
    }

    final fullName = _qualify(package, name);
    final symbols = <String>[fullName];

    for (final method in methods) {
      final methodReader = ProtoReader(method);
      var methodName = '';
      while (methodReader.hasNext) {
        final tag = methodReader.readTag();
        if (tag == 1) {
          methodName = methodReader.readString();
        } else {
          methodReader.skipField();
        }
      }
      symbols.add('$fullName.$methodName');
    }

    return symbols;
  }

  /// The name of a symbol of the package [package].
  String _qualify(String package, String name) =>
      package.isEmpty ? name : '$package.$name';
}

/// The service of the reflection of gRPC.
///
/// The service answers the questions of a tool about the server it belongs to:
/// the services it serves and the files of their contracts.
class GrpcReflectionService extends grpc.Service {
  /// Creates the service of the reflection of the [index].
  GrpcReflectionService(this.index, {this.serviceName = reflectionServiceV1});

  /// The index of the contracts of the services of the server.
  final GrpcReflectionIndex index;

  /// The name the service is known by.
  ///
  /// The name is the one of the protocol of gRPC: the version 1 or the
  /// version 1alpha.
  final String serviceName;

  @override
  String get $name => serviceName;

  @override
  grpc.ServiceMethod? $lookupMethod(String name) =>
      name == reflectionMethod ? _method : null;

  late final grpc.ServiceMethod<List<int>, List<int>> _method =
      grpc.ServiceMethod<List<int>, List<int>>(
    reflectionMethod,
    (grpc.ServiceCall call, Stream<List<int>> requests) => _answers(requests),
    true,
    true,
    (List<int> value) => value,
    (List<int> value) => value,
  );

  /// The answers of the requests of the stream [requests].
  Stream<List<int>> _answers(Stream<List<int>> requests) async* {
    await for (final request in requests) {
      yield _answerOf(request);
    }
  }

  /// The answer of the request [request].
  List<int> _answerOf(List<int> request) {
    final reader = ProtoReader(request);

    var host = '';
    String? fileByFilename;
    String? fileContainingSymbol;
    var listsServices = false;

    while (reader.hasNext) {
      final tag = reader.readTag();
      switch (tag) {
        case 1:
          host = reader.readString();
        case 3:
          fileByFilename = reader.readString();
        case 4:
          fileContainingSymbol = reader.readString();
        case 7:
          // The request of the list of the services is an empty message, and
          // the wire of an empty message is the wire of an empty string.
          reader.skipField();
          listsServices = true;
        default:
          reader.skipField();
      }
    }

    if (listsServices) {
      return _listOfServices(host, request);
    }

    if (fileContainingSymbol != null) {
      final descriptor = index.descriptorOfSymbol(fileContainingSymbol);
      if (descriptor == null) {
        return _error(
            host,
            request,
            'The symbol "$fileContainingSymbol" is '
            'not declared by a file of this server.');
      }
      return _descriptor(host, request, descriptor);
    }

    if (fileByFilename != null) {
      final descriptor = index.descriptorOfFile(fileByFilename);
      if (descriptor == null) {
        return _error(
          host,
          request,
          'The file "$fileByFilename" is not known by this server.',
        );
      }
      return _descriptor(host, request, descriptor);
    }

    return _error(host, request, 'The request holds no question.');
  }

  /// The answer that lists the services of the server.
  List<int> _listOfServices(String host, List<int> request) {
    final list = ProtoWriter();
    for (final service in index.serviceNames) {
      final entry = ProtoWriter()..writeString(1, service);
      list.writeMessage(1, entry.toBytes());
    }

    final response = ProtoWriter()
      ..writeString(1, host)
      ..writeMessage(2, request)
      ..writeMessage(6, list.toBytes());
    return response.toBytes();
  }

  /// The answer that holds the files [descriptor].
  List<int> _descriptor(String host, List<int> request, List<int> descriptor) {
    final files = ProtoWriter();
    for (final file in _filesOf(descriptor)) {
      files.writeBytes(1, file);
    }

    final response = ProtoWriter()
      ..writeString(1, host)
      ..writeMessage(2, request)
      ..writeMessage(4, files.toBytes());
    return response.toBytes();
  }

  /// The files of the descriptor [descriptor].
  ///
  /// The descriptor holds the files of the protocol buffers one after the
  /// other, and every file is a message of its own.
  List<List<int>> _filesOf(List<int> descriptor) {
    final files = <List<int>>[];
    final reader = ProtoReader(descriptor);

    while (reader.hasNext) {
      final tag = reader.readTag();
      if (tag == 1 && reader.wireType == WireType.lengthDelimited) {
        files.add(reader.readBytes());
      } else {
        reader.skipField();
      }
    }

    return files;
  }

  /// The answer that holds the problem [message].
  List<int> _error(String host, List<int> request, String message) {
    final error = ProtoWriter()
      ..writeInt32(1, _codeNotFound)
      ..writeString(2, message);

    final response = ProtoWriter()
      ..writeString(1, host)
      ..writeMessage(2, request)
      ..writeMessage(7, error.toBytes());
    return response.toBytes();
  }
}

/// The code of the status of gRPC that means "not found".
const int _codeNotFound = 5;
