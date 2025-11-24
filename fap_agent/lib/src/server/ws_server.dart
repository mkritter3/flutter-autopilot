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
  final List<json_rpc.Peer> _peers = [];

  FapServer({
    required this.port,
    required this.rpcHandler,
    this.secretToken,
  });

  Future<void> start() async {
    try {
      // Secondary Gate: Environment Variable
      final envEnabled = Platform.environment['FAP_ENABLED'];
      if (envEnabled != null && envEnabled.toLowerCase() == 'false') {
        print('FAP Agent disabled via FAP_ENABLED environment variable.');
        return;
      }

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
    for (final peer in _peers) {
      await peer.close();
    }
    await _server?.close();
    _server = null;
  }

  void broadcastNotification(String method, dynamic params) {
    for (final peer in _peers) {
      if (!peer.isClosed) {
        peer.sendNotification(method, params);
      }
    }
  }

  void _handleWebSocket(WebSocket socket) {
    print('FAP Client connected');

    // Create a StreamChannel from the WebSocket
    final channel = StreamChannel(socket, socket).cast<String>();
    
    // Create a JSON-RPC Peer (supports bidirectional)
    final peer = json_rpc.Peer(channel);
    _peers.add(peer);
    
    // Register methods
    rpcHandler.registerMethods(peer);
    
    // Listen
    peer.listen().then((_) {
      _peers.remove(peer);
      print('FAP Client disconnected');
    }).catchError((error) {
      _peers.remove(peer);
      print('FAP Client error: $error');
    });
  }
}
