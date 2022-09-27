import 'package:laska/laska.dart';

void main() async {
  final laska = Laska();

  laska.GET('/hello/:name',
      (context) async => await context.Text("Hello ${context.param('name')}!"));

  await run(laska);
}
