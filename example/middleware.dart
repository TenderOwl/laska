import 'package:laska/laska.dart';

class Acl extends Middleware {
  final allowedRoles;

  Acl(this.allowedRoles);

  @override
  Future<Function> execute(Function next, Context context) {
    // TODO: implement execute
    final role = context.request.headers['role'];
    if (!allowedRoles.contains(role)) {
      context.Text('Role $role is not allowed.');
      return null;
    }

    // Don't forget to call the handler.
    return next();
  }
}

void main() async {
  final laska = Laska(isolateCount: 2);
  final acl_middleware = Acl(['admin']);
  laska.GET('/secret', secretHandler, middlewares: [acl_middleware]);

  await run(laska);
}

void secretHandler(Context context) async {
  await context.Text('You have access to secret path!');
}
