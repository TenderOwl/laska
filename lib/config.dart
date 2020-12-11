import 'dart:io';
import 'package:laska/router.dart';

class Configuration
{
  int isolatesCount = Platform.numberOfProcessors;
  String address = 'localhost';
  int port = 3789;
  Router router;
}