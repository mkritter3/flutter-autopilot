import 'dart:async';
import 'dart:collection';
import 'dart:io';
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
import 'src/core/widget_inspector_bridge.dart';
import 'src/core/text_input_simulator.dart';

export 'src/widgets/fap_meta.dart';
export 'src/widgets/fap_navigator_observer.dart';
export 'src/core/widget_inspector_bridge.dart';
export 'src/core/text_input_simulator.dart';
export 'src/core/flutter_controller.dart';

class FapConfig {
  final int port;
  final bool enabled;
  final String? secretToken;
  final InternetAddress? bindAddress;

  final int maxFrameTimings;
  final int maxLogs;
  final int maxErrors;

  const FapConfig({
    this.port = 9001,
    this.enabled = !kReleaseMode,
    this.secretToken,
    this.bindAddress,
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

  // Connection tracking for lazy Semantics activation
  int _clientCount = 0;

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

    // DON'T enable semantics yet - wait for client connection
    // This prevents FAP from interfering with native platform views (e.g., Plaid)
    WidgetsFlutterBinding.ensureInitialized();
    print('FapAgent: Initialized (Semantics will activate on client connection)');

    _instance!._setupObservability();
    await _instance!._start();
  }

  void _setupObservability() {
    // 1. Frame Timings
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        _frameTimings.add(timing);
        if (_frameTimings.length > config.maxFrameTimings)
          _frameTimings.removeFirst();
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
      bindAddress: config.bindAddress,
    );

    // Wire up Recorder events
    _recorder.events.listen((event) {
      _server?.broadcastNotification('recording.event', event);
    });

    await _server!.start();
  }

  /// Called when a client connects - enables Semantics on first connection
  void onClientConnected() {
    _clientCount++;
    if (_clientCount == 1 && _semanticsHandle == null) {
      _semanticsHandle = SemanticsBinding.instance.ensureSemantics();
      print('FapAgent: Semantics enabled (client connected)');

      // Force a frame rebuild to populate the Semantics tree
      // Without this, the tree may remain empty even after ensureSemantics()
      SchedulerBinding.instance.scheduleFrame();
      print('FapAgent: Frame rebuild scheduled');

      // Initialize Widget Inspector for advanced widget targeting
      WidgetInspectorBridge.instance.initialize();
      print('FAP Widget Inspector: Enabled');

      // Initialize Text Input Simulator for keyboard simulation
      // Accessing .instance installs the channel interceptor
      final _ = TextInputSimulator.instance;
      print('FAP TextInputSimulator: Interceptor installed');
    }
  }

  /// Called when a client disconnects - disables Semantics when last client leaves
  void onClientDisconnected() {
    _clientCount--;
    if (_clientCount == 0 && _semanticsHandle != null) {
      _semanticsHandle!.dispose();
      _semanticsHandle = null;
      print('FapAgent: Semantics disabled (no clients connected)');
    }
  }

  static Future<void> stop() async {
    await _instance?._server?.stop();
    _instance = null;
  }

  // Public API for RPC Handler
  List<Map<String, int>> getPerformanceMetrics() {
    return _frameTimings
        .map(
          (t) => {
            'build': t.buildDuration.inMicroseconds,
            'raster': t.rasterDuration.inMicroseconds,
            'total': t.totalSpan.inMicroseconds,
          },
        )
        .toList();
  }

  List<String> getLogs() {
    return _logs.toList();
  }

  List<String> getErrors() {
    return _errors.toList();
  }
}
