import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Handler for rich text editors (SuperEditor, SuperTextLayout, etc.)
///
/// SuperEditor Architecture:
/// - SuperEditor widget holds an Editor instance
/// - Editor has a Document and executes Commands via execute([Command])
/// - Document contains DocumentNodes (ParagraphNode, ListItemNode, etc.)
/// - DocumentComposer manages selection and composition
///
/// This handler discovers rich text editors and provides methods to:
/// - Insert text at the current selection
/// - Get document content
/// - Get/set selection
/// - Apply formatting
class RichTextHandler {
  static final RichTextHandler instance = RichTextHandler._();
  RichTextHandler._();

  // Cache of detected editors by element hash
  final Map<int, RichTextEditorRef> _editorCache = {};

  /// Clear the editor cache (call when UI changes significantly)
  void clearCache() {
    _editorCache.clear();
  }

  /// Discover all rich text editors in the widget tree
  List<RichTextEditorRef> discoverEditors() {
    final results = <RichTextEditorRef>[];
    _editorCache.clear();

    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return results;

    void visit(Element element) {
      final typeName = element.widget.runtimeType.toString();

      if (_isSupportedEditor(typeName)) {
        final ref = _createEditorRef(element, typeName);
        if (ref != null) {
          results.add(ref);
          _editorCache[element.hashCode] = ref;
        }
      }

      element.visitChildren(visit);
    }

    visit(root);
    debugPrint('RichTextHandler: Discovered ${results.length} editors');
    return results;
  }

  /// Check if a widget type name indicates a supported rich text editor
  bool _isSupportedEditor(String typeName) {
    return typeName.contains('SuperEditor') ||
        typeName.contains('SuperTextField') ||
        typeName.contains('SuperTextLayout') ||
        typeName.contains('SuperReader') ||
        typeName.contains('DocumentEditor') ||
        typeName.contains('QuillEditor') ||
        typeName.contains('FlutterQuill') ||
        typeName.contains('ZefyrEditor') ||
        typeName.contains('RichTextEditor') ||
        typeName.contains('AttributedTextEditor');
  }

  /// Create a reference to a rich text editor
  RichTextEditorRef? _createEditorRef(Element element, String typeName) {
    try {
      final widget = element.widget;
      final dynamic dynWidget = widget;

      // Try multiple access patterns to get editor components
      dynamic editor;
      dynamic document;
      dynamic composer;
      dynamic editContext;

      // Pattern 1: Direct widget properties
      try {
        editor = dynWidget.editor;
      } catch (_) {}
      try {
        document = dynWidget.document;
      } catch (_) {}
      try {
        composer = dynWidget.composer;
      } catch (_) {}
      try {
        editContext = dynWidget.editContext;
      } catch (_) {}

      // Pattern 2: Via State object
      if (element is StatefulElement) {
        final state = element.state;
        final dynamic dynState = state;

        try {
          editor ??= dynState.editor;
        } catch (_) {}
        try {
          document ??= dynState.document;
        } catch (_) {}
        try {
          composer ??= dynState.composer;
        } catch (_) {}
        try {
          editContext ??= dynState.editContext;
        } catch (_) {}

        // Pattern 3: Via editContext (SuperEditor pattern)
        if (editContext != null) {
          try {
            editor ??= (editContext as dynamic).editor;
          } catch (_) {}
          try {
            document ??= (editContext as dynamic).document;
          } catch (_) {}
          try {
            composer ??= (editContext as dynamic).composer;
          } catch (_) {}
        }
      }

      // Get bounds
      final renderObject = element.renderObject;
      Rect? bounds;
      if (renderObject is RenderBox && renderObject.hasSize) {
        try {
          final transform = renderObject.getTransformTo(null);
          bounds = MatrixUtils.transformRect(
            transform,
            Offset.zero & renderObject.size,
          );
        } catch (_) {}
      }

      return RichTextEditorRef(
        id: element.hashCode,
        editorType: typeName,
        element: element,
        bounds: bounds ?? Rect.zero,
        editor: editor,
        document: document,
        composer: composer,
        editContext: editContext,
      );
    } catch (e) {
      debugPrint('RichTextHandler: Error creating ref for $typeName: $e');
      return null;
    }
  }

  /// Get editor by element hash code
  RichTextEditorRef? getEditor(int hashCode) => _editorCache[hashCode];

  /// Get editor by finding element with matching hash
  RichTextEditorRef? getEditorByElement(Element element) {
    final cached = _editorCache[element.hashCode];
    if (cached != null) return cached;

    // Try to create a ref if not cached
    final typeName = element.widget.runtimeType.toString();
    if (_isSupportedEditor(typeName)) {
      final ref = _createEditorRef(element, typeName);
      if (ref != null) {
        _editorCache[element.hashCode] = ref;
      }
      return ref;
    }
    return null;
  }

  /// Insert text at current selection using SuperEditor command pattern
  Future<Map<String, dynamic>> insertText(int editorId, String text) async {
    final ref = _editorCache[editorId];
    if (ref == null) {
      return {'success': false, 'error': 'Editor not found: $editorId'};
    }

    if (ref.editor == null) {
      return {
        'success': false,
        'error': 'No Editor instance available',
        'hint': 'Use IME fallback via enterRichText RPC method',
      };
    }

    try {
      final dynamic editor = ref.editor;

      // Check if composer has a selection
      dynamic selection;
      if (ref.composer != null) {
        try {
          selection = (ref.composer as dynamic).selection;
        } catch (_) {}
      }

      if (selection == null) {
        return {
          'success': false,
          'error': 'No selection available. Focus the editor first.',
          'hint': 'Tap the editor to place cursor before inserting text.',
        };
      }

      // Try to execute insert command
      // SuperEditor uses: editor.execute([InsertTextRequest(documentPosition, attributions, text)])
      try {
        // Get the request class dynamically
        // This varies by SuperEditor version
        final requestTypes = _getInsertRequestTypes(editor);

        if (requestTypes.isEmpty) {
          return {
            'success': false,
            'error': 'Could not determine insert request type',
            'editorType': editor.runtimeType.toString(),
            'hint':
                'SuperEditor API may have changed. Use IME fallback instead.',
          };
        }

        // Try to execute using the found request type
        for (final requestType in requestTypes) {
          try {
            final result =
                await _executeInsert(editor, ref.composer, text, requestType);
            if (result['success'] == true) {
              return result;
            }
          } catch (e) {
            debugPrint(
                'RichTextHandler: Insert attempt with $requestType failed: $e');
          }
        }

        return {
          'success': false,
          'error': 'All insert attempts failed',
          'triedTypes': requestTypes,
          'hint': 'Use IME fallback via enterRichText RPC method',
        };
      } catch (e) {
        return {
          'success': false,
          'error': 'Insert command execution failed: $e',
        };
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Determine available insert request types from editor
  List<String> _getInsertRequestTypes(dynamic editor) {
    final types = <String>[];

    // SuperEditor common request types
    // - InsertTextRequest (older versions)
    // - InsertTextAtCaretRequest (newer versions)
    // - InsertCharacterAtCaretRequest

    try {
      final editorType = editor.runtimeType.toString();
      debugPrint('RichTextHandler: Editor type: $editorType');

      // The editor.execute method accepts a list of requests
      // We'll try common patterns
      types.add('InsertTextAtCaretRequest');
      types.add('InsertCharacterAtCaretRequest');
      types.add('InsertTextRequest');
    } catch (e) {
      debugPrint('RichTextHandler: Error determining request types: $e');
    }

    return types;
  }

  /// Execute insert using a specific request type
  Future<Map<String, dynamic>> _executeInsert(
    dynamic editor,
    dynamic composer,
    String text,
    String requestType,
  ) async {
    // SuperEditor's execute pattern:
    // editor.execute([
    //   InsertTextAtCaretRequest(text: text, attributions: {}),
    // ]);

    // Since we can't import SuperEditor types, we need to use dynamic invocation
    // This is inherently limited

    return {
      'success': false,
      'error':
          'Direct SuperEditor command execution requires app-specific integration',
      'requestType': requestType,
      'hint':
          'SuperEditor uses a Command pattern. '
          'For full support, integrate FAP directly with your app\'s Editor instance. '
          'Alternatively, use the IME fallback which works for plain text insertion.',
      'workaround': 'Call enterRichText with useDelta=true for IME simulation',
    };
  }

  /// Get document content as structured data
  Future<Map<String, dynamic>> getContent(int editorId) async {
    final ref = _editorCache[editorId];
    if (ref == null) {
      return {'success': false, 'error': 'Editor not found'};
    }

    if (ref.document == null) {
      return {'success': false, 'error': 'No document available'};
    }

    try {
      final dynamic doc = ref.document;
      final nodes = <Map<String, dynamic>>[];

      // SuperEditor Document has a 'nodes' property
      try {
        final docNodes = doc.nodes as List<dynamic>;
        for (final node in docNodes) {
          nodes.add(_nodeToJson(node));
        }
      } catch (e) {
        debugPrint('RichTextHandler: Error reading nodes: $e');
      }

      // Try to get plain text
      String? plainText;
      try {
        // Some documents have toPlainText() or similar
        plainText = _extractPlainText(doc);
      } catch (_) {}

      return {
        'success': true,
        'editorId': editorId,
        'documentType': doc.runtimeType.toString(),
        'nodeCount': nodes.length,
        'nodes': nodes,
        'plainText': plainText,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Map<String, dynamic> _nodeToJson(dynamic node) {
    try {
      final result = <String, dynamic>{
        'type': node.runtimeType.toString(),
      };

      // Try to get node ID
      try {
        result['id'] = (node as dynamic).id;
      } catch (_) {}

      // Try to get text content
      try {
        final text = (node as dynamic).text;
        if (text != null) {
          // AttributedText has a 'text' property
          try {
            result['text'] = (text as dynamic).text;
          } catch (_) {
            result['text'] = text.toString();
          }
        }
      } catch (_) {}

      // Try to get metadata
      try {
        final metadata = (node as dynamic).metadata;
        if (metadata != null) {
          result['metadata'] = metadata.toString();
        }
      } catch (_) {}

      return result;
    } catch (_) {
      return {'type': node.runtimeType.toString()};
    }
  }

  String? _extractPlainText(dynamic document) {
    try {
      // Try common patterns
      try {
        return (document as dynamic).toPlainText();
      } catch (_) {}

      // Build from nodes
      final nodes = document.nodes as List<dynamic>;
      final buffer = StringBuffer();
      for (final node in nodes) {
        try {
          final text = (node as dynamic).text;
          if (text != null) {
            try {
              buffer.writeln((text as dynamic).text);
            } catch (_) {
              buffer.writeln(text.toString());
            }
          }
        } catch (_) {}
      }
      final result = buffer.toString().trim();
      return result.isEmpty ? null : result;
    } catch (_) {
      return null;
    }
  }

  /// Get current selection state
  Future<Map<String, dynamic>> getSelection(int editorId) async {
    final ref = _editorCache[editorId];
    if (ref == null) {
      return {'success': false, 'error': 'Editor not found'};
    }

    if (ref.composer == null) {
      return {'success': false, 'error': 'No composer available'};
    }

    try {
      final dynamic composer = ref.composer;
      dynamic selection;

      try {
        selection = composer.selection;
      } catch (_) {}

      if (selection == null) {
        return {
          'success': true,
          'editorId': editorId,
          'hasSelection': false,
        };
      }

      return {
        'success': true,
        'editorId': editorId,
        'hasSelection': true,
        'selection': _selectionToJson(selection),
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Map<String, dynamic> _selectionToJson(dynamic selection) {
    try {
      final result = <String, dynamic>{};

      try {
        result['isCollapsed'] = selection.isCollapsed;
      } catch (_) {}

      try {
        final base = selection.base;
        result['base'] = _positionToJson(base);
      } catch (_) {}

      try {
        final extent = selection.extent;
        result['extent'] = _positionToJson(extent);
      } catch (_) {}

      return result;
    } catch (_) {
      return {'raw': selection.toString()};
    }
  }

  Map<String, dynamic> _positionToJson(dynamic position) {
    try {
      final result = <String, dynamic>{};

      try {
        result['nodeId'] = position.nodeId;
      } catch (_) {}

      try {
        final nodePosition = position.nodePosition;
        try {
          result['offset'] = (nodePosition as dynamic).offset;
        } catch (_) {
          result['nodePosition'] = nodePosition.toString();
        }
      } catch (_) {}

      return result;
    } catch (_) {
      return {'raw': position.toString()};
    }
  }

  /// Apply formatting to current selection
  Future<Map<String, dynamic>> applyFormat(int editorId, String format) async {
    final ref = _editorCache[editorId];
    if (ref == null) {
      return {'success': false, 'error': 'Editor not found'};
    }

    // Map common format names to SuperEditor attributions
    final formatMap = {
      'bold': 'bold',
      'italic': 'italics',
      'underline': 'underline',
      'strikethrough': 'strikethrough',
      'code': 'code',
    };

    if (!formatMap.containsKey(format.toLowerCase())) {
      return {
        'success': false,
        'error': 'Unknown format: $format',
        'availableFormats': formatMap.keys.toList(),
      };
    }

    // Format application requires executing a ToggleTextAttributionsRequest
    // This is app-specific
    return {
      'success': false,
      'error': 'Format application requires app-specific integration',
      'format': format,
      'attribution': formatMap[format.toLowerCase()],
      'hint':
          'Use editor.execute([ToggleTextAttributionsRequest(attributions: {$format})])',
    };
  }

  /// Clear all document content
  Future<Map<String, dynamic>> clearContent(int editorId) async {
    final ref = _editorCache[editorId];
    if (ref == null) {
      return {'success': false, 'error': 'Editor not found'};
    }

    // Clearing requires selecting all + delete, which is app-specific
    return {
      'success': false,
      'error': 'Clear content requires app-specific integration',
      'hint': 'Select all text then execute delete command',
    };
  }
}

/// Reference to a discovered rich text editor
class RichTextEditorRef {
  final int id;
  final String editorType;
  final Element element;
  final Rect bounds;
  final dynamic editor;
  final dynamic document;
  final dynamic composer;
  final dynamic editContext;

  RichTextEditorRef({
    required this.id,
    required this.editorType,
    required this.element,
    required this.bounds,
    this.editor,
    this.document,
    this.composer,
    this.editContext,
  });

  bool get hasEditor => editor != null;
  bool get hasDocument => document != null;
  bool get hasComposer => composer != null;
  bool get hasEditContext => editContext != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'editorType': editorType,
        'hasEditor': hasEditor,
        'hasDocument': hasDocument,
        'hasComposer': hasComposer,
        'hasEditContext': hasEditContext,
        'bounds': {
          'x': bounds.left,
          'y': bounds.top,
          'w': bounds.width,
          'h': bounds.height,
        },
      };
}
