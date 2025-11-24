import 'dart:async';
import 'dart:collection';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

import 'src/server/rpc_handler.dart';
import 'src/server/ws_server.dart';

import 'src/widgets/fap_navigator_observer.dart';
import 'src/core/semantics_index.dart';
import 'src/core/recorder.dart';

export 'src/widgets/fap_meta.dart';
export 'src/widgets/fap_navigator_observer.dart';

class FapConfig {
  final int port;
  final bool enabled;
  final String? secretToken;

  final int maxFrameTimings;
  final int maxLogs;
  final int maxErrors;

  const FapConfig({
    this.port = 9001,
    this.enabled = !kReleaseMode,
    this.secretToken,
    this.maxFrameTimings = 100,
    this.maxLogs = 1000,
    this.maxErrors = 100,
  });
}



class FapAgent {
  static FapAgent? _instance;
  final FapConfig config;
  FapServer? _server;
  SemanticsHandle? _semanticsHandle;
  final FapNavigatorObserver navigatorObserver = FapNavigatorObserver();
  
  // Core Components
  final SemanticsIndexer _indexer = SemanticsIndexer();
  late final Recorder _recorder;

  // Observability Data
  late final ListQueue<FrameTiming> _frameTimings;
  late final ListQueue<String> _logs;
  late final ListQueue<String> _errors;

  FapAgent._(this.config) {
    _recorder = Recorder(_indexer);
    _frameTimings = ListQueue<FrameTiming>(config.maxFrameTimings);
    _logs = ListQueue<String>(config.maxLogs);
    _errors = ListQueue<String>(config.maxErrors);
  }

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
        if (_frameTimings.length > config.maxFrameTimings) _frameTimings.removeFirst();
      }
    });

    // 2. Log Capture (intercept debugPrint)
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        _logs.add('${DateTime.now().toIso8601String()}: $message');
        if (_logs.length > config.maxLogs) _logs.removeFirst();
      }
      originalDebugPrint(message, wrapWidth: wrapWidth);
    };

    // 3. Async Errors
    PlatformDispatcher.instance.onError = (error, stack) {
      _errors.add('${DateTime.now().toIso8601String()}: $error\n$stack');
      if (_errors.length > config.maxErrors) _errors.removeFirst();
      return false; // Allow error to propagate
    };
  }

  Future<void> _start() async {
    if (!config.enabled) return;
    
    final rpcHandler = FapRpcHandlerImpl(
      agent: this,
      indexer: _indexer,
      recorder: _recorder,
    );
    
    _server = FapServer(
      port: config.port, 
      rpcHandler: rpcHandler,
      secretToken: config.secretToken,
    );

    // Wire up Recorder events
    _recorder.events.listen((event) {
      _server?.broadcastNotification('recording.event', event);
    });

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
