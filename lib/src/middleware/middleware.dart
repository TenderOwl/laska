import '../context.dart';

/// Middleware is a class with `execute` method
/// called before the route handler will be called.
abstract class Middleware {

  /// The middleware handler.
  /// Executes logic and calls the `next` function to chain the process.
  Future<Function> execute(Function next, Context context);
}
