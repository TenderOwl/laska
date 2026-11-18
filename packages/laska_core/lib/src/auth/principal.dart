/// Who is calling the service.
///
/// The principal is what the authentication middleware leaves in the request.
/// A handler asks the request who the caller is and what the caller may do.
library;

/// The kind of the caller.
enum PrincipalKind {
  /// The caller is a person.
  user,

  /// The caller is another service.
  service,

  /// The caller is a machine that holds an API key.
  apiKey,

  /// The caller is not known.
  anonymous,
}

/// The caller of a service.
class Principal {
  /// Creates a principal.
  const Principal({
    required this.id,
    this.kind = PrincipalKind.user,
    this.issuer,
    this.scopes = const <String>[],
    this.claims = const <String, Object?>{},
  });

  /// The id of the caller.
  ///
  /// It is the subject of the token of the caller, the id of the API key or
  /// the id of the session, depending on how the caller proved who it is.
  final String id;

  /// The kind of the caller.
  final PrincipalKind kind;

  /// The service that issued the token of the caller.
  final String? issuer;

  /// What the caller may do.
  final List<String> scopes;

  /// The claims of the token of the caller.
  final Map<String, Object?> claims;

  /// Whether the caller may do [scope].
  bool hasScope(String scope) => scopes.contains(scope);

  /// Whether the caller may do any of the [scopes].
  bool hasAnyScope(Iterable<String> scopes) =>
      scopes.any((scope) => hasScope(scope));

  @override
  String toString() => 'Principal($id, ${kind.name})';
}
