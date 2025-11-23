import 'dart:convert';
import 'dart:io';
import 'package:json_rpc_2/json_rpc_2.dart' as json_rpc;

import '../core/actions.dart';
import '../core/selector_parser.dart';
import '../core/semantics_index.dart';
import '../utils/errors.dart';
import '../utils/screenshot.dart';

abstract class FapRpcHandler {
  void registerMethods(json_rpc.Server server);
}

class FapRpcHandlerImpl implements FapRpcHandler {
  final SemanticsIndexer _indexer = SemanticsIndexer();
  final ActionExecutor _executor = ActionExecutor();
  final ErrorMonitor _errorMonitor = ErrorMonitor();
  final ScreenshotUtils _screenshotUtils = ScreenshotUtils();

  FapRpcHandlerImpl() {
    _errorMonitor.start();
  }

  @override
  void registerMethods(json_rpc.Server server) {
    server.registerMethod('ping', () => 'pong');
    
    server.registerMethod('getTree', ([json_rpc.Parameters? params]) {
      _indexer.reindex();
      return _indexer.elements.values.map((e) => e.toJson()).toList();
    });

    server.registerMethod('tap', (json_rpc.Parameters params) async {
      final selectorString = params['selector'].asString;
      final selector = Selector.parse(selectorString);
      
      final elements = _indexer.find(selector);
      if (elements.isEmpty) {
        throw json_rpc.RpcException(100, 'Element not found: $selectorString');
      }
      
      // Tap the first match
      final element = elements.first;
      // print('RPC: Tapping element ${element.id} at ${element.globalRect}');
      final debugInfo = await _executor.tap(element.globalRect);
      
      return {
        'status': 'tapped', 
        'element': element.toJson(),
        'debug': debugInfo
      };
    });

    server.registerMethod('enterText', (json_rpc.Parameters params) async {
      final text = params['text'].asString;
      String? selectorString;
      try {
        selectorString = params['selector'].asString;
      } catch (_) {
        // selector is optional
      }
      
      if (selectorString != null) {
        final selector = Selector.parse(selectorString);
        final elements = _indexer.find(selector);
        if (elements.isEmpty) {
          throw json_rpc.RpcException(100, 'Element not found: $selectorString');
        }
        final element = elements.first;
        await _executor.enterText(element.node, text);
      } else {
        // If no selector, maybe use focused element?
        // For now, require selector or throw.
        throw json_rpc.RpcException(100, 'Selector required for enterText');
      }
      
      return {'status': 'text_entered', 'text': text};
    });

    server.registerMethod('getErrors', (json_rpc.Parameters params) {
      return _errorMonitor.getErrors().map((e) => e.toJson()).toList();
    });

    server.registerMethod('captureScreenshot', (json_rpc.Parameters params) async {
      final bytes = await _screenshotUtils.capture();
      if (bytes == null) {
        throw json_rpc.RpcException(101, 'Screenshot failed');
      }
      return {'base64': base64Encode(bytes)};
    });
  }
}
