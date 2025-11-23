import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import '../widgets/fap_meta.dart';
import 'selector_parser.dart';

class FapElement {
  final String id;
  final SemanticsNode node;
  final Rect globalRect;
  String? type;
  String? key;
  Map<String, String> metadata = {};

  FapElement({
    required this.id,
    required this.node,
    required this.globalRect,
    this.type,
    this.key,
    Map<String, String>? metadata,
  }) : metadata = metadata ?? {};

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type ?? 'Unknown',
      'key': key ?? '',
      'label': node.label,
      'value': node.value,
      'hint': node.hint,
      'metadata': metadata,
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

  final Map<int, FapElement> _nodeIdToElement = {};

  void reindex() {
    _elements.clear();
    _nodeIdToElement.clear();
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
      
      final element = FapElement(
        id: id,
        node: node,
        globalRect: globalRect,
      );
      _elements[id] = element;
      _nodeIdToElement[node.id] = element;
    }

    node.visitChildren((child) {
      _traverse(child, nodeGlobalTransform);
      return true;
    });
  }

  // ... _enrichElements and _traverseElements remain same ...
  // But I need to make sure I don't delete them.
  // Since I am replacing from line 55 (reindex) to end, I need to include them.
  // Wait, I should use replace_file_content carefully.
  // I will replace `reindex` and `_traverse` first to add `_nodeIdToElement`.
  // Then replace `find`.

  // Let's do it in chunks if possible, or just replace the whole class content if it's easier.
  // The file is small enough.

  // Actually, I'll just replace `reindex` and `_traverse` first.
  // And then `find`.

  // Wait, `_enrichElements` uses `_elements`.
  // I'll replace `reindex` and `_traverse` first.


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
    // Extract Metadata
    if (element.widget is FapMeta) {
      fapElement.metadata.addAll((element.widget as FapMeta).metadata);
    }

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
    var candidates = _elements.values.toList();
    return _findRecursive(candidates, selector);
  }

  List<FapElement> _findRecursive(List<FapElement> scope, Selector selector) {
    // 1. Filter scope by current selector criteria
    var matches = scope.where((e) => _matches(e, selector)).toList();

    if (selector.next == null) {
      return matches;
    }

    // 2. If there is a next selector, proceed based on combinator
    var nextScope = <FapElement>[];
    
    for (var match in matches) {
      if (selector.combinator == SelectorCombinator.child) {
        // Direct children
        match.node.visitChildren((child) {
           final childElement = _nodeIdToElement[child.id];
           if (childElement != null) {
             nextScope.add(childElement);
           }
           return true;
        });
      } else if (selector.combinator == SelectorCombinator.descendant) {
        // All descendants
        _collectDescendants(match.node, nextScope);
      }
    }
    
    return _findRecursive(nextScope, selector.next!);
  }

  void _collectDescendants(SemanticsNode node, List<FapElement> result) {
    node.visitChildren((child) {
      final childElement = _nodeIdToElement[child.id];
      if (childElement != null) {
        result.add(childElement);
      }
      _collectDescendants(child, result);
      return true;
    });
  }

  bool _matches(FapElement element, Selector selector) {
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
        // Check metadata first
        if (element.metadata.containsKey(entry.key)) {
            if (element.metadata[entry.key] != entry.value) return false;
            continue;
        }
        // Fallback to semantics data
        if (data.label != entry.value && data.value != entry.value && data.hint != entry.value) return false;
      }

      // Match Regex Attributes
      for (final entry in selector.regexAttributes.entries) {
        final pattern = entry.value;
        bool matched = false;
        
        // Check metadata
        if (element.metadata.containsKey(entry.key)) {
            if (pattern.hasMatch(element.metadata[entry.key]!)) matched = true;
        }
        
        // Check standard fields
        if (!matched) {
             if (entry.key == 'text' || entry.key == 'label') {
                 if (pattern.hasMatch(data.label)) matched = true;
             }
             if (entry.key == 'text' || entry.key == 'value') {
                 if (pattern.hasMatch(data.value)) matched = true;
             }
             if (entry.key == 'text' || entry.key == 'hint') {
                 if (pattern.hasMatch(data.hint)) matched = true;
             }
             if (entry.key == 'key' && element.key != null) {
                 if (pattern.hasMatch(element.key!)) matched = true;
             }
             if (entry.key == 'type' && element.type != null) {
                 if (pattern.hasMatch(element.type!)) matched = true;
             }
        }
        
        if (!matched) return false;
      }
      
      return true;
  }
}
