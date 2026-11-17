/// The health probes of a service.
library;

import 'app.dart';
import 'db/database.dart';

/// Registers the health probes of the service.
///
/// * `/healthz` answers `200` as long as the process is alive — it is the
///   liveness probe;
/// * `/readyz` answers `200` when the service is ready to serve traffic and
///   `503` otherwise — it is the readiness probe.
///
/// The readiness is decided by [isReady]. When it is not given, the service
/// is ready as soon as it runs.
void registerHealthChecks(
  Laska app, {
  Future<bool> Function()? isReady,
  String prefix = '',
}) {
  app.get(
    '$prefix/healthz',
    (ctx) => ctx.json(<String, Object?>{
      'status': 'ok',
      'service': app.logger.service,
    }),
  );

  app.get('$prefix/readyz', (ctx) async {
    final ready = isReady == null ? true : await isReady();
    return ctx.json(
      <String, Object?>{
        'status': ready ? 'ok' : 'unavailable',
        'service': app.logger.service,
      },
      status: ready ? 200 : 503,
    );
  });
}

/// A readiness check that asks the database.
///
/// It returns `false` when the database does not answer, so a service with a
/// broken database stops receiving traffic instead of failing every request.
Future<bool> databaseReady(Database? database) async {
  if (database == null) {
    return true;
  }
  return database.ping();
}
