import 'dart:io';
import 'dart:async';

import 'package:stream_channel/stream_channel.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as json_rpc;

import 'rpc_handler.dart';

class FapServer {
  final int port;
  final FapRpcHandler rpcHandler;
  final String? secretToken;
  HttpServer? _server;
  final List<WebSocket> _sockets = [];

  FapServer({
    required this.port,
    required this.rpcHandler,
    this.secretToken,
  });

  Future<void> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      print('FAP Agent listening on ws://localhost:$port');

      _server!.listen((HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          // Check Auth Token
          if (secretToken != null) {
            final authHeader = request.headers.value('Authorization');
            if (authHeader != 'Bearer $secretToken') {
              print('FAP Agent: Unauthorized connection attempt');
              request.response.statusCode = HttpStatus.unauthorized;
              await request.response.close();
              return;
            }
          }

          final socket = await WebSocketTransformer.upgrade(request);
          _handleWebSocket(socket);
        } else {
          request.response.statusCode = HttpStatus.forbidden;
          await request.response.close();
        }
      });
    } catch (e) {
      print('FAP Agent failed to start: $e');
    }
  }

  Future<void> stop() async {
    for (final socket in _sockets) {
      socket.close();
    }
    await _server?.close();
    _server = null;
  }

  void _handleWebSocket(WebSocket socket) {
    _sockets.add(socket);
    print('FAP Client connected');

    // Create a StreamChannel from the WebSocket
    final channel = StreamChannel(socket, socket).cast<String>();
    
    // Create a JSON-RPC Server
    final server = json_rpc.Server(channel);
    
    // Register methods
    rpcHandler.registerMethods(server);
    
    // Listen
    server.listen().then((_) {
      _sockets.remove(socket);
      print('FAP Client disconnected');
    }).catchError((error) {
      _sockets.remove(socket);
      print('FAP Client error: $error');
    });
  }
}
