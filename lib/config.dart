import 'dart:io';
import 'package:laska/router.dart';

/// Stores [Laska] configuration.
class Configuration {
  /// The count of [Isolate] to process requests.
  int isolatesCount = Platform.numberOfProcessors;

  /// Default server address.
  String address = 'localhost';

  /// Default server port.
  int port = 3789;

  /// The Router object filled with routes.
  Router router;
}