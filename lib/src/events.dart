import 'package:event/event.dart';
import 'laska.dart';

class StartupEventArgs extends EventArgs {
  Laska app;

  StartupEventArgs(this.app);
}

class TeardownEventArgs extends EventArgs {
  Laska app;

  TeardownEventArgs(this.app);
}
