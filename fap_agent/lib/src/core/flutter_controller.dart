import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Universal Flutter Controller
///
/// Provides deep access to Flutter's internals for complete app control:
/// - Element tree traversal
/// - State object access
/// - Controller access (TextEditingController, ScrollController, etc.)
/// - Method invocation on any widget
/// - Property reading/modification
class FlutterController {
  static final FlutterController instance = FlutterController._();
  FlutterController._();

  /// Get the root element of the widget tree
  Element? get rootElement {
    try {
      return WidgetsBinding.instance.rootElement;
    } catch (e) {
      debugPrint('FlutterController: Cannot get root element: $e');
      return null;
    }
  }

  /// Find all elements matching a predicate
  List<Element> findElements(bool Function(Element) predicate) {
    final results = <Element>[];
    final root = rootElement;
    if (root == null) return results;

    void visit(Element element) {
      if (predicate(element)) {
        results.add(element);
      }
      element.visitChildren(visit);
    }

    visit(root);
    return results;
  }

  /// Find elements by widget type name (supports partial matching)
  List<Element> findByWidgetType(String typeName, {bool exact = false}) {
    return findElements((element) {
      final widgetType = element.widget.runtimeType.toString();
      if (exact) {
        return widgetType == typeName;
      }
      return widgetType.contains(typeName);
    });
  }

  /// Find elements by widget key
  List<Element> findByKey(String keyPattern) {
    return findElements((element) {
      final key = element.widget.key;
      if (key == null) return false;
      return key.toString().contains(keyPattern);
    });
  }

  /// Find elements at a specific position
  List<Element> findAtPosition(Offset position) {
    return findElements((element) {
      final renderObject = element.renderObject;
      if (renderObject is RenderBox && renderObject.hasSize) {
        try {
          final transform = renderObject.getTransformTo(null);
          final bounds = MatrixUtils.transformRect(
            transform,
            Offset.zero & renderObject.size,
          );
          return bounds.contains(position);
        } catch (e) {
          return false;
        }
      }
      return false;
    });
  }

  /// Get State object from a StatefulElement
  State? getState(Element element) {
    if (element is StatefulElement) {
      return element.state;
    }
    return null;
  }

  /// Find State objects by state type name
  List<StateInfo> findStatesByType(String stateTypeName) {
    final results = <StateInfo>[];

    findElements((element) {
      if (element is StatefulElement) {
        final state = element.state;
        final stateType = state.runtimeType.toString();
        if (stateType.contains(stateTypeName)) {
          results.add(StateInfo(
            element: element,
            state: state,
            stateType: stateType,
            widgetType: element.widget.runtimeType.toString(),
          ));
        }
      }
      return false; // Don't collect, just iterate
    });

    return results;
  }

  /// Get a property value from any object using reflection-like access
  /// Uses Dart's noSuchMethod for dynamic property access
  dynamic getProperty(dynamic object, String propertyName) {
    try {
      // Use dynamic dispatch to access properties
      // This works because Dart allows dynamic member access
      final dynamic obj = object;

      // Common controller properties
      switch (propertyName) {
        case 'text':
          if (obj is TextEditingController) return obj.text;
          break;
        case 'value':
          if (obj is ValueNotifier) return obj.value;
          if (obj is TextEditingController) return obj.value;
          break;
        case 'selection':
          if (obj is TextEditingController) return obj.selection;
          break;
        case 'offset':
          if (obj is ScrollController) return obj.offset;
          break;
        case 'position':
          if (obj is ScrollController) return obj.position;
          break;
      }

      // Try direct dynamic access
      return (object as dynamic)[propertyName];
    } catch (e) {
      debugPrint('FlutterController: Cannot get property $propertyName: $e');
      return null;
    }
  }

  /// Set a property value on any object
  bool setProperty(dynamic object, String propertyName, dynamic value) {
    try {
      // Common controller properties
      switch (propertyName) {
        case 'text':
          if (object is TextEditingController) {
            object.text = value as String;
            return true;
          }
          break;
        case 'value':
          if (object is ValueNotifier) {
            object.value = value;
            return true;
          }
          break;
      }

      // Try dynamic access
      (object as dynamic)[propertyName] = value;
      return true;
    } catch (e) {
      debugPrint('FlutterController: Cannot set property $propertyName: $e');
      return false;
    }
  }

  /// Find TextEditingController instances in the tree
  List<ControllerInfo<TextEditingController>> findTextControllers() {
    final results = <ControllerInfo<TextEditingController>>[];

    findElements((element) {
      // Check for TextField
      if (element.widget.runtimeType.toString().contains('TextField')) {
        _extractTextController(element, results);
      }
      // Check for EditableText
      if (element.widget.runtimeType.toString().contains('EditableText')) {
        _extractTextController(element, results);
      }
      return false;
    });

    return results;
  }

  void _extractTextController(
    Element element,
    List<ControllerInfo<TextEditingController>> results,
  ) {
    try {
      final widget = element.widget;
      final dynamic dynWidget = widget;

      // Try to get controller property
      TextEditingController? controller;

      try {
        controller = dynWidget.controller as TextEditingController?;
      } catch (_) {}

      if (controller != null) {
        results.add(ControllerInfo(
          controller: controller,
          element: element,
          widgetType: widget.runtimeType.toString(),
          bounds: getElementBounds(element),
        ));
      }
    } catch (e) {
      // Ignore
    }
  }

  /// Find ScrollController instances
  List<ControllerInfo<ScrollController>> findScrollControllers() {
    final results = <ControllerInfo<ScrollController>>[];

    findElements((element) {
      final widget = element.widget;
      final widgetType = widget.runtimeType.toString();

      if (widgetType.contains('Scrollable') ||
          widgetType.contains('ListView') ||
          widgetType.contains('ScrollView') ||
          widgetType.contains('CustomScrollView')) {
        try {
          final dynamic dynWidget = widget;
          ScrollController? controller;

          try {
            controller = dynWidget.controller as ScrollController?;
          } catch (_) {}

          if (controller != null) {
            results.add(ControllerInfo(
              controller: controller,
              element: element,
              widgetType: widgetType,
              bounds: getElementBounds(element),
            ));
          }
        } catch (e) {
          // Ignore
        }
      }
      return false;
    });

    return results;
  }

  /// Get bounds of an element
  Rect? getElementBounds(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is RenderBox && renderObject.hasSize) {
      try {
        final transform = renderObject.getTransformTo(null);
        return MatrixUtils.transformRect(
          transform,
          Offset.zero & renderObject.size,
        );
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /// Invoke a method on an object
  Future<dynamic> invokeMethod(
    dynamic object,
    String methodName,
    List<dynamic> args,
  ) async {
    try {
      // Common methods on controllers
      switch (methodName) {
        // TextEditingController methods
        case 'clear':
          if (object is TextEditingController) {
            object.clear();
            return {'success': true};
          }
          break;

        case 'selectAll':
          if (object is TextEditingController) {
            object.selection = TextSelection(
              baseOffset: 0,
              extentOffset: object.text.length,
            );
            return {'success': true};
          }
          break;

        // ScrollController methods
        case 'jumpTo':
          if (object is ScrollController && args.isNotEmpty) {
            object.jumpTo(args[0] as double);
            return {'success': true};
          }
          break;

        case 'animateTo':
          if (object is ScrollController && args.isNotEmpty) {
            await object.animateTo(
              args[0] as double,
              duration: Duration(milliseconds: args.length > 1 ? args[1] as int : 300),
              curve: Curves.easeInOut,
            );
            return {'success': true};
          }
          break;
      }

      // Try dynamic invocation using Function.apply
      // This is limited but works for some cases
      debugPrint('FlutterController: Method $methodName not directly supported');
      return {'success': false, 'error': 'Method not supported'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Set text in a TextEditingController by finding it in the tree
  Future<Map<String, dynamic>> setTextByWidgetType(
    String widgetType,
    String text, {
    int index = 0,
  }) async {
    final controllers = findTextControllers();
    final matching = controllers.where(
      (c) => c.widgetType.contains(widgetType),
    ).toList();

    if (matching.isEmpty) {
      return {
        'success': false,
        'error': 'No TextEditingController found for widget type: $widgetType',
        'foundControllers': controllers.map((c) => c.widgetType).toList(),
      };
    }

    if (index >= matching.length) {
      return {
        'success': false,
        'error': 'Index $index out of range. Found ${matching.length} controllers.',
      };
    }

    final controller = matching[index].controller;
    controller.text = text;

    return {
      'success': true,
      'widgetType': matching[index].widgetType,
      'text': text,
      'index': index,
    };
  }

  /// Get full widget tree as JSON
  Map<String, dynamic> getWidgetTree({int maxDepth = 10}) {
    final root = rootElement;
    if (root == null) {
      return {'error': 'No root element'};
    }

    Map<String, dynamic> buildNode(Element element, int depth) {
      if (depth > maxDepth) {
        return {'truncated': true};
      }

      final widget = element.widget;
      final children = <Map<String, dynamic>>[];

      element.visitChildren((child) {
        children.add(buildNode(child, depth + 1));
      });

      final node = <String, dynamic>{
        'type': widget.runtimeType.toString(),
        'key': widget.key?.toString(),
      };

      // Add state info for StatefulWidgets
      if (element is StatefulElement) {
        node['stateType'] = element.state.runtimeType.toString();
      }

      // Add bounds if available
      final bounds = getElementBounds(element);
      if (bounds != null) {
        node['bounds'] = {
          'x': bounds.left,
          'y': bounds.top,
          'w': bounds.width,
          'h': bounds.height,
        };
      }

      if (children.isNotEmpty) {
        node['children'] = children;
      }

      return node;
    }

    return buildNode(root, 0);
  }

  /// Execute a custom action on a widget by type
  /// This is the most powerful method - it finds a widget and executes
  /// a predefined action based on the widget type
  Future<Map<String, dynamic>> executeAction(
    String widgetType,
    String action,
    Map<String, dynamic> params, {
    int index = 0,
  }) async {
    final elements = findByWidgetType(widgetType);

    if (elements.isEmpty) {
      return {
        'success': false,
        'error': 'Widget type $widgetType not found',
      };
    }

    if (index >= elements.length) {
      return {
        'success': false,
        'error': 'Index $index out of range. Found ${elements.length} widgets.',
      };
    }

    final element = elements[index];
    final widget = element.widget;

    // Handle different widget types
    final type = widget.runtimeType.toString();

    // ===== SuperEditor handling =====
    if (type.contains('SuperEditor')) {
      return await _handleSuperEditorAction(element, action, params);
    }

    // ===== TextField handling =====
    if (type.contains('TextField') || type.contains('TextFormField')) {
      return await _handleTextFieldAction(element, action, params);
    }

    // ===== ListView/ScrollView handling =====
    if (type.contains('ListView') || type.contains('ScrollView')) {
      return await _handleScrollAction(element, action, params);
    }

    // ===== Generic StatefulWidget handling =====
    if (element is StatefulElement) {
      return await _handleStatefulAction(element, action, params);
    }

    return {
      'success': false,
      'error': 'No action handler for widget type: $type',
      'availableTypes': ['SuperEditor', 'TextField', 'ListView', 'ScrollView'],
    };
  }

  /// Handle SuperEditor-specific actions
  Future<Map<String, dynamic>> _handleSuperEditorAction(
    Element element,
    String action,
    Map<String, dynamic> params,
  ) async {
    try {
      // SuperEditor exposes an Editor via its state or as a property
      // We need to find the Editor to execute commands

      final widget = element.widget;
      final dynamic dynWidget = widget;

      // Try to get the editor property
      dynamic editor;
      try {
        editor = dynWidget.editor;
      } catch (_) {}

      // Try to get document
      dynamic document;
      try {
        document = dynWidget.document;
      } catch (_) {}

      switch (action) {
        case 'setText':
        case 'insertText':
          final text = params['text'] as String?;
          if (text == null) {
            return {'success': false, 'error': 'Missing text parameter'};
          }

          // For SuperEditor, we need to work with the Document
          if (document != null) {
            // This is app-specific - SuperEditor's document API varies
            debugPrint('FlutterController: Found SuperEditor document: ${document.runtimeType}');

            // Try to insert text at current selection
            if (editor != null) {
              try {
                // SuperEditor uses Commands pattern
                // We need to execute an InsertTextCommand or similar
                final dynamic dynEditor = editor;

                // Try common SuperEditor command patterns
                // 1. Check if there's an execute method
                try {
                  // SuperEditor typically has: editor.execute([command])
                  debugPrint('FlutterController: Editor type: ${dynEditor.runtimeType}');

                  // For now, return info about what we found
                  return {
                    'success': false,
                    'error': 'SuperEditor text insertion requires app-specific integration',
                    'info': {
                      'editorType': dynEditor.runtimeType.toString(),
                      'documentType': document.runtimeType.toString(),
                      'hint': 'SuperEditor uses a Command pattern. Integrate with the app\'s specific Editor instance.',
                    },
                  };
                } catch (e) {
                  return {'success': false, 'error': 'Editor execute failed: $e'};
                }
              } catch (e) {
                return {'success': false, 'error': 'Editor access failed: $e'};
              }
            }
          }

          return {
            'success': false,
            'error': 'Could not find SuperEditor editor/document',
            'hasEditor': editor != null,
            'hasDocument': document != null,
          };

        case 'getContent':
          if (document != null) {
            try {
              // Try to serialize the document
              return {
                'success': true,
                'documentType': document.runtimeType.toString(),
                // Content extraction is app-specific
              };
            } catch (e) {
              return {'success': false, 'error': 'Document access failed: $e'};
            }
          }
          return {'success': false, 'error': 'No document found'};

        default:
          return {
            'success': false,
            'error': 'Unknown SuperEditor action: $action',
            'availableActions': ['setText', 'insertText', 'getContent'],
          };
      }
    } catch (e) {
      return {'success': false, 'error': 'SuperEditor error: $e'};
    }
  }

  /// Handle TextField-specific actions
  Future<Map<String, dynamic>> _handleTextFieldAction(
    Element element,
    String action,
    Map<String, dynamic> params,
  ) async {
    try {
      final widget = element.widget;
      final dynamic dynWidget = widget;

      TextEditingController? controller;
      try {
        controller = dynWidget.controller as TextEditingController?;
      } catch (_) {}

      if (controller == null) {
        // TextField might create its own controller internally
        // Try to find it in the element tree below this widget
        final textControllers = <TextEditingController>[];
        element.visitChildren((child) {
          if (child is StatefulElement) {
            final state = child.state;
            try {
              final dynamic dynState = state;
              final ctrl = dynState.controller as TextEditingController?;
              if (ctrl != null) textControllers.add(ctrl);
            } catch (_) {}
          }
        });

        if (textControllers.isNotEmpty) {
          controller = textControllers.first;
        }
      }

      if (controller == null) {
        return {'success': false, 'error': 'No TextEditingController found'};
      }

      switch (action) {
        case 'setText':
          final text = params['text'] as String?;
          if (text == null) {
            return {'success': false, 'error': 'Missing text parameter'};
          }
          controller.text = text;
          return {'success': true, 'text': text};

        case 'getText':
          return {'success': true, 'text': controller.text};

        case 'clear':
          controller.clear();
          return {'success': true};

        case 'appendText':
          final text = params['text'] as String?;
          if (text == null) {
            return {'success': false, 'error': 'Missing text parameter'};
          }
          controller.text += text;
          return {'success': true, 'text': controller.text};

        case 'setSelection':
          final start = params['start'] as int?;
          final end = params['end'] as int?;
          if (start == null || end == null) {
            return {'success': false, 'error': 'Missing start/end parameters'};
          }
          controller.selection = TextSelection(
            baseOffset: start,
            extentOffset: end,
          );
          return {'success': true};

        default:
          return {
            'success': false,
            'error': 'Unknown TextField action: $action',
            'availableActions': ['setText', 'getText', 'clear', 'appendText', 'setSelection'],
          };
      }
    } catch (e) {
      return {'success': false, 'error': 'TextField error: $e'};
    }
  }

  /// Handle Scroll-specific actions
  Future<Map<String, dynamic>> _handleScrollAction(
    Element element,
    String action,
    Map<String, dynamic> params,
  ) async {
    try {
      // Find ScrollController
      ScrollController? controller;

      element.visitChildren((child) {
        if (child.widget.runtimeType.toString().contains('Scrollable')) {
          try {
            final dynamic scrollable = child.widget;
            controller = scrollable.controller as ScrollController?;
          } catch (_) {}
        }
      });

      if (controller == null) {
        return {'success': false, 'error': 'No ScrollController found'};
      }

      switch (action) {
        case 'scrollTo':
          final offset = params['offset'] as double?;
          if (offset == null) {
            return {'success': false, 'error': 'Missing offset parameter'};
          }
          controller!.jumpTo(offset);
          return {'success': true, 'offset': offset};

        case 'scrollBy':
          final delta = params['delta'] as double?;
          if (delta == null) {
            return {'success': false, 'error': 'Missing delta parameter'};
          }
          final newOffset = controller!.offset + delta;
          controller!.jumpTo(newOffset);
          return {'success': true, 'offset': newOffset};

        case 'getPosition':
          return {
            'success': true,
            'offset': controller!.offset,
            'maxExtent': controller!.position.maxScrollExtent,
            'minExtent': controller!.position.minScrollExtent,
          };

        default:
          return {
            'success': false,
            'error': 'Unknown scroll action: $action',
            'availableActions': ['scrollTo', 'scrollBy', 'getPosition'],
          };
      }
    } catch (e) {
      return {'success': false, 'error': 'Scroll error: $e'};
    }
  }

  /// Handle generic StatefulWidget actions
  Future<Map<String, dynamic>> _handleStatefulAction(
    StatefulElement element,
    String action,
    Map<String, dynamic> params,
  ) async {
    final state = element.state;

    switch (action) {
      case 'getStateInfo':
        return {
          'success': true,
          'stateType': state.runtimeType.toString(),
          'widgetType': element.widget.runtimeType.toString(),
          'mounted': state.mounted,
        };

      case 'rebuild':
        // Force a rebuild by calling setState
        try {
          // This is a bit hacky but works
          (state as dynamic).setState(() {});
          return {'success': true};
        } catch (e) {
          return {'success': false, 'error': 'Cannot call setState: $e'};
        }

      default:
        return {
          'success': false,
          'error': 'Unknown stateful action: $action',
          'availableActions': ['getStateInfo', 'rebuild'],
        };
    }
  }
}

/// Information about a found State object
class StateInfo {
  final StatefulElement element;
  final State state;
  final String stateType;
  final String widgetType;

  StateInfo({
    required this.element,
    required this.state,
    required this.stateType,
    required this.widgetType,
  });

  Map<String, dynamic> toJson() => {
    'stateType': stateType,
    'widgetType': widgetType,
    'mounted': state.mounted,
  };
}

/// Information about a found Controller
class ControllerInfo<T> {
  final T controller;
  final Element element;
  final String widgetType;
  final Rect? bounds;

  ControllerInfo({
    required this.controller,
    required this.element,
    required this.widgetType,
    this.bounds,
  });

  Map<String, dynamic> toJson() => {
    'controllerType': controller.runtimeType.toString(),
    'widgetType': widgetType,
    'bounds': bounds != null ? {
      'x': bounds!.left,
      'y': bounds!.top,
      'w': bounds!.width,
      'h': bounds!.height,
    } : null,
  };
}
