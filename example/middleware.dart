import 'package:laska/laska.dart';

// Custom middleware that checks user access.
class Acl implements Middleware {
  final allowedRoles;

  Acl(this.allowedRoles);

  @override
  Future<Function> execute(Function next, Context context) async {
    return (Context c) {
      // In this case it's simple check:
      // Does the request contains `role` header with `admin` value.
      final role = context.request.headers.value('role');

      // If the header's `role` is not in `allowedRoles`, reject the request.
      if (!allowedRoles.contains(role)) {
        context.Text('Role $role is not allowed.');
        return null;
      }
      print('Role $role is allowed.');

      // Don't forget to call the handler.
      return next(c);
    };
  }
}

// Custom middleware that prints request path and given prefix.
class Logger implements Middleware {
  String prefix;

  Logger(this.prefix);

  @override
  Future<Function> execute(Function next, Context context) async {
    return (Context c) {
      print('$prefix: Path: ${context.path}');

      // Don't forget to call the handler.
      return next(c);
    };
  }
}

void main() async {
  final laska = Laska();

  final acl_middleware = Acl(['admin']);

  // Add global middleware
  laska.Use(Logger('global'));

  // Create handler with per-route middlewares: logger and acl
  laska.GET('/secret', secretHandler,
      middlewares: {Logger('route'), acl_middleware});

  // Add route handler, only global middleware will apply
  laska.GET('/users', getUsers);

  // Add route with acl middleware, but only for the POST method.
  laska.POST('/users', getUsers, middlewares: {acl_middleware});

  await run(laska);
}

void secretHandler(Context context) async {
  await context.Text('You have access to secret path!');
}

void getUsers(Context context) async {
  await context.JSON([
    {'id': 1, 'name': 'Make something useful', 'status': 0},
    {'id': 2, 'name': 'Make new website', 'status': 1},
  ]);
}
