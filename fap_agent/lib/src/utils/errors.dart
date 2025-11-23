import 'package:flutter/foundation.dart';

class FapError {
  final String code;
  final String message;
  final String? details;
  final DateTime timestamp;

  FapError({
    required this.code,
    required this.message,
    this.details,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
      'details': details,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class ErrorMonitor {
  final List<FapError> _errors = [];

  void start() {
    FlutterError.onError = (FlutterErrorDetails details) {
      _errors.add(FapError(
        code: 'FLUTTER_ERROR',
        message: details.exceptionAsString(),
        details: details.stack.toString(),
      ));
      
      // Call original handler if needed, or just print
      FlutterError.presentError(details);
    };
  }

  List<FapError> getErrors({DateTime? since}) {
    if (since == null) return List.from(_errors);
    return _errors.where((e) => e.timestamp.isAfter(since)).toList();
  }
}
