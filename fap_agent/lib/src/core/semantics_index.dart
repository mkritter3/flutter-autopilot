import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'selector_parser.dart';

class FapElement {
  final String id;
  final SemanticsNode node;
  final Rect globalRect;
  String? type;
  String? key;

  FapElement({
    required this.id,
    required this.node,
    required this.globalRect,
    this.type,
    this.key,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type ?? 'Unknown',
      'key': key ?? '',
      'label': node.label,
      'value': node.value,
      'hint': node.hint,
      'rect': {
        'x': globalRect.left,
        'y': globalRect.top,
        'w': globalRect.width,
        'h': globalRect.height,
      },
      'actions': _getActions(node.getSemanticsData().actions),
    };
  }

  List<String> _getActions(int actionsMask) {
    final List<String> result = [];
    for (final action in SemanticsAction.values) {
      if ((actionsMask & action.index) != 0) {
        result.add(action.name);
      }
    }
    return result;
  }
}

class SemanticsIndexer {
  final Map<String, FapElement> _elements = {};
  int _nextId = 1;

  Map<String, FapElement> get elements => _elements;

  void reindex() {
    _elements.clear();
    _nextId = 1;
    
    // 1. Index Semantics
    for (final view in RendererBinding.instance.renderViews) {
      final owner = view.owner?.semanticsOwner;
      if (owner?.rootSemanticsNode != null) {
        _traverse(owner!.rootSemanticsNode!, Matrix4.identity());
      }
    }
    
    // Fallback
    if (_elements.isEmpty) {
       final rootOwner = RendererBinding.instance.rootPipelineOwner.semanticsOwner;
       if (rootOwner?.rootSemanticsNode != null) {
         _traverse(rootOwner!.rootSemanticsNode!, Matrix4.identity());
       }
    }

    // 2. Enrich with Widget Type/Key info
    _enrichElements();
    
    print('SemanticsIndexer: Indexed ${_elements.length} elements.');
  }

  void _traverse(SemanticsNode node, Matrix4 parentTransform) {
    final Matrix4 nodeGlobalTransform = node.transform != null
        ? parentTransform * node.transform!
        : parentTransform;

    if (!node.isInvisible) {
      final globalRect = MatrixUtils.transformRect(nodeGlobalTransform, node.rect);
      final id = 'fap-${_nextId++}';
      
      _elements[id] = FapElement(
        id: id,
        node: node,
        globalRect: globalRect,
      );
    }

    node.visitChildren((child) {
      _traverse(child, nodeGlobalTransform);
      return true;
    });
  }

  void _enrichElements() {
    final rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement != null) {
      // Create lookup map for O(1) access
      final semanticsMap = <int, FapElement>{};
      for (final el in _elements.values) {
        semanticsMap[el.node.id] = el;
      }

      _traverseElements(rootElement, semanticsMap);
    }
  }

  void _traverseElements(Element element, Map<int, FapElement> semanticsMap) {
    final renderObject = element.renderObject;
    if (renderObject != null && renderObject.debugSemantics != null) {
      final semanticsId = renderObject.debugSemantics!.id;
      final fapElement = semanticsMap[semanticsId];

      if (fapElement != null) {
        // Found match!

        // 1. Check current element for Key/Type
        _extractInfo(element, fapElement);

        // 2. Walk up ancestors if Key or Type is missing
        if (fapElement.key == null || fapElement.type == null) {
          element.visitAncestorElements((ancestor) {
            _extractInfo(ancestor, fapElement);
            // Stop if we found a Key, as that's usually the "target" widget.
            if (fapElement.key != null) return false;
            return true;
          });
        }
      }
    }

    element.visitChildren((child) => _traverseElements(child, semanticsMap));
  }

  void _extractInfo(Element element, FapElement fapElement) {
    // Extract Key
    if (fapElement.key == null && element.widget.key != null) {
      final key = element.widget.key!;
      if (key is ValueKey<String>) {
        fapElement.key = key.value;
      } else {
         String keyStr = key.toString();
         if (keyStr.startsWith("[<'") && keyStr.endsWith("'>]")) {
           keyStr = keyStr.substring(3, keyStr.length - 3);
         } else if (keyStr.startsWith("[<") && keyStr.endsWith(">]")) {
           keyStr = keyStr.substring(2, keyStr.length - 2);
         }
         fapElement.key = keyStr;
      }
      // If we found a key, use this widget's type
      fapElement.type = element.widget.runtimeType.toString();
    }

    // Extract Type (heuristic)
    if (fapElement.type == null && !element.widget.runtimeType.toString().startsWith('_')) {
       fapElement.type = element.widget.runtimeType.toString();
    }
  }

  List<FapElement> find(Selector selector) {
    reindex(); 
    
    return _elements.values.where((element) {
      final data = element.node.getSemanticsData();
      
      // Match ID
      if (selector.id != null && element.id != selector.id) return false;

      // Match Text / Label
      if (selector.text != null && data.label != selector.text && data.value != selector.text && data.hint != selector.text) return false;
      if (selector.label != null && data.label != selector.label) return false;
      
      // Match Role
      if (selector.role != null) {
        if (selector.role == 'button' && !element.node.hasFlag(SemanticsFlag.isButton)) return false;
        if (selector.role == 'textField' && !element.node.hasFlag(SemanticsFlag.isTextField)) return false;
      }

      // Match Key
      if (selector.key != null) {
        if (element.key != selector.key) return false;
      }

      // Match Type
      if (selector.type != null) {
        if (element.type != selector.type) return false;
      }

      // Match Attributes
      for (final entry in selector.attributes.entries) {
        if (data.label != entry.value && data.value != entry.value && data.hint != entry.value) return false;
      }
      
      return true;
    }).toList();
  }
}
