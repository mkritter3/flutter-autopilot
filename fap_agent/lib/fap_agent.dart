import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

import 'src/server/rpc_handler.dart';
import 'src/server/ws_server.dart';

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

  FapAgent._(this.config);

  static Future<void> init(FapConfig config) async {
    print('FapAgent: Initializing...');
    if (_instance != null) return;
    _instance = FapAgent._(config);
    
    // Ensure semantics are enabled
    WidgetsFlutterBinding.ensureInitialized();
    _instance!._semanticsHandle = SemanticsBinding.instance.ensureSemantics();
    print('FapAgent: Semantics enabled. Handle: ${_instance!._semanticsHandle}');
    
    await _instance!._start();
  }

  Future<void> _start() async {
    if (!config.enabled) return;
    
    final rpcHandler = FapRpcHandlerImpl();
    _server = FapServer(port: config.port, rpcHandler: rpcHandler);
    await _server!.start();
  }

  static Future<void> stop() async {
    await _instance?._server?.stop();
    _instance = null;
  }
}
