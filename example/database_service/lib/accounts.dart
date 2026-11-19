import 'package:laska_core/laska_core.dart';

/// An account of the service.
class Account {
  const Account({required this.id, required this.name, required this.balance});

  /// The identifier of the account.
  final String id;

  /// The name of the owner of the account.
  final String name;

  /// The money of the account, in cents.
  final int balance;

  /// The account in the form of a JSON document.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'balance': balance,
  };
}

/// A transfer of money from one account to another.
class Transfer {
  const Transfer({
    required this.from,
    required this.to,
    required this.amount,
    required this.createdAt,
  });

  /// The account the money comes from.
  final String from;

  /// The account the money goes to.
  final String to;

  /// The money of the transfer, in cents.
  final int amount;

  /// When the transfer happened.
  final DateTime createdAt;

  /// The transfer in the form of a JSON document.
  Map<String, Object?> toJson() => <String, Object?>{
    'from': from,
    'to': to,
    'amount': amount,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}

/// The repository of the accounts.
///
/// The repository is the only part of the service that knows the SQL. The
/// routes ask it for the accounts and never touch the database themselves.
class AccountRepository {
  AccountRepository(this._database);

  final Database _database;

  /// Every account, ordered by the identifier.
  Future<List<Account>> list() async {
    final rows = await _database.query(
      'SELECT id, name, balance FROM accounts ORDER BY id',
    );
    return rows.map(_toAccount).toList();
  }

  /// The account of the [id], or `null` when there is none.
  Future<Account?> findById(String id) async {
    final rows = await _database.query(
      'SELECT id, name, balance FROM accounts WHERE id = ?',
      <Object?>[id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _toAccount(rows.first);
  }

  /// Creates an account.
  Future<Account> create({
    required String id,
    required String name,
    required int balance,
  }) async {
    await _database.execute(
      'INSERT INTO accounts (id, name, balance) VALUES (?, ?, ?)',
      <Object?>[id, name, balance],
    );
    return Account(id: id, name: name, balance: balance);
  }

  /// Moves the [amount] from one account to another.
  ///
  /// The three writes — the two balances and the ledger — happen in one
  /// transaction. When any of them fails, the others are rolled back, so no
  /// money is created and none is lost. The transaction is the reason the
  /// balance of an account never tells a half-finished story.
  Future<Transfer> transfer({
    required String from,
    required String to,
    required int amount,
  }) async {
    if (amount <= 0) {
      throw HttpException(
        422,
        'The amount of a transfer has to be positive.',
        code: 'invalid_amount',
      );
    }

    final transfer = Transfer(
      from: from,
      to: to,
      amount: amount,
      createdAt: DateTime.now().toUtc(),
    );

    await _database.transaction((transaction) async {
      final source = await transaction.query(
        'SELECT balance FROM accounts WHERE id = ?',
        <Object?>[from],
      );
      if (source.isEmpty) {
        throw HttpException(
          404,
          'The account "$from" was not found.',
          code: 'account_not_found',
        );
      }

      final target = await transaction.query(
        'SELECT id FROM accounts WHERE id = ?',
        <Object?>[to],
      );
      if (target.isEmpty) {
        throw HttpException(
          404,
          'The account "$to" was not found.',
          code: 'account_not_found',
        );
      }

      final balance = source.first['balance']! as int;
      if (balance < amount) {
        throw HttpException(
          422,
          'The account "$from" does not hold the money.',
          code: 'insufficient_funds',
        );
      }

      await transaction.execute(
        'UPDATE accounts SET balance = balance - ? WHERE id = ?',
        <Object?>[amount, from],
      );
      await transaction.execute(
        'UPDATE accounts SET balance = balance + ? WHERE id = ?',
        <Object?>[amount, to],
      );
      await transaction.execute(
        'INSERT INTO transfers (from_account, to_account, amount, created_at) '
        'VALUES (?, ?, ?, ?)',
        <Object?>[from, to, amount, transfer.createdAt.toIso8601String()],
      );
    });

    return transfer;
  }

  /// The transfers of the service, the newest first.
  Future<List<Transfer>> transfers() async {
    final rows = await _database.query(
      'SELECT from_account, to_account, amount, created_at '
      'FROM transfers ORDER BY id DESC',
    );
    return rows
        .map(
          (row) => Transfer(
            from: row['from_account']! as String,
            to: row['to_account']! as String,
            amount: row['amount']! as int,
            createdAt: DateTime.parse(row['created_at']! as String),
          ),
        )
        .toList();
  }

  Account _toAccount(Map<String, Object?> row) => Account(
    id: row['id']! as String,
    name: row['name']! as String,
    balance: row['balance']! as int,
  );
}
