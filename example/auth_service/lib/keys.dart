import 'package:laska_core/laska_core.dart';

/// The issuer of the tokens of the example service.
const String serviceIssuer = 'https://auth.laska.example';

/// The service the tokens of the example are meant for.
const String serviceAudience = 'laska-auth-service';

/// The keys and the secrets of the example service.
///
/// The service signs the tokens of its callers with one key and verifies them
/// with the same key. A service that talks to other services publishes the
/// public part of the key in the key set of the service (the JWKS), so the
/// token of another service is verified without a shared secret.
class ServiceKeys {
  ServiceKeys({
    required this.signer,
    required this.verifier,
    required this.apiKeys,
    required this.sessions,
  });

  /// The keys of a service that runs in the development and in the tests.
  ///
  /// The key of a real service comes from the environment or from the key
  /// store of the service, and never from the code.
  factory ServiceKeys.development({String machineKey = 'machine-secret'}) {
    final key = generateHmacKey(kid: 'dev-1');

    return ServiceKeys(
      signer: JwtSigner(key),
      verifier: JwtVerifier(
        keys: <JwtKey>[key],
        issuer: serviceIssuer,
        audience: const <String>[serviceAudience],
      ),
      apiKeys: ApiKeyGuard(<ApiKey>[
        ApiKey(
          id: 'reporting',
          name: 'The reporting service',
          hash: hashApiKey(machineKey),
          scopes: const <String>['reports:read'],
        ),
      ]),
      sessions: MemorySessionStore(),
    );
  }

  /// Signs the tokens of the callers.
  final JwtSigner signer;

  /// Verifies the tokens of the callers.
  final JwtVerifier verifier;

  /// Checks the API keys of the machines that call the service.
  final ApiKeyGuard apiKeys;

  /// Holds the sessions of the browsers.
  final SessionStore sessions;
}
