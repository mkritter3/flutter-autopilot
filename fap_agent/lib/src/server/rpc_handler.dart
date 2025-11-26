import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/rendering.dart' show SemanticsFlag;
import 'package:flutter/widgets.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as json_rpc;

import '../core/actions.dart';
import '../core/selector_parser.dart';
import '../core/semantics_index.dart';
import '../utils/errors.dart';
import '../utils/screenshot.dart';

import '../../fap_agent.dart';

import '../core/recorder.dart';
import '../core/widget_inspector_bridge.dart';
import '../core/text_input_simulator.dart';
import '../core/flutter_controller.dart';
import '../handlers/rich_text_handler.dart';
import '../handlers/menu_discovery_handler.dart';

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

      // Add cache metadata
      final response = {
        'elements': data,
        'cached': _indexer.lastResponseWasCached,
        'cacheAgeSeconds': _indexer.cacheAgeSeconds,
      };

      return _compressIfNeeded(response);
    });

    peer.registerMethod('getTreeDiff', ([json_rpc.Parameters? params]) {
      _indexer.reindex();
      final data = _indexer.computeDiff();
      return _compressIfNeeded(data);
    });

    peer.registerMethod('getPlaceholders', ([json_rpc.Parameters? params]) {
      final placeholders = _indexer.getPlaceholders();
      final data = placeholders.map((e) => e.toJson()).toList();
      return {
        'count': placeholders.length,
        'placeholders': data,
      };
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
      bool tapFirst = false;
      bool fallbackToFocused = true;

      try {
        selectorString = params['selector'].asString;
      } catch (_) {
        // selector is optional
      }
      try {
        tapFirst = params['tap_first'].asBool;
      } catch (_) {}
      try {
        fallbackToFocused = params['fallback_to_focused'].asBool;
      } catch (_) {}

      String? strategyUsed;

      // Strategy 1: Find by selector
      if (selectorString != null) {
        final selector = Selector.parse(selectorString);
        final elements = _indexer.find(selector);

        if (elements.isNotEmpty) {
          final element = elements.first;
          if (element.isInteractable && element.node != null) {
            if (tapFirst) {
              await _executor.tap(element.globalRect, semanticsNode: element.node);
              await Future.delayed(const Duration(milliseconds: 100));
            }
            await _executor.enterText(element.node!, text);
            strategyUsed = 'selector';
            return {'status': 'text_entered', 'text': text, 'strategy': strategyUsed};
          }
        }
      }

      // Strategy 2: Use focused text field via TextInputSimulator
      if (fallbackToFocused && TextInputSimulator.instance.hasActiveInput) {
        await TextInputSimulator.instance.typeText(text);
        strategyUsed = 'focused_field';
        return {'status': 'text_entered', 'text': text, 'strategy': strategyUsed};
      }

      // All strategies failed - throw diagnostic error
      throw _buildTextInputError(selectorString, text);
    });

    peer.registerMethod('setText', (json_rpc.Parameters params) async {
      final text = params['text'].asString;
      String? selectorString;
      bool fallbackToFocused = true;

      try {
        selectorString = params['selector'].asString;
      } catch (_) {}
      try {
        fallbackToFocused = params['fallback_to_focused'].asBool;
      } catch (_) {}

      String? strategyUsed;

      // Strategy 1: Find by selector
      if (selectorString != null) {
        final elements = _indexer.find(Selector.parse(selectorString));
        if (elements.isNotEmpty) {
          final element = elements.first;
          if (element.isInteractable && element.node != null) {
            await _executor.enterText(element.node!, text);
            strategyUsed = 'selector';
            return {'status': 'text_set', 'text': text, 'strategy': strategyUsed};
          }
        }
      }

      // Strategy 2: Use focused text field via TextInputSimulator
      if (fallbackToFocused && TextInputSimulator.instance.hasActiveInput) {
        await TextInputSimulator.instance.setText(text);
        strategyUsed = 'focused_field';
        return {'status': 'text_set', 'text': text, 'strategy': strategyUsed};
      }

      // All strategies failed - throw diagnostic error
      throw _buildTextInputError(selectorString, text);
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
      if (element.node == null) {
        throw json_rpc.RpcException(
          103,
          'Element has no semantics node (element-based discovery): $selectorString',
        );
      }

      await _executor.setSelection(element.node!, base, extent);
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

    // Widget Inspector RPC Methods
    peer.registerMethod('getWidgetTree', ([json_rpc.Parameters? params]) async {
      try {
        final inspector = WidgetInspectorBridge.instance;
        final widgets = await inspector.getWidgetTree();
        final data = widgets.map((w) => w.toJson()).toList();
        return _compressIfNeeded({'widgets': data, 'count': widgets.length});
      } catch (e) {
        throw json_rpc.RpcException(300, 'Widget inspector error: $e');
      }
    });

    peer.registerMethod('findWidget', (json_rpc.Parameters params) async {
      try {
        final inspector = WidgetInspectorBridge.instance;
        List<FapWidgetRef> widgets = [];
        
        // Support multiple search modes
        if (params.asMap.containsKey('type')) {
          final typeName = params['type'].asString;
          widgets = await inspector.findByType(typeName);
        } else if (params.asMap.containsKey('key')) {
          final keyPattern = params['key'].asString;
          widgets = await inspector.findByKey(keyPattern);
        } else if (params.asMap.containsKey('x') && params.asMap.containsKey('y')) {
          final x = params['x'].asNum.toDouble();
          final y = params['y'].asNum.toDouble();
          final widget = await inspector.findByCoordinates(Offset(x, y));
          if (widget != null) widgets = [widget];
        }
        
        return widgets.map((w) => w.toJson()).toList();
      } catch (e) {
        throw json_rpc.RpcException(300, 'Widget search error: $e');
      }
    });

    // Smart Text Entry (Widget Inspector + Keyboard Simulation)
    peer.registerMethod('smartEnterText', (json_rpc.Parameters params) async {
      try {
        final text = params['text'].asString;
        String? widgetType;
        Offset? coordinates;

        // Check for widgetType parameter
        try {
          widgetType = params['widgetType'].asString;
        } catch (_) {}

        // Check for coordinate parameters
        if (params.asMap.containsKey('x') && params.asMap.containsKey('y')) {
          final x = params['x'].asNum.toDouble();
          final y = params['y'].asNum.toDouble();
          coordinates = Offset(x, y);
        }

        final result = await _executor.smartEnterText(
          text: text,
          widgetType: widgetType,
          coordinates: coordinates,
        );

        return result;
      } catch (e) {
        throw json_rpc.RpcException(300, 'Smart text entry error: $e');
      }
    });

    // Text Input Status (diagnostic)
    peer.registerMethod('getTextInputStatus', ([json_rpc.Parameters? params]) {
      final simulator = TextInputSimulator.instance;
      return {
        'hasActiveInput': simulator.hasActiveInput,
        'clientId': simulator.currentClientId,
        'currentText': simulator.currentText,
      };
    });

    // Type text into currently focused field (requires prior tap)
    peer.registerMethod('typeText', (json_rpc.Parameters params) async {
      try {
        final text = params['text'].asString;
        final simulator = TextInputSimulator.instance;

        if (!simulator.hasActiveInput) {
          return {
            'success': false,
            'error': 'No active text input. Tap a text field first.',
          };
        }

        await simulator.typeText(text);

        return {
          'success': true,
          'text': text,
          'clientId': simulator.currentClientId,
        };
      } catch (e) {
        throw json_rpc.RpcException(300, 'Type text error: $e');
      }
    });

    // Set text directly (replaces existing text)
    peer.registerMethod('setTextDirect', (json_rpc.Parameters params) async {
      try {
        final text = params['text'].asString;
        final simulator = TextInputSimulator.instance;

        if (!simulator.hasActiveInput) {
          return {
            'success': false,
            'error': 'No active text input. Tap a text field first.',
          };
        }

        await simulator.setText(text);

        return {
          'success': true,
          'text': text,
          'clientId': simulator.currentClientId,
        };
      } catch (e) {
        throw json_rpc.RpcException(300, 'Set text error: $e');
      }
    });

    // Clear text in focused field
    peer.registerMethod('clearTextInput', ([json_rpc.Parameters? params]) async {
      try {
        final simulator = TextInputSimulator.instance;

        if (!simulator.hasActiveInput) {
          return {
            'success': false,
            'error': 'No active text input. Tap a text field first.',
          };
        }

        await simulator.clearText();

        return {
          'success': true,
          'clientId': simulator.currentClientId,
        };
      } catch (e) {
        throw json_rpc.RpcException(300, 'Clear text error: $e');
      }
    });

    // Press special keys
    peer.registerMethod('pressKey', (json_rpc.Parameters params) async {
      try {
        final key = params['key'].asString.toLowerCase();
        final simulator = TextInputSimulator.instance;

        if (!simulator.hasActiveInput) {
          return {
            'success': false,
            'error': 'No active text input. Tap a text field first.',
          };
        }

        switch (key) {
          case 'enter':
          case 'return':
            await simulator.pressEnter();
            break;
          case 'backspace':
          case 'delete':
            await simulator.pressBackspace();
            break;
          default:
            return {
              'success': false,
              'error': 'Unknown key: $key. Supported: enter, backspace',
            };
        }

        return {
          'success': true,
          'key': key,
          'clientId': simulator.currentClientId,
        };
      } catch (e) {
        throw json_rpc.RpcException(300, 'Press key error: $e');
      }
    });

    // ========================================
    // FLUTTER CONTROLLER - Direct Widget Access
    // ========================================

    final controller = FlutterController.instance;

    // Find elements by widget type
    peer.registerMethod('findElements', (json_rpc.Parameters params) {
      try {
        final typeName = params['type'].asString;
        final exact = params.asMap.containsKey('exact') ? params['exact'].asBool : false;

        final elements = controller.findByWidgetType(typeName, exact: exact);

        return {
          'count': elements.length,
          'elements': elements.map((e) {
            final bounds = controller.getElementBounds(e);
            return {
              'widgetType': e.widget.runtimeType.toString(),
              'key': e.widget.key?.toString(),
              'isStateful': e is StatefulElement,
              'bounds': bounds != null ? {
                'x': bounds.left,
                'y': bounds.top,
                'w': bounds.width,
                'h': bounds.height,
              } : null,
            };
          }).toList(),
        };
      } catch (e) {
        throw json_rpc.RpcException(400, 'Find elements error: $e');
      }
    });

    // Find elements at position
    peer.registerMethod('findElementsAtPosition', (json_rpc.Parameters params) {
      try {
        final x = params['x'].asNum.toDouble();
        final y = params['y'].asNum.toDouble();

        final elements = controller.findAtPosition(Offset(x, y));

        return {
          'count': elements.length,
          'elements': elements.map((e) {
            final bounds = controller.getElementBounds(e);
            return {
              'widgetType': e.widget.runtimeType.toString(),
              'key': e.widget.key?.toString(),
              'isStateful': e is StatefulElement,
              'bounds': bounds != null ? {
                'x': bounds.left,
                'y': bounds.top,
                'w': bounds.width,
                'h': bounds.height,
              } : null,
            };
          }).toList(),
        };
      } catch (e) {
        throw json_rpc.RpcException(400, 'Find at position error: $e');
      }
    });

    // Find TextEditingControllers
    peer.registerMethod('findTextControllers', ([json_rpc.Parameters? params]) {
      try {
        final controllers = controller.findTextControllers();

        return {
          'count': controllers.length,
          'controllers': controllers.map((c) => {
            'widgetType': c.widgetType,
            'text': c.controller.text,
            'selectionStart': c.controller.selection.start,
            'selectionEnd': c.controller.selection.end,
            'bounds': c.bounds != null ? {
              'x': c.bounds!.left,
              'y': c.bounds!.top,
              'w': c.bounds!.width,
              'h': c.bounds!.height,
            } : null,
          }).toList(),
        };
      } catch (e) {
        throw json_rpc.RpcException(400, 'Find text controllers error: $e');
      }
    });

    // Set text by widget type (direct controller access)
    peer.registerMethod('setTextByType', (json_rpc.Parameters params) async {
      try {
        final widgetType = params['widgetType'].asString;
        final text = params['text'].asString;
        final index = params.asMap.containsKey('index') ? params['index'].asInt : 0;

        return await controller.setTextByWidgetType(widgetType, text, index: index);
      } catch (e) {
        throw json_rpc.RpcException(400, 'Set text error: $e');
      }
    });

    // Execute action on widget
    peer.registerMethod('executeAction', (json_rpc.Parameters params) async {
      try {
        final widgetType = params['widgetType'].asString;
        final action = params['action'].asString;
        final index = params.asMap.containsKey('index') ? params['index'].asInt : 0;

        // Extract action params
        final actionParams = <String, dynamic>{};
        for (final key in params.asMap.keys) {
          if (key != 'widgetType' && key != 'action' && key != 'index') {
            actionParams[key] = params[key].value;
          }
        }

        return await controller.executeAction(
          widgetType,
          action,
          actionParams,
          index: index,
        );
      } catch (e) {
        throw json_rpc.RpcException(400, 'Execute action error: $e');
      }
    });

    // Get widget tree structure
    peer.registerMethod('getElementTree', (json_rpc.Parameters params) {
      try {
        final maxDepth = params.asMap.containsKey('maxDepth')
            ? params['maxDepth'].asInt
            : 5;

        final tree = controller.getWidgetTree(maxDepth: maxDepth);
        return _compressIfNeeded(tree);
      } catch (e) {
        throw json_rpc.RpcException(400, 'Get element tree error: $e');
      }
    });

    // Find States by type
    peer.registerMethod('findStates', (json_rpc.Parameters params) {
      try {
        final stateType = params['stateType'].asString;
        final states = controller.findStatesByType(stateType);

        return {
          'count': states.length,
          'states': states.map((s) => s.toJson()).toList(),
        };
      } catch (e) {
        throw json_rpc.RpcException(400, 'Find states error: $e');
      }
    });

    // Find ScrollControllers
    peer.registerMethod('findScrollControllers', ([json_rpc.Parameters? params]) {
      try {
        final controllers = controller.findScrollControllers();

        return {
          'count': controllers.length,
          'controllers': controllers.map((c) => {
            'widgetType': c.widgetType,
            'offset': c.controller.hasClients ? c.controller.offset : null,
            'bounds': c.bounds != null ? {
              'x': c.bounds!.left,
              'y': c.bounds!.top,
              'w': c.bounds!.width,
              'h': c.bounds!.height,
            } : null,
          }).toList(),
        };
      } catch (e) {
        throw json_rpc.RpcException(400, 'Find scroll controllers error: $e');
      }
    });

    // ========================================
    // RICH TEXT EDITOR SUPPORT
    // ========================================

    final richTextHandler = RichTextHandler.instance;

    // Discover all rich text editors in the widget tree
    peer.registerMethod('discoverRichTextEditors', ([json_rpc.Parameters? params]) {
      try {
        final editors = richTextHandler.discoverEditors();
        return {
          'count': editors.length,
          'editors': editors.map((e) => e.toJson()).toList(),
        };
      } catch (e) {
        throw json_rpc.RpcException(500, 'Rich text discovery error: $e');
      }
    });

    // Insert text into rich text editor at cursor position
    peer.registerMethod('richText.insertText', (json_rpc.Parameters params) async {
      try {
        final editorId = params['editorId'].asInt;
        final text = params['text'].asString;
        return await richTextHandler.insertText(editorId, text);
      } catch (e) {
        throw json_rpc.RpcException(500, 'Rich text insert error: $e');
      }
    });

    // Get document content from rich text editor
    peer.registerMethod('richText.getContent', (json_rpc.Parameters params) async {
      try {
        final editorId = params['editorId'].asInt;
        return await richTextHandler.getContent(editorId);
      } catch (e) {
        throw json_rpc.RpcException(500, 'Rich text content error: $e');
      }
    });

    // Get selection state from rich text editor
    peer.registerMethod('richText.getSelection', (json_rpc.Parameters params) async {
      try {
        final editorId = params['editorId'].asInt;
        return await richTextHandler.getSelection(editorId);
      } catch (e) {
        throw json_rpc.RpcException(500, 'Rich text selection error: $e');
      }
    });

    // Apply formatting to rich text editor selection
    peer.registerMethod('richText.applyFormat', (json_rpc.Parameters params) async {
      try {
        final editorId = params['editorId'].asInt;
        final format = params['format'].asString;
        return await richTextHandler.applyFormat(editorId, format);
      } catch (e) {
        throw json_rpc.RpcException(500, 'Rich text format error: $e');
      }
    });

    // Clear rich text editor cache
    peer.registerMethod('richText.clearCache', ([json_rpc.Parameters? params]) {
      richTextHandler.clearCache();
      return {'status': 'cache_cleared'};
    });

    // Enter text via IME delta simulation (for rich editors)
    peer.registerMethod('enterRichText', (json_rpc.Parameters params) async {
      try {
        final text = params['text'].asString;
        final useDelta = params.asMap.containsKey('useDelta')
            ? params['useDelta'].asBool
            : true;
        final simulator = TextInputSimulator.instance;

        if (!simulator.hasActiveInput) {
          return {
            'success': false,
            'error': 'No active text input. Tap the rich text editor first.',
            'hint': 'Focus the editor by tapping it, then call enterRichText.',
          };
        }

        if (useDelta) {
          await simulator.sendTextDelta(text);
        } else {
          await simulator.typeText(text);
        }

        return {
          'success': true,
          'text': text,
          'method': useDelta ? 'delta' : 'typing',
          'clientId': simulator.currentClientId,
        };
      } catch (e) {
        throw json_rpc.RpcException(500, 'Enter rich text error: $e');
      }
    });

    // Replace text range via IME delta simulation
    peer.registerMethod('replaceRichText', (json_rpc.Parameters params) async {
      try {
        final newText = params['text'].asString;
        final start = params['start'].asInt;
        final end = params['end'].asInt;
        final simulator = TextInputSimulator.instance;

        if (!simulator.hasActiveInput) {
          return {
            'success': false,
            'error': 'No active text input. Tap the rich text editor first.',
          };
        }

        await simulator.sendReplacementDelta(newText, start, end);

        return {
          'success': true,
          'text': newText,
          'range': {'start': start, 'end': end},
          'clientId': simulator.currentClientId,
        };
      } catch (e) {
        throw json_rpc.RpcException(500, 'Replace rich text error: $e');
      }
    });

    // ========================================
    // MENU / OVERLAY / DRAWER DISCOVERY
    // ========================================

    final menuHandler = MenuDiscoveryHandler.instance;

    // Get current overlay state
    peer.registerMethod('getOverlayState', ([json_rpc.Parameters? params]) {
      try {
        final state = menuHandler.getCurrentOverlayState();
        return state.toJson();
      } catch (e) {
        throw json_rpc.RpcException(500, 'Get overlay state error: $e');
      }
    });

    // Wait for overlay to appear
    peer.registerMethod('waitForOverlay', (json_rpc.Parameters params) async {
      try {
        final timeoutMs = params.asMap.containsKey('timeoutMs')
            ? params['timeoutMs'].asInt
            : 5000;
        final pollIntervalMs = params.asMap.containsKey('pollIntervalMs')
            ? params['pollIntervalMs'].asInt
            : 50;

        final result = await menuHandler.waitForOverlay(
          timeoutMs: timeoutMs,
          pollIntervalMs: pollIntervalMs,
        );

        return result.toJson();
      } catch (e) {
        throw json_rpc.RpcException(500, 'Wait for overlay error: $e');
      }
    });

    // Get only overlay elements from the tree
    peer.registerMethod('getOverlayElements', ([json_rpc.Parameters? params]) {
      try {
        _indexer.reindex();
        final overlayElements = _indexer.elements.values
            .where((e) => e.isOverlayElement)
            .map((e) => e.toJson())
            .toList();
        return {
          'count': overlayElements.length,
          'elements': overlayElements,
        };
      } catch (e) {
        throw json_rpc.RpcException(500, 'Get overlay elements error: $e');
      }
    });

    // Get drawer state
    peer.registerMethod('getDrawerState', ([json_rpc.Parameters? params]) {
      try {
        return controller.getDrawerState();
      } catch (e) {
        throw json_rpc.RpcException(500, 'Get drawer state error: $e');
      }
    });

    // Discover menu triggers (hamburger icons, dropdown buttons, etc.)
    peer.registerMethod('discoverMenuTriggers', ([json_rpc.Parameters? params]) {
      try {
        final triggers = menuHandler.discoverMenuTriggers();
        return {
          'count': triggers.length,
          'triggers': triggers.map((t) => t.toJson()).toList(),
        };
      } catch (e) {
        throw json_rpc.RpcException(500, 'Discover menu triggers error: $e');
      }
    });

    // Open drawer programmatically
    peer.registerMethod('openDrawer', (json_rpc.Parameters params) async {
      try {
        final isEndDrawer = params.asMap.containsKey('endDrawer')
            ? params['endDrawer'].asBool
            : false;
        return menuHandler.openDrawer(endDrawer: isEndDrawer);
      } catch (e) {
        throw json_rpc.RpcException(500, 'Open drawer error: $e');
      }
    });

    // Close drawer programmatically
    peer.registerMethod('closeDrawer', ([json_rpc.Parameters? params]) async {
      try {
        return await menuHandler.closeDrawer();
      } catch (e) {
        throw json_rpc.RpcException(500, 'Close drawer error: $e');
      }
    });

    // Find rich text editors via FlutterController
    peer.registerMethod('findRichTextEditors', ([json_rpc.Parameters? params]) {
      try {
        return {
          'editors': controller.findRichTextEditors(),
        };
      } catch (e) {
        throw json_rpc.RpcException(500, 'Find rich text editors error: $e');
      }
    });

    // Get elements by UI category
    peer.registerMethod('getElementsByCategory', (json_rpc.Parameters params) {
      try {
        final category = params['category'].asString;
        _indexer.reindex();
        final elements = _indexer.elements.values
            .where((e) => e.uiCategory == category)
            .map((e) => e.toJson())
            .toList();
        return {
          'category': category,
          'count': elements.length,
          'elements': elements,
        };
      } catch (e) {
        throw json_rpc.RpcException(500, 'Get by category error: $e');
      }
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

  /// Build diagnostic error for text input failures
  json_rpc.RpcException _buildTextInputError(String? selector, String text) {
    // Find all available text fields for diagnostics
    final textFields = _indexer.elements.values
        .where((e) => e.node != null && e.node!.hasFlag(SemanticsFlag.isTextField))
        .take(5)
        .map((e) {
          final nodeLabel = e.node?.label ?? '';
          final label = nodeLabel.isNotEmpty ? nodeLabel : (e.label ?? '(no label)');
          // Truncate long labels that have newlines
          final displayLabel = label.length > 50
              ? '${label.substring(0, 50).replaceAll('\n', '\\n')}...'
              : label.replaceAll('\n', '\\n');
          return '  - "$displayLabel" [key=${e.key ?? 'none'}, type=${e.type ?? 'unknown'}]';
        })
        .join('\n');

    final hasFocusedField = TextInputSimulator.instance.hasActiveInput;

    return json_rpc.RpcException(
      100,
      'Text input failed.\n'
      'Selector: ${selector ?? "(none)"}\n'
      'Text: "${text.length > 20 ? text.substring(0, 20) + '...' : text}"\n'
      'Has focused field: $hasFocusedField\n'
      'Available text fields:\n${textFields.isEmpty ? '  (none found)' : textFields}\n'
      'Tips:\n'
      '  - Labels are now auto-normalized (multiline labels work)\n'
      '  - Partial matches work: label="Project" matches "Project Title\\nSubtext"\n'
      '  - Try tap_first=true if field needs focus first\n'
      '  - Try tapping the field first, then call enterText without selector',
    );
  }
}
