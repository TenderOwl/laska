/// The addresses of the services of the workspace.
///
/// The discovery of Laska is static: the addresses come from the environment
/// or from the manifest of the workspace. A Consul or a Kubernetes plug can
/// replace it later, because the rest of the runtime only asks the discovery
/// for an address.
library;

import 'errors.dart';

/// The addresses of the services of the workspace.
class ServiceDiscovery {
  /// Creates a discovery holding the given [services].
  ServiceDiscovery(Map<String, Uri> services)
      : _services = <String, Uri>{...services};

  /// Creates a discovery out of the environment of the process.
  ///
  /// Two forms are read:
  ///
  /// * `LASKA_SERVICES` — a list of `name=url` pairs, separated by commas,
  ///   e.g. `users=http://localhost:8080,orders=http://localhost:8081`;
  /// * `<NAME>_URL` — the address of one service, e.g. `USERS_URL`.
  factory ServiceDiscovery.fromEnvironment([Map<String, String>? environment]) {
    final values = environment ?? const <String, String>{};
    final services = <String, Uri>{};

    final list = values['LASKA_SERVICES'];
    if (list != null) {
      for (final entry in list.split(',')) {
        final trimmed = entry.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        final separator = trimmed.indexOf('=');
        if (separator <= 0) {
          continue;
        }
        final name = trimmed.substring(0, separator).trim();
        final url = trimmed.substring(separator + 1).trim();
        final uri = Uri.tryParse(url);
        if (name.isNotEmpty && uri != null) {
          services[name] = uri;
        }
      }
    }

    for (final entry in values.entries) {
      if (!entry.key.endsWith('_URL')) {
        continue;
      }
      final name = entry.key.substring(0, entry.key.length - '_URL'.length);
      final uri = Uri.tryParse(entry.value);
      if (name.isEmpty || uri == null || services.containsKey(name)) {
        continue;
      }
      services[name] = uri;
    }

    return ServiceDiscovery(services);
  }

  final Map<String, Uri> _services;

  /// The names of the services that are known.
  Set<String> get names => _services.keys.toSet();

  /// The address of the service [name], or `null` when it is not known.
  ///
  /// The lookup ignores the case of the name, so a service that the
  /// environment declares as `USERS_URL` is found as `users` — which is how
  /// the services of a workspace are named.
  Uri? find(String name) {
    final exact = _services[name];
    if (exact != null) {
      return exact;
    }

    final lower = name.toLowerCase();
    for (final entry in _services.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value;
      }
    }

    return null;
  }

  /// The address of the service [name].
  ///
  /// Throws [ServiceNotFoundException] when the service is not known, so a
  /// missing address is a clear error and not a call to `null`.
  Uri resolve(String name) {
    final uri = find(name);
    if (uri == null) {
      throw ServiceNotFoundException(name, known: names.toList()..sort());
    }
    return uri;
  }

  /// Replaces the addresses of the services.
  void update(Map<String, Uri> services) {
    _services
      ..clear()
      ..addAll(services);
  }

  /// Adds or replaces the address of one service.
  void put(String name, Uri uri) {
    _services[name] = uri;
  }
}
