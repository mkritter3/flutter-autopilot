import 'dart:async';
import 'dart:collection';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

import 'src/server/rpc_handler.dart';
import 'src/server/ws_server.dart';

export 'src/widgets/fap_meta.dart';

class FapConfig {
  final int port;
  final bool enabled;

  const FapConfig({
    this.port = 9001,
    this.enabled = true,
  });
}

class FapAgent {
  static FapAgent? _instance;
  final FapConfig config;
  FapServer? _server;
  SemanticsHandle? _semanticsHandle;

  // Observability Data
  final ListQueue<FrameTiming> _frameTimings = ListQueue<FrameTiming>(100);
  final ListQueue<String> _logs = ListQueue<String>(1000);
  final ListQueue<String> _errors = ListQueue<String>(100);

  FapAgent._(this.config);

  static FapAgent get instance => _instance!;

  static Future<void> init(FapConfig config) async {
    print('FapAgent: Initializing...');
    if (_instance != null) return;
    _instance = FapAgent._(config);
    
    // Ensure semantics are enabled
    WidgetsFlutterBinding.ensureInitialized();
    _instance!._semanticsHandle = SemanticsBinding.instance.ensureSemantics();
    print('FapAgent: Semantics enabled. Handle: ${_instance!._semanticsHandle}');
    
    _instance!._setupObservability();
    await _instance!._start();
  }

  void _setupObservability() {
    // 1. Frame Timings
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        _frameTimings.add(timing);
        if (_frameTimings.length > 100) _frameTimings.removeFirst();
      }
    });

    // 2. Log Capture (intercept debugPrint)
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        _logs.add('${DateTime.now().toIso8601String()}: $message');
        if (_logs.length > 1000) _logs.removeFirst();
      }
      originalDebugPrint(message, wrapWidth: wrapWidth);
    };

    // 3. Async Errors
    PlatformDispatcher.instance.onError = (error, stack) {
      _errors.add('${DateTime.now().toIso8601String()}: $error\n$stack');
      if (_errors.length > 100) _errors.removeFirst();
      return false; // Allow error to propagate
    };
  }

  Future<void> _start() async {
    if (!config.enabled) return;
    
    final rpcHandler = FapRpcHandlerImpl(agent: this);
    _server = FapServer(port: config.port, rpcHandler: rpcHandler);
    await _server!.start();
  }

  static Future<void> stop() async {
    await _instance?._server?.stop();
    _instance = null;
  }

  // Public API for RPC Handler
  List<Map<String, int>> getPerformanceMetrics() {
    return _frameTimings.map((t) => {
      'build': t.buildDuration.inMicroseconds,
      'raster': t.rasterDuration.inMicroseconds,
      'total': t.totalSpan.inMicroseconds,
    }).toList();
  }

  List<String> getLogs() {
    return _logs.toList();
  }

  List<String> getErrors() {
    return _errors.toList();
  }
}
