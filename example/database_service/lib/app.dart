import 'package:laska_core/laska_core.dart';

import 'accounts.dart';
import 'database.dart';

/// Builds the application of the example.
///
/// The routes ask the repository for the accounts and never touch the database
/// themselves, so the SQL stays in one place and the routes may be tested
/// without a database.
Future<Laska> buildApp({required Database database}) async {
  final app = Laska();

  // The service registers its database, so the migration runner of the
  // framework finds it and the readiness probe asks it whether the service is
  // able to serve traffic.
  app.database = database;
  app.migrationsDirectory = migrationsDirectory;

  // The observability is installed before the routes, so its middleware runs
  // before the middleware of the routes.
  await Observability.install(app);

  final accounts = AccountRepository(database);

  app.get('/accounts', (ctx) async {
    final list = await accounts.list();
    return ctx.json(<String, Object?>{
      'accounts': list.map((account) => account.toJson()).toList(),
    });
  });

  app.get('/accounts/:id', (ctx) async {
    final account = await accounts.findById(ctx.params['id']!);
    if (account == null) {
      throw HttpException(
        404,
        'The account was not found.',
        code: 'account_not_found',
      );
    }
    return ctx.json(account.toJson());
  });

  app.post('/accounts', (ctx) async {
    final body = ctx.request.json();
    final id = body['id'];
    final name = body['name'];

    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      throw HttpException(
        400,
        'An account needs an id and a name.',
        code: 'invalid_account',
      );
    }

    final balance = body['balance'];
    if (balance is! int || balance < 0) {
      throw HttpException(
        400,
        'The balance of an account is a positive number of cents.',
        code: 'invalid_balance',
      );
    }

    final account = await accounts.create(id: id, name: name, balance: balance);

    return Response.json(account.toJson(), status: 201);
  });

  app.post('/transfers', (ctx) async {
    final body = ctx.request.json();
    final from = body['from'];
    final to = body['to'];
    final amount = body['amount'];

    if (from is! String || to is! String || amount is! int) {
      throw HttpException(
        400,
        'A transfer needs the accounts and the amount.',
        code: 'invalid_transfer',
      );
    }

    final transfer = await accounts.transfer(
      from: from,
      to: to,
      amount: amount,
    );

    return Response.json(transfer.toJson(), status: 201);
  });

  app.get('/transfers', (ctx) async {
    final list = await accounts.transfers();
    return ctx.json(<String, Object?>{
      'transfers': list.map((transfer) => transfer.toJson()).toList(),
    });
  });

  return app;
}
