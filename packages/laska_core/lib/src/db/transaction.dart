import '../errors.dart';
import 'database.dart';

/// The error of a transaction that failed.
///
/// The body of a transaction often refuses the work of the caller: an account
/// that does not exist, a transfer of an amount the account does not hold.
/// Such a refusal is a domain error of the service, and the caller has to see
/// the status it carries — a `404` or a `422`, not a `500`. It is therefore
/// thrown as it is.
///
/// The failure of the database itself is wrapped, so the service may tell the
/// two apart: a broken database is an incident, a refused operation is not.
Object transactionError(Object error) {
  if (error is DatabaseException || error is HttpException) {
    return error;
  }

  return DatabaseException('Transaction failed', cause: error);
}
