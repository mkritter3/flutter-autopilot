import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reference to a widget in the inspector tree
class FapWidgetRef {
  final String id;
  final String type;
  final String? key;
  final Rect bounds;
  final Map<String, dynamic> properties;

  FapWidgetRef({
    required this.id,
    required this.type,
    this.key,
    required this.bounds,
    required this.properties,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'key': key,
    'bounds': {
      'x': bounds.left,
      'y': bounds.top,
      'w': bounds.width,
      'h': bounds.height,
    },
    'properties': properties,
  };
}

/// Bridge to Flutter's WidgetInspector for accessing non-semantic widgets
class WidgetInspectorBridge {
  static final WidgetInspectorBridge instance = WidgetInspectorBridge._();
  WidgetInspectorBridge._();

  bool _initialized = false;
  final Map<String, FapWidgetRef> _widgetCache = {};
  
  /// Initialize the widget inspector bridge
  void initialize() {
    if (_initialized) return;
    
    // Enable widget inspector mode
    if (kDebugMode) {
      debugPrint('WidgetInspectorBridge: Initialized');
    }
    
    _initialized = true;
  }

  /// Get full widget tree by walking the Element tree
  Future<List<FapWidgetRef>> getWidgetTree() async {
    if (!_initialized) {
      throw StateError('WidgetInspectorBridge not initialized');
    }

    final widgets = <FapWidgetRef>[];
    
    // Get the root element
    final binding = WidgetsBinding.instance;
    final rootElement = binding.renderViewElement;
    
    if (rootElement != null) {
      _visitElement(rootElement, widgets);
    }
    
    // Update cache
    _widgetCache.clear();
    for (final widget in widgets) {
      _widgetCache[widget.id] = widget;
    }
    
    return widgets;
  }

  /// Recursively visit elements and build widget refs
  void _visitElement(Element element, List<FapWidgetRef> widgets) {
    try {
      // Get widget info
      final widget = element.widget;
      final renderObject = element.renderObject;
      
      // Only include widgets with RenderObject (visible widgets)
      if (renderObject is RenderBox && renderObject.hasSize) {
        final id = 'widget-${element.hashCode}';
        final type = widget.runtimeType.toString();
        final key = widget.key?.toString();
        
        // Get global bounds
        final offset = renderObject.localToGlobal(Offset.zero);
        final size = renderObject.size;
        final bounds = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
        
        // Extract basic properties
        final properties = <String, dynamic>{
          'hashCode': element.hashCode,
          'depth': element.depth,
        };
        
        // Add to list
        widgets.add(FapWidgetRef(
          id: id,
          type: type,
          key: key,
          bounds: bounds,
          properties: properties,
        ));
      }
      
      // Visit children
      element.visitChildren((child) {
        _visitElement(child, widgets);
      });
    } catch (e) {
      // Skip elements that error out
      if (kDebugMode) {
        debugPrint('Error visiting element: $e');
      }
    }
  }

  /// Find widgets by runtime type
  Future<List<FapWidgetRef>> findByType(String typeName) async {
    final allWidgets = await getWidgetTree();
    return allWidgets.where((w) => w.type.contains(typeName)).toList();
  }

  /// Find widgets by key
  Future<List<FapWidgetRef>> findByKey(String keyPattern) async {
    final allWidgets = await getWidgetTree();
    return allWidgets.where((w) => w.key?.contains(keyPattern) ?? false).toList();
  }

  /// Find widget by ID
  FapWidgetRef? findById(String id) {
    return _widgetCache[id];
  }

  /// Get widget at specific coordinates
  Future<FapWidgetRef?> findByCoordinates(Offset position) async {
    final allWidgets = await getWidgetTree();
    
    // Find widgets containing the point, sorted by size (smallest first)
    final matches = allWidgets
        .where((w) => w.bounds.contains(position))
        .toList()
      ..sort((a, b) => (a.bounds.width * a.bounds.height)
          .compareTo(b.bounds.width * b.bounds.height));
    
    return matches.isNotEmpty ? matches.first : null;
  }

  /// Clear widget cache
  void clearCache() {
    _widgetCache.clear();
  }
}
