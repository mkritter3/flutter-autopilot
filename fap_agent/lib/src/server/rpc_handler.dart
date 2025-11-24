import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:json_rpc_2/json_rpc_2.dart' as json_rpc;

import '../core/actions.dart';
import '../core/selector_parser.dart';
import '../core/semantics_index.dart';
import '../utils/errors.dart';
import '../utils/screenshot.dart';

import '../../fap_agent.dart';

import '../core/recorder.dart';

abstract class FapRpcHandler {
  FapAgent get agent;
  void registerMethods(json_rpc.Peer peer);
}

class FapRpcHandlerImpl implements FapRpcHandler {
  final FapAgent agent;
  final SemanticsIndexer _indexer;
  final Recorder _recorder;
  final ActionExecutor _executor = ActionExecutor();
  final ErrorMonitor _errorMonitor = ErrorMonitor();
  final ScreenshotUtils _screenshotUtils = ScreenshotUtils();

  FapRpcHandlerImpl({
    required this.agent,
    required SemanticsIndexer indexer,
    required Recorder recorder,
  }) : _indexer = indexer,
       _recorder = recorder {
    _errorMonitor.start();
  }

  @override
  void registerMethods(json_rpc.Peer peer) {
    peer.registerMethod('ping', () => 'pong');

    peer.registerMethod('startRecording', (json_rpc.Parameters params) {
      _recorder.start();
      return {'status': 'recording_started'};
    });

    peer.registerMethod('stopRecording', (json_rpc.Parameters params) {
      _recorder.stop();
      return {'status': 'recording_stopped'};
    });

    peer.registerMethod('getTree', ([json_rpc.Parameters? params]) {
      _indexer.reindex();
      final data = _indexer.elements.values.map((e) => e.toJson()).toList();
      return _compressIfNeeded(data);
    });

    peer.registerMethod('getTreeDiff', ([json_rpc.Parameters? params]) {
      _indexer.reindex();
      final data = _indexer.computeDiff();
      return _compressIfNeeded(data);
    });

    peer.registerMethod('getRoute', ([json_rpc.Parameters? params]) {
      return agent.navigatorObserver.currentRoute;
    });

    peer.registerMethod('tap', (json_rpc.Parameters params) async {
      final selectorString = params['selector'].asString;
      final selector = Selector.parse(selectorString);

      final elements = _indexer.find(selector);
      if (elements.isEmpty) {
        throw json_rpc.RpcException(100, 'Element not found: $selectorString');
      }

      final element = elements.first;
      if (!element.isInteractable) {
        throw json_rpc.RpcException(
          102,
          'Element is not interactable: $selectorString',
        );
      }

      final debugInfo = await _executor.tap(
        element.globalRect,
        semanticsNode: element.node,
      );

      return {
        'status': 'tapped',
        'element': element.toJson(),
        'debug': debugInfo,
      };
    });

    peer.registerMethod('tapAt', (json_rpc.Parameters params) async {
      final x = params['x'].asNum.toDouble();
      final y = params['y'].asNum.toDouble();

      return await _executor.tapAt(Offset(x, y));
    });

    peer.registerMethod('enterText', (json_rpc.Parameters params) async {
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
          throw json_rpc.RpcException(
            100,
            'Element not found: $selectorString',
          );
        }
        final element = elements.first;
        if (!element.isInteractable) {
          throw json_rpc.RpcException(
            102,
            'Element is not interactable: $selectorString',
          );
        }
        await _executor.enterText(element.node, text);
      } else {
        throw json_rpc.RpcException(100, 'Selector required for enterText');
      }

      return {'status': 'text_entered', 'text': text};
    });

    peer.registerMethod('setText', (json_rpc.Parameters params) async {
      final text = params['text'].asString;
      final selectorString = params['selector'].asString;

      final elements = _indexer.find(Selector.parse(selectorString));
      if (elements.isEmpty)
        throw json_rpc.RpcException(100, 'Element not found: $selectorString');

      final element = elements.first;
      if (!element.isInteractable) {
        throw json_rpc.RpcException(
          102,
          'Element is not interactable: $selectorString',
        );
      }

      await _executor.enterText(
        element.node,
        text,
      ); // enterText uses SemanticsAction.setText which replaces text
      return {'status': 'text_set', 'text': text};
    });

    peer.registerMethod('setSelection', (json_rpc.Parameters params) async {
      final selectorString = params['selector'].asString;
      final base = params['base'].asInt;
      final extent = params['extent'].asInt;

      final elements = _indexer.find(Selector.parse(selectorString));
      if (elements.isEmpty)
        throw json_rpc.RpcException(100, 'Element not found: $selectorString');

      final element = elements.first;
      if (!element.isInteractable) {
        throw json_rpc.RpcException(
          102,
          'Element is not interactable: $selectorString',
        );
      }

      await _executor.setSelection(element.node, base, extent);
      return {'status': 'selection_set', 'base': base, 'extent': extent};
    });

    peer.registerMethod('getErrors', (json_rpc.Parameters params) {
      final frameworkErrors = _errorMonitor
          .getErrors()
          .map((e) => e.toJson())
          .toList();
      final asyncErrors = agent
          .getErrors()
          .map((e) => {'message': e, 'type': 'async'})
          .toList();
      return [...frameworkErrors, ...asyncErrors];
    });

    peer.registerMethod('getPerformanceMetrics', (json_rpc.Parameters params) {
      return agent.getPerformanceMetrics();
    });

    peer.registerMethod('getLogs', (json_rpc.Parameters params) {
      return agent.getLogs();
    });

    peer.registerMethod('captureScreenshot', (
      json_rpc.Parameters params,
    ) async {
      final bytes = await _screenshotUtils.capture();
      if (bytes == null) {
        throw json_rpc.RpcException(101, 'Screenshot failed');
      }
      return {'base64': base64Encode(bytes)};
    });

    peer.registerMethod('scroll', (json_rpc.Parameters params) async {
      final selectorString = params['selector'].asString;
      final dx = params['dx'].asNum.toDouble();
      final dy = params['dy'].asNum.toDouble();
      final durationMs = params['durationMs'].asIntOr(300);

      final elements = _indexer.find(Selector.parse(selectorString));
      if (elements.isEmpty)
        throw json_rpc.RpcException(100, 'Element not found: $selectorString');

      final element = elements.first;
      if (!element.isInteractable) {
        throw json_rpc.RpcException(
          102,
          'Element is not interactable: $selectorString',
        );
      }

      return await _executor.scroll(
        element.globalRect,
        dx,
        dy,
        duration: Duration(milliseconds: durationMs),
      );
    });

    peer.registerMethod('drag', (json_rpc.Parameters params) async {
      final selectorString = params['selector'].asString;
      final targetSelectorString = params['targetSelector'].asStringOr('');
      final dx = params['dx'].asNumOr(0).toDouble();
      final dy = params['dy'].asNumOr(0).toDouble();
      final durationMs = params['durationMs'].asIntOr(300);

      final elements = _indexer.find(Selector.parse(selectorString));
      if (elements.isEmpty)
        throw json_rpc.RpcException(100, 'Element not found: $selectorString');

      final element = elements.first;
      if (!element.isInteractable) {
        throw json_rpc.RpcException(
          102,
          'Element is not interactable: $selectorString',
        );
      }

      final start = element.globalRect.center;

      Offset end;
      if (targetSelectorString.isNotEmpty) {
        final targets = _indexer.find(Selector.parse(targetSelectorString));
        if (targets.isEmpty)
          throw json_rpc.RpcException(
            100,
            'Target element not found: $targetSelectorString',
          );

        final target = targets.first;
        if (!target.isInteractable) {
          throw json_rpc.RpcException(
            102,
            'Target element is not interactable: $targetSelectorString',
          );
        }
        end = target.globalRect.center;
      } else {
        end = start.translate(dx, dy);
      }

      return await _executor.drag(
        start,
        end,
        duration: Duration(milliseconds: durationMs),
      );
    });

    peer.registerMethod('longPress', (json_rpc.Parameters params) async {
      final selectorString = params['selector'].asString;
      final durationMs = params['durationMs'].asIntOr(800);

      final elements = _indexer.find(Selector.parse(selectorString));
      if (elements.isEmpty)
        throw json_rpc.RpcException(100, 'Element not found: $selectorString');

      final element = elements.first;
      if (!element.isInteractable) {
        throw json_rpc.RpcException(
          102,
          'Element is not interactable: $selectorString',
        );
      }

      return await _executor.longPress(
        element.globalRect,
        duration: Duration(milliseconds: durationMs),
      );
    });

    peer.registerMethod('doubleTap', (json_rpc.Parameters params) async {
      final selectorString = params['selector'].asString;

      final elements = _indexer.find(Selector.parse(selectorString));
      if (elements.isEmpty)
        throw json_rpc.RpcException(100, 'Element not found: $selectorString');

      final element = elements.first;
      if (!element.isInteractable) {
        throw json_rpc.RpcException(
          102,
          'Element is not interactable: $selectorString',
        );
      }

      return await _executor.doubleTap(
        element.globalRect,
        semanticsNode: element.node,
      );
    });
  }

  dynamic _compressIfNeeded(Object data) {
    final jsonString = jsonEncode(data);
    final bytes = utf8.encode(jsonString);

    // Compress if larger than 1KB
    if (bytes.length > 1024) {
      final compressed = GZipCodec().encode(bytes);
      final base64 = base64Encode(compressed);
      return {'compressed': true, 'data': base64};
    }

    return data;
  }
}
