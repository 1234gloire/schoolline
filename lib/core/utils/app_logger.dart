import 'package:flutter/foundation.dart';

class AppLogger {
  AppLogger._();

  static void info(String tag, String message) {
    if (kDebugMode) debugPrint('[$tag] $message');
  }

  static void warn(String tag, String message) {
    if (kDebugMode) debugPrint('[WARN][$tag] $message');
  }

  static void error(String tag, String message, [Object? err, StackTrace? stack]) {
    debugPrint('[ERROR][$tag] $message${err != null ? '\n  $err' : ''}${stack != null ? '\n  $stack' : ''}');
  }
}
