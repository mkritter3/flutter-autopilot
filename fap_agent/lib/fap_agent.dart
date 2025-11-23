import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
  final FapConfig config;
  FapServer? _server;

  FapAgent._(this.config);

  static FapAgent? _instance;

  static Future<void> init(FapConfig config) async {
    if (_instance != null) return;
    _instance = FapAgent._(config);
    
    WidgetsFlutterBinding.ensureInitialized();
    SemanticsBinding.instance.ensureSemantics();
    
    await _instance!._start();
  }

  Future<void> _start() async {
    if (!config.enabled) return;
    
    final rpcHandler = FapRpcHandlerImpl();
    _server = FapServer(
      port: config.port,
      rpcHandler: rpcHandler,
    );
    await _server!.start();
  }
}
