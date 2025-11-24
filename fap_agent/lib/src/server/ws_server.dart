import 'dart:io';
import 'dart:async';

import 'package:stream_channel/stream_channel.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as json_rpc;

import 'rpc_handler.dart';

class FapServer {
  final int port;
  final FapRpcHandler rpcHandler;
  final String? secretToken;
  final InternetAddress bindAddress;
  HttpServer? _server;
  final List<json_rpc.Peer> _peers = [];

  FapServer({
    required this.port,
    required this.rpcHandler,
    this.secretToken,
    InternetAddress? bindAddress,
  }) : bindAddress = bindAddress ?? InternetAddress.loopbackIPv4;

  Future<void> start() async {
    try {
      // Secondary Gate: Environment Variable
      final envEnabled = Platform.environment['FAP_ENABLED'];
      if (envEnabled != null && envEnabled.toLowerCase() == 'false') {
        print('FAP Agent disabled via FAP_ENABLED environment variable.');
        return;
      }

      final address = await _resolveBindAddress();
      _server = await HttpServer.bind(address, port);
      print('FAP Agent listening on ws://${_formatAddress(address)}:$port');

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

  Future<InternetAddress> _resolveBindAddress() async {
    final override = Platform.environment['FAP_BIND_ADDRESS'];
    if (override != null && override.isNotEmpty) {
      final parsed = InternetAddress.tryParse(override);
      if (parsed != null) {
        return parsed;
      }
      try {
        final lookup = await InternetAddress.lookup(override);
        if (lookup.isNotEmpty) {
          return lookup.first;
        }
      } catch (err) {
        print(
          'FAP Agent: Failed to resolve FAP_BIND_ADDRESS="$override" ($err). Using ${bindAddress.address}.',
        );
      }
    }
    return bindAddress;
  }

  String _formatAddress(InternetAddress address) {
    if (address.address == InternetAddress.anyIPv4.address) {
      return '0.0.0.0';
    }
    if (address.address == InternetAddress.anyIPv6.address) {
      return '[::]';
    }
    return address.address;
  }

  void _handleWebSocket(WebSocket socket) {
    print('FAP Client connected');

    // Notify agent of connection (enables Semantics on first client)
    rpcHandler.agent.onClientConnected();

    // Create a StreamChannel from the WebSocket
    final channel = StreamChannel(socket, socket).cast<String>();

    // Create a JSON-RPC Peer (supports bidirectional)
    final peer = json_rpc.Peer(channel);
    _peers.add(peer);

    // Register methods
    rpcHandler.registerMethods(peer);

    // Listen
    peer
        .listen()
        .then((_) {
          _peers.remove(peer);
          print('FAP Client disconnected');
          // Notify agent of disconnection (disables Semantics when last client leaves)
          rpcHandler.agent.onClientDisconnected();
        })
        .catchError((error) {
          _peers.remove(peer);
          print('FAP Client error: $error');
          // Notify agent of disconnection even on error
          rpcHandler.agent.onClientDisconnected();
        });
  }
}
