import 'dart:async';
import 'dart:io';

import 'package:json_rpc_2/json_rpc_2.dart' as json_rpc;
import 'package:web_socket_channel/io.dart';

import 'rpc_handler.dart';

class FapServer {
  HttpServer? _server;
  final int port;
  final FapRpcHandler _rpcHandler;
  final List<json_rpc.Server> _activeConnections = [];

  FapServer({
    this.port = 9001,
    required FapRpcHandler rpcHandler,
  }) : _rpcHandler = rpcHandler;

  Future<void> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      print('FAP Agent listening on ws://localhost:$port');

      _server!.listen((HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          _handleConnection(socket);
        } else {
          request.response
            ..statusCode = HttpStatus.forbidden
            ..close();
        }
      });
    } catch (e) {
      print('Failed to start FAP server: $e');
      rethrow;
    }
  }

  void _handleConnection(WebSocket socket) {
    final channel = IOWebSocketChannel(socket);
    final rpcServer = json_rpc.Server(channel.cast<String>());

    _rpcHandler.registerMethods(rpcServer);

    _activeConnections.add(rpcServer);
    rpcServer.listen().then((_) {
      _activeConnections.remove(rpcServer);
    });
  }

  Future<void> stop() async {
    for (final conn in _activeConnections) {
      await conn.close();
    }
    await _server?.close();
    _server = null;
  }
}
