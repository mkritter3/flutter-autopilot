import 'package:flutter/rendering.dart';

import 'selector_parser.dart';

class FapElement {
  final String id;
  final SemanticsNode node;
  final Rect globalRect;

  FapElement({
    required this.id,
    required this.node,
    required this.globalRect,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
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
      // 'role': node.getSemanticsData(). // Role is not directly exposed as a string easily, need to infer or use debug properties
    };
  }

  List<String> _getActions(int actionsMask) {
    final List<String> result = [];
    // SemanticsAction.values is a Map<int, SemanticsAction> in stable, but might be List in some versions?
    // The error said "List<SemanticsAction>". So let's try iterating directly.
    // But wait, if it's a List, it doesn't have .values.
    // Let's assume it is a Map in the version I am using if .values failed on List.
    // Wait, the error was: "The getter 'values' isn't defined for the type 'List<SemanticsAction>'".
    // This CONFIRMS it is a List. So I should remove .values.
    
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
    
    print('SemanticsIndexer: Checking renderViews...');
    for (final view in RendererBinding.instance.renderViews) {
      final owner = view.owner?.semanticsOwner;
      print('SemanticsIndexer: View=$view, Owner=$owner, RootNode=${owner?.rootSemanticsNode}');
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
    
    print('SemanticsIndexer: Indexed ${_elements.length} elements.');
  }

  void _traverse(SemanticsNode node, Matrix4 parentTransform) {
    // Log node details
    // print('Node ${node.id}: Rect=${node.rect}, Transform=${node.transform}');
    // print('  Actions: ${node.getSemanticsData().actions}');

    // Calculate transform for this node
    // node.transform transforms from node to parent.
    // So nodeGlobalTransform (node to global) = parentTransform (parent to global) * node.transform (node to parent)
    final Matrix4 nodeGlobalTransform = node.transform != null
        ? parentTransform * node.transform!
        : parentTransform;

    if (!node.isInvisible) {
      // If rect is local, we apply nodeGlobalTransform.
      // If rect is in parent, we apply parentTransform.
      // Data suggests rect is local (0,0) while transform has translation.
      // So we use nodeGlobalTransform.
      final globalRect = MatrixUtils.transformRect(nodeGlobalTransform, node.rect);
      
      print('  GlobalRect: $globalRect');
      
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

  List<FapElement> find(Selector selector) {
    reindex(); // Always reindex before search for now
    
    return _elements.values.where((element) {
      final data = element.node.getSemanticsData();
      
      // Match ID
      if (selector.id != null && element.id != selector.id) return false;

      // Match Text / Label
      if (selector.text != null && data.label != selector.text && data.value != selector.text && data.hint != selector.text) return false;
      if (selector.label != null && data.label != selector.label) return false;
      
      // Match Role (heuristic based on actions or flags)
      if (selector.role != null) {
        // Simple role matching
        if (selector.role == 'button' && !element.node.hasFlag(SemanticsFlag.isButton)) return false;
        if (selector.role == 'textField' && !element.node.hasFlag(SemanticsFlag.isTextField)) return false;
        // Add more roles as needed
      }

      // Match Key (not directly available in SemanticsNode without debug builds or custom metadata)
      // For MVP, we might rely on 'label' or 'hint' acting as key if key is not available.
      // Or we need to traverse WidgetInspector to find the widget key.
      // This is a known limitation of Semantics-only approach.
      // If we want keys, we need to map SemanticsNode back to Widget.
      // For now, let's assume key matching is not supported or relies on label.
      if (selector.key != null) {
        // Check if label or hint matches key for now
        if (data.label != selector.key && data.hint != selector.key) return false;
      }

      // Match Type (also hard with just SemanticsNode)
      if (selector.type != null) {
        // Cannot easily check widget type from SemanticsNode alone.
        // We would need to use WidgetInspectorService.
        // For MVP, ignore or fail?
        // Let's ignore type matching for now or log warning.
      }

      // Match Attributes
      for (final entry in selector.attributes.entries) {
        // Check if any string property matches
        if (data.label != entry.value && data.value != entry.value && data.hint != entry.value) return false;
      }
      
      return true;
    }).toList();
  }
}
