import 'package:laska/context.dart';

/// Middleware is a class with `execute` method
/// called before the route handler will be called.
abstract class Middleware {
  Future<Function> execute(Function next, Context context);
}
