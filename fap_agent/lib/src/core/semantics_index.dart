import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import '../widgets/fap_meta.dart';
import 'selector_parser.dart';

/// Source of element discovery
enum FapElementSource {
  /// Discovered via Semantics tree (has rich accessibility metadata)
  semantics,
  /// Discovered via Element tree fallback (inside ExcludeSemantics)
  element,
}

class FapElement {
  final String id;
  final SemanticsNode? node;  // Nullable for element-based discovery
  final Element? widgetElement;  // For element-based discovery
  final Rect globalRect;
  final FapElementSource source;
  String? type;
  String? key;
  String? label;  // For element-only: extracted from widget
  String? value;  // For element-only: extracted from widget
  Map<String, String> metadata = {};

  // Explicit placeholder marking (from FapMeta)
  bool _explicitPlaceholder = false;
  String? _explicitPlaceholderReason;

  FapElement({
    required this.id,
    this.node,
    this.widgetElement,
    required this.globalRect,
    this.source = FapElementSource.semantics,
    this.type,
    this.key,
    this.label,
    this.value,
    Map<String, String>? metadata,
  }) : metadata = metadata ?? {};

  /// Set explicit placeholder from FapMeta
  void setExplicitPlaceholder(bool isPlaceholder, String? reason) {
    _explicitPlaceholder = isPlaceholder;
    _explicitPlaceholderReason = reason;
  }

  /// Whether the element is enabled (from semantics flags)
  bool get isEnabled {
    if (node == null) return true;
    if (node!.hasFlag(SemanticsFlag.hasEnabledState)) {
      return node!.hasFlag(SemanticsFlag.isEnabled);
    }
    return true;
  }

  /// Placeholder text patterns for heuristic detection
  static final List<RegExp> _placeholderPatterns = [
    RegExp(r'coming\s+soon', caseSensitive: false),
    RegExp(r'not\s+implemented', caseSensitive: false),
    RegExp(r'under\s+(construction|development)', caseSensitive: false),
    RegExp(r'\bTODO\b', caseSensitive: false),
    RegExp(r'\bWIP\b', caseSensitive: false),
    RegExp(r'\bstub\b', caseSensitive: false),
    RegExp(r'placeholder', caseSensitive: false),
    RegExp(r'lorem\s+ipsum', caseSensitive: false),
    RegExp(r'feature\s+coming', caseSensitive: false),
    RegExp(r'not\s+available', caseSensitive: false),
    RegExp(r'upgrade\s+to\s+unlock', caseSensitive: false),
  ];

  /// Whether this element is a placeholder (explicit or heuristic)
  bool get isPlaceholder {
    if (_explicitPlaceholder) return true;
    return _detectPlaceholderHeuristically();
  }

  bool _detectPlaceholderHeuristically() {
    if (node == null) return false;
    final data = node!.getSemanticsData();

    // H1: Disabled button (has enabled state but is disabled)
    if (node!.hasFlag(SemanticsFlag.isButton)) {
      if (node!.hasFlag(SemanticsFlag.hasEnabledState) &&
          !node!.hasFlag(SemanticsFlag.isEnabled)) {
        return true;
      }
      // H2: Button without tap action
      if (!data.hasAction(SemanticsAction.tap)) {
        return true;
      }
    }

    // H3: Text pattern matching
    final textContent = '${data.label} ${data.value} ${data.hint}'.toLowerCase();
    for (final pattern in _placeholderPatterns) {
      if (pattern.hasMatch(textContent)) {
        return true;
      }
    }

    // H4: Check metadata for placeholder hints
    if (metadata.containsKey('placeholder') ||
        metadata.containsKey('stub') ||
        metadata.containsKey('wip')) {
      return true;
    }

    return false;
  }

  /// Reason why element is considered a placeholder
  String? get placeholderReason {
    if (_explicitPlaceholderReason != null) return _explicitPlaceholderReason;
    return _getHeuristicPlaceholderReason();
  }

  String? _getHeuristicPlaceholderReason() {
    if (node == null) return null;
    final data = node!.getSemanticsData();

    // Check disabled button
    if (node!.hasFlag(SemanticsFlag.isButton)) {
      if (node!.hasFlag(SemanticsFlag.hasEnabledState) &&
          !node!.hasFlag(SemanticsFlag.isEnabled)) {
        return 'Disabled button';
      }
      if (!data.hasAction(SemanticsAction.tap)) {
        return 'Button without tap action';
      }
    }

    // Check text patterns
    final textContent = '${data.label} ${data.value} ${data.hint}'.toLowerCase();
    for (final pattern in _placeholderPatterns) {
      if (pattern.hasMatch(textContent)) {
        return 'Placeholder text detected';
      }
    }

    // Check metadata
    if (metadata.containsKey('placeholder')) {
      return metadata['placeholder'] ?? 'Marked as placeholder';
    }
    if (metadata.containsKey('stub')) {
      return metadata['stub'] ?? 'Marked as stub';
    }
    if (metadata.containsKey('wip')) {
      return 'Work in progress';
    }

    return null;
  }

  /// UI category for classification
  String get uiCategory {
    final typeName = type ?? '';

    // Overlay/Modal types
    if (typeName.contains('PopupMenu') || typeName.contains('DropdownMenu')) {
      return 'menu';
    }
    if (typeName.contains('MenuItem') || typeName.contains('MenuItemButton')) {
      return 'menuItem';
    }
    if (typeName.contains('Drawer') || typeName.contains('NavigationDrawer')) {
      return 'drawer';
    }
    if (typeName.contains('BottomSheet')) {
      return 'bottomSheet';
    }
    if (typeName.contains('Dialog') || typeName.contains('AlertDialog')) {
      return 'dialog';
    }
    if (typeName.contains('Snackbar') || typeName.contains('MaterialBanner')) {
      return 'notification';
    }

    // Rich text editors
    if (typeName.contains('SuperEditor') ||
        typeName.contains('SuperTextField') ||
        typeName.contains('SuperTextLayout') ||
        typeName.contains('QuillEditor')) {
      return 'richEditor';
    }

    // Standard text input
    if (typeName.contains('TextField') || typeName.contains('TextFormField')) {
      return 'textField';
    }

    // Buttons
    if (typeName.contains('Button') ||
        typeName.contains('InkWell') ||
        typeName.contains('GestureDetector')) {
      return 'button';
    }

    return 'standard';
  }

  /// Whether this element is from an overlay (menu, dialog, drawer, etc.)
  bool get isOverlayElement {
    return metadata['_isOverlay'] == 'true';
  }

  /// Type of overlay if this is an overlay element
  String? get overlayType => metadata['_overlayType'];

  /// Whether this is a rich text editor
  bool get isRichTextEditor {
    final cat = uiCategory;
    return cat == 'richEditor';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type ?? 'Unknown',
      'key': key ?? '',
      'source': source.name,
      'label': node?.label ?? label ?? '',
      'value': node?.value ?? value ?? '',
      'hint': node?.hint ?? '',
      'metadata': metadata,
      'rect': {
        'x': globalRect.left,
        'y': globalRect.top,
        'w': globalRect.width,
        'h': globalRect.height,
      },
      'actions': node != null ? _getActions(node!.getSemanticsData().actions) : <String>[],
      'isEnabled': isEnabled,
      'isPlaceholder': isPlaceholder,
      'placeholderReason': placeholderReason,
      // New fields for overlay/menu discovery
      'uiCategory': uiCategory,
      'isOverlay': isOverlayElement,
      'overlayType': overlayType,
      'isRichTextEditor': isRichTextEditor,
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

  bool get isInteractable {
    // Size check applies to both sources
    if (globalRect.width <= 0 || globalRect.height <= 0) return false;

    // Semantics-based check
    if (node != null) {
      if (node!.isInvisible) return false;
      if (node!.isMergedIntoParent) return false;
      if (node!.hasFlag(SemanticsFlag.hasEnabledState) &&
          !node!.hasFlag(SemanticsFlag.isEnabled)) {
        return false;
      }
      return true;
    }

    // Element-based check - widget type heuristics
    if (widgetElement != null) {
      final typeName = widgetElement!.widget.runtimeType.toString();
      // These widget types are typically interactable
      if (typeName.contains('Button') ||
          typeName.contains('GestureDetector') ||
          typeName.contains('InkWell') ||
          typeName.contains('TextField') ||
          typeName.contains('Checkbox') ||
          typeName.contains('Switch') ||
          typeName.contains('Slider') ||
          typeName.contains('ListTile') ||
          typeName.contains('PopupMenu')) {
        return true;
      }
    }

    return false;
  }
}

class SemanticsIndexer {
  final Map<String, FapElement> _elements = {};
  Map<String, FapElement> _previousElements = {};

  Map<String, FapElement> get elements => _elements;

  final Map<int, FapElement> _nodeIdToElement = {};

  DateTime _lastReindex = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _throttleDuration = Duration(milliseconds: 15);

  /// Whether to discover widgets inside ExcludeSemantics wrappers
  bool includeExcludedElements = true;

  // Server-side UI state caching (for navigation across reconnects)
  Map<String, FapElement> _cachedElements = {};
  DateTime? _cacheTimestamp;
  bool _hasCachedData = false;
  bool _lastResponseWasCached = false;
  static const Duration _maxCacheAge = Duration(seconds: 5);
  static const int _maxCacheSize = 10000;

  // Getters for cache metadata
  bool get lastResponseWasCached => _lastResponseWasCached;
  int? get cacheAgeSeconds => _cacheTimestamp != null
      ? DateTime.now().difference(_cacheTimestamp!).inSeconds
      : null;

  /// Returns all elements detected as placeholders
  List<FapElement> getPlaceholders() {
    reindex();
    return _elements.values.where((e) => e.isPlaceholder).toList();
  }

  void reindex({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastReindex) < _throttleDuration) {
      return;
    }
    _lastReindex = now;

    // Save previous state
    _previousElements = Map.from(_elements);

    _elements.clear();
    _nodeIdToElement.clear();
    _lastResponseWasCached = false;

    // 1. Index Semantics
    debugPrint('SemanticsIndexer: Reindexing... Views: ${RendererBinding.instance.renderViews.length}');
    for (final view in RendererBinding.instance.renderViews) {
      final owner = view.owner?.semanticsOwner;
      debugPrint('SemanticsIndexer: View $view, Owner: $owner, RootNode: ${owner?.rootSemanticsNode}');
      if (owner?.rootSemanticsNode != null) {
        _traverse(owner!.rootSemanticsNode!, Matrix4.identity());
      }
    }

    // Fallback
    if (_elements.isEmpty) {
      final rootOwner =
          RendererBinding.instance.rootPipelineOwner.semanticsOwner;
      if (rootOwner?.rootSemanticsNode != null) {
        _traverse(rootOwner!.rootSemanticsNode!, Matrix4.identity());
      }
    }

    // 2. Enrich with Widget Type/Key info
    _enrichElements();

    // 3. Discover excluded elements (inside ExcludeSemantics)
    if (includeExcludedElements) {
      final beforeCount = _elements.length;
      _discoverExcludedElements();
      final addedCount = _elements.length - beforeCount;
      if (addedCount > 0) {
        debugPrint('SemanticsIndexer: Discovered $addedCount excluded elements');
      }
    }

    // 4. Discover overlay elements (menus, dialogs, drawers when open)
    final overlayBeforeCount = _elements.length;
    _discoverOverlayElements();
    final overlayAddedCount = _elements.length - overlayBeforeCount;
    if (overlayAddedCount > 0) {
      debugPrint('SemanticsIndexer: Discovered $overlayAddedCount overlay elements');
    }

    // 4. Server-side caching logic
    if (_elements.isNotEmpty) {
      // Fresh data available - update cache
      _cachedElements = Map.from(_elements);
      _cacheTimestamp = DateTime.now();
      _hasCachedData = true;

      // Enforce cache size limit (keep only most recent)
      if (_cachedElements.length > _maxCacheSize) {
        print('⚠️  FAP Cache: Size limit exceeded (${_cachedElements.length}), trimming to $_maxCacheSize');
        final keys = _cachedElements.keys.take(_maxCacheSize).toList();
        _cachedElements = Map.fromEntries(
          keys.map((k) => MapEntry(k, _cachedElements[k]!))
        );
      }

      print('SemanticsIndexer: Indexed ${_elements.length} elements (cache updated).');
    } else if (_hasCachedData && _isCacheValid) {
      // Tree is empty but we have valid cached data - restore from cache
      _elements.addAll(_cachedElements);
      _lastResponseWasCached = true;
      final age = DateTime.now().difference(_cacheTimestamp!).inSeconds;
      print('⚠️  FAP: Serving cached UI tree (${_elements.length} elements, age: ${age}s)');
    } else {
      // No fresh data and no valid cache
      if (_hasCachedData && !_isCacheValid) {
        print('⚠️  FAP: Cache expired (age: ${DateTime.now().difference(_cacheTimestamp!).inSeconds}s > ${_maxCacheAge.inSeconds}s)');
      }
      print('SemanticsIndexer: Indexed ${_elements.length} elements.');
    }
  }

  bool get _isCacheValid {
    if (_cacheTimestamp == null) return false;
    return DateTime.now().difference(_cacheTimestamp!) < _maxCacheAge;
  }

  void _traverse(SemanticsNode node, Matrix4 parentTransform) {
    final Matrix4 nodeGlobalTransform = node.transform != null
        ? parentTransform * node.transform!
        : parentTransform;

    if (!node.isInvisible) {
      final globalRect = MatrixUtils.transformRect(
        nodeGlobalTransform,
        node.rect,
      );
      final id = 'fap-${node.id}';

      final element = FapElement(
        id: id,
        node: node,
        globalRect: globalRect,
        source: FapElementSource.semantics,
      );
      _elements[id] = element;
      _nodeIdToElement[node.id] = element;
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
        if (el.node != null) {
          semanticsMap[el.node!.id] = el;
        }
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
    // Extract Metadata and placeholder info from FapMeta
    if (element.widget is FapMeta) {
      final fapMeta = element.widget as FapMeta;
      fapElement.metadata.addAll(fapMeta.metadata);

      // Extract explicit placeholder marking
      if (fapMeta.isPlaceholder) {
        fapElement.setExplicitPlaceholder(true, fapMeta.placeholderReason);
      }
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
    if (fapElement.type == null &&
        !element.widget.runtimeType.toString().startsWith('_')) {
      fapElement.type = element.widget.runtimeType.toString();
    }
  }

  // ============================================================
  // ExcludeSemantics Fallback Discovery
  // ============================================================

  void _discoverExcludedElements() {
    final rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement == null) return;

    // Build set of elements already covered by semantics
    final coveredElementHashes = <int>{};
    for (final fapEl in _elements.values) {
      if (fapEl.widgetElement != null) {
        coveredElementHashes.add(fapEl.widgetElement!.hashCode);
      }
    }

    _traverseForExcluded(rootElement, coveredElementHashes);
  }

  void _traverseForExcluded(Element element, Set<int> covered) {
    // Skip if already covered by semantics
    if (covered.contains(element.hashCode)) {
      element.visitChildren((child) => _traverseForExcluded(child, covered));
      return;
    }

    // Check if this is inside ExcludeSemantics and is an interactable widget type
    if (_isInsideExcludeSemantics(element) && _isInteractableWidgetType(element)) {
      final fapElement = _createElementBasedFapElement(element);
      if (fapElement != null) {
        _elements[fapElement.id] = fapElement;
      }
    }

    element.visitChildren((child) => _traverseForExcluded(child, covered));
  }

  /// Discover overlay elements (menu items, dialogs, drawers when open)
  void _discoverOverlayElements() {
    final rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement == null) return;

    // Build set of elements already covered
    final coveredHashes = <int>{};
    for (final fapEl in _elements.values) {
      if (fapEl.widgetElement != null) {
        coveredHashes.add(fapEl.widgetElement!.hashCode);
      }
    }

    void visit(Element element) {
      if (coveredHashes.contains(element.hashCode)) {
        element.visitChildren(visit);
        return;
      }

      final typeName = element.widget.runtimeType.toString();

      // Check for overlay-specific widget types
      if (_isOverlayWidgetType(typeName)) {
        final fapElement = _createElementBasedFapElement(element);
        if (fapElement != null) {
          // Mark as overlay element
          fapElement.metadata['_isOverlay'] = 'true';
          fapElement.metadata['_overlayType'] = _classifyOverlayType(typeName);
          _elements[fapElement.id] = fapElement;
        }
      }

      element.visitChildren(visit);
    }

    visit(rootElement);
  }

  bool _isInsideExcludeSemantics(Element element) {
    bool found = false;
    element.visitAncestorElements((ancestor) {
      final typeName = ancestor.widget.runtimeType.toString();
      if (typeName == 'ExcludeSemantics') {
        found = true;
        return false; // Stop traversal
      }
      return true; // Continue
    });
    return found;
  }

  bool _isInteractableWidgetType(Element element) {
    final type = element.widget.runtimeType.toString();
    return type.contains('Button') ||
           type.contains('GestureDetector') ||
           type.contains('InkWell') ||
           type.contains('TextField') ||
           type.contains('TextFormField') ||
           type.contains('Checkbox') ||
           type.contains('Switch') ||
           type.contains('Slider') ||
           type.contains('ListTile') ||
           type.contains('PopupMenu') ||
           type.contains('DropdownButton') ||
           type.contains('IconButton') ||
           type.contains('FloatingActionButton') ||
           // Rich text editors
           type.contains('SuperEditor') ||
           type.contains('SuperTextField') ||
           type.contains('SuperTextLayout') ||
           type.contains('SuperReader') ||
           type.contains('QuillEditor') ||
           type.contains('EditableText') ||
           // Menu items (when menus are open)
           type.contains('PopupMenuItem') ||
           type.contains('DropdownMenuItem') ||
           type.contains('MenuItemButton') ||
           type.contains('SubmenuButton') ||
           type.contains('MenuAnchor') ||
           // Drawer components
           type.contains('DrawerController') ||
           type.contains('Drawer') ||
           type.contains('NavigationDrawer') ||
           type.contains('NavigationRail');
  }

  /// Check if a widget type is overlay-specific
  bool _isOverlayWidgetType(String typeName) {
    return typeName.contains('PopupMenuItem') ||
           typeName.contains('DropdownMenuItem') ||
           typeName.contains('MenuItemButton') ||
           typeName.contains('_DropdownRoute') ||
           typeName.contains('_PopupMenuRoute') ||
           typeName.contains('_MenuItem') ||
           typeName.contains('DropdownButtonFormField') ||
           typeName.contains('MenuAnchor') ||
           typeName.contains('SubmenuButton') ||
           typeName.contains('DrawerController') ||
           typeName.contains('Drawer') ||
           typeName.contains('EndDrawer') ||
           typeName.contains('NavigationDrawer') ||
           typeName.contains('ModalBarrier') ||
           typeName.contains('_ModalScope') ||
           typeName.contains('BottomSheet') ||
           typeName.contains('Dialog') ||
           typeName.contains('AlertDialog') ||
           typeName.contains('SimpleDialog');
  }

  /// Classify the type of overlay
  String _classifyOverlayType(String typeName) {
    if (typeName.contains('Dropdown')) return 'dropdown';
    if (typeName.contains('PopupMenu')) return 'popup_menu';
    if (typeName.contains('Menu')) return 'menu';
    if (typeName.contains('Drawer')) return 'drawer';
    if (typeName.contains('BottomSheet')) return 'bottom_sheet';
    if (typeName.contains('Dialog')) return 'dialog';
    if (typeName.contains('Modal')) return 'modal';
    return 'overlay';
  }

  FapElement? _createElementBasedFapElement(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }

    try {
      // Get global bounds
      final transform = renderObject.getTransformTo(null);
      final globalRect = MatrixUtils.transformRect(
        transform,
        Offset.zero & renderObject.size,
      );

      // Skip if zero-size
      if (globalRect.width <= 0 || globalRect.height <= 0) return null;

      final id = 'fap-elem-${element.hashCode}';
      final widget = element.widget;

      // Extract key
      String? key;
      if (widget.key != null) {
        final keyObj = widget.key!;
        if (keyObj is ValueKey<String>) {
          key = keyObj.value;
        } else {
          String keyStr = keyObj.toString();
          // Clean up key format
          if (keyStr.startsWith("[<'") && keyStr.endsWith("'>]")) {
            keyStr = keyStr.substring(3, keyStr.length - 3);
          } else if (keyStr.startsWith("[<") && keyStr.endsWith(">]")) {
            keyStr = keyStr.substring(2, keyStr.length - 2);
          }
          key = keyStr;
        }
      }

      // Extract type
      final type = widget.runtimeType.toString();

      // Try to extract text/label from common widget types
      String? label;
      String? value;
      _extractWidgetContent(widget, (l, v) {
        label = l;
        value = v;
      });

      return FapElement(
        id: id,
        node: null,
        widgetElement: element,
        globalRect: globalRect,
        source: FapElementSource.element,
        type: type,
        key: key,
        label: label,
        value: value,
      );
    } catch (e) {
      debugPrint('Error creating FapElement from Element: $e');
      return null;
    }
  }

  void _extractWidgetContent(Widget widget, void Function(String?, String?) callback) {
    final type = widget.runtimeType.toString();

    try {
      final dynamic dyn = widget;

      // Text widgets
      if (type.contains('Text') && !type.contains('TextField')) {
        try {
          final data = dyn.data as String?;
          callback(data, null);
          return;
        } catch (_) {}
      }

      // ElevatedButton, TextButton, OutlinedButton - try to get child text
      if (type.contains('Button')) {
        try {
          final child = dyn.child;
          if (child != null && child.runtimeType.toString().contains('Text')) {
            callback((child as dynamic).data, null);
            return;
          }
        } catch (_) {}
      }

      // ListTile
      if (type == 'ListTile') {
        try {
          final title = dyn.title;
          if (title != null && title.runtimeType.toString().contains('Text')) {
            callback((title as dynamic).data, null);
            return;
          }
        } catch (_) {}
      }
    } catch (_) {}

    callback(null, null);
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
      // Only semantics-based elements support hierarchical traversal
      if (match.node == null) continue;

      if (selector.combinator == SelectorCombinator.child) {
        // Direct children
        match.node!.visitChildren((child) {
          final childElement = _nodeIdToElement[child.id];
          if (childElement != null) {
            nextScope.add(childElement);
          }
          return true;
        });
      } else if (selector.combinator == SelectorCombinator.descendant) {
        // All descendants
        _collectDescendants(match.node!, nextScope);
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

  /// Normalize whitespace for matching (collapses newlines, tabs, multiple spaces)
  String _normalizeForMatching(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Check if selector text matches field value with normalization and partial matching
  bool _textMatches(String? fieldValue, String? selectorText) {
    if (fieldValue == null || selectorText == null) return false;

    // Fast path: exact match
    if (fieldValue == selectorText) return true;

    // Normalized matching (handles multiline labels like "Project Title\nMy Amazing Novel")
    final normalizedField = _normalizeForMatching(fieldValue);
    final normalizedSelector = _normalizeForMatching(selectorText);

    // Normalized exact match
    if (normalizedField == normalizedSelector) return true;

    // Contains match (selector is substring of normalized field)
    // e.g., "Project Title" matches "Project Title My Amazing Novel"
    if (normalizedField.contains(normalizedSelector)) return true;

    return false;
  }

  bool _matches(FapElement element, Selector selector) {
    // Get semantics data if available
    final data = element.node?.getSemanticsData();

    // For element-based discovery, use extracted label/value
    final label = data?.label ?? element.label ?? '';
    final value = data?.value ?? element.value ?? '';
    final hint = data?.hint ?? '';

    // Match ID
    if (selector.id != null && element.id != selector.id) return false;

    // Match Text / Label (with normalization and partial matching)
    if (selector.text != null &&
        !_textMatches(label, selector.text) &&
        !_textMatches(value, selector.text) &&
        !_textMatches(hint, selector.text))
      return false;
    if (selector.label != null && !_textMatches(label, selector.label)) return false;

    // Match Role (only for semantics-based elements)
    if (selector.role != null) {
      // Element-based elements don't have semantic roles
      if (element.node == null) return false;

      final role = selector.role!;
      bool roleMatched = false;

      // Map common roles to SemanticsFlags
      switch (role) {
        case 'button':
          if (element.node!.hasFlag(SemanticsFlag.isButton)) roleMatched = true;
          break;
        case 'textField':
          if (element.node!.hasFlag(SemanticsFlag.isTextField))
            roleMatched = true;
          break;
        case 'slider':
          if (element.node!.hasFlag(SemanticsFlag.isSlider)) roleMatched = true;
          break;
        case 'switch':
        case 'toggle':
          if (element.node!.hasFlag(SemanticsFlag.hasToggledState))
            roleMatched = true;
          break;
        case 'checkbox':
          if (element.node!.hasFlag(SemanticsFlag.hasCheckedState))
            roleMatched = true;
          break;
        case 'image':
          if (element.node!.hasFlag(SemanticsFlag.isImage)) roleMatched = true;
          break;
        case 'header':
          if (element.node!.hasFlag(SemanticsFlag.isHeader)) roleMatched = true;
          break;
        case 'link':
          if (element.node!.hasFlag(SemanticsFlag.isLink)) roleMatched = true;
          break;
        case 'list':
          // Heuristic: has children and scrollable?
          // SemanticsFlag doesn't have explicit 'isList'.
          // But we can check if it's a scroll container?
          // For now, let's stick to explicit flags.
          break;
        default:
          // Try to match flag name case-insensitively
          for (final flag in SemanticsFlag.values) {
            if (flag.toString().split('.').last.toLowerCase() ==
                role.toLowerCase()) {
              if (element.node!.hasFlag(flag)) roleMatched = true;
              break;
            }
            // Also try 'is' prefix removal (e.g. role='button' matches isButton)
            if (flag.toString().split('.').last.toLowerCase() ==
                'is${role.toLowerCase()}') {
              if (element.node!.hasFlag(flag)) roleMatched = true;
              break;
            }
          }
      }
      if (!roleMatched) return false;
    }

    // Match Key
    if (selector.key != null) {
      if (element.key != selector.key) return false;
    }

    // Match Type
    if (selector.type != null) {
      if (element.type != selector.type) return false;
    }

    // Match Attributes (with normalized matching)
    for (final entry in selector.attributes.entries) {
      // Check metadata first
      if (element.metadata.containsKey(entry.key)) {
        if (!_textMatches(element.metadata[entry.key], entry.value)) return false;
        continue;
      }
      // Fallback to semantics data (with normalization)
      if (!_textMatches(label, entry.value) &&
          !_textMatches(value, entry.value) &&
          !_textMatches(hint, entry.value))
        return false;
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
          if (pattern.hasMatch(label)) matched = true;
        }
        if (entry.key == 'text' || entry.key == 'value') {
          if (pattern.hasMatch(value)) matched = true;
        }
        if (entry.key == 'text' || entry.key == 'hint') {
          if (pattern.hasMatch(hint)) matched = true;
        }
        if (entry.key == 'key' && element.key != null) {
          if (pattern.hasMatch(element.key!)) matched = true;
        }
        if (entry.key == 'type' && element.type != null) {
          if (pattern.hasMatch(element.type!)) matched = true;
        }
      }

      if (!matched) {
        print(
          'Regex mismatch: ${entry.key}=${pattern.pattern} against label="$label", value="$value"',
        );
        return false;
      }
    }

    return true;
  }

  FapElement? hitTest(Offset point) {
    // Iterate in reverse order (top-most first usually, though semantics order isn't strictly z-order)
    // Actually, semantics traversal is usually paint order.
    // We want the deepest child that contains the point.
    // Since we flatten the tree into _elements, we don't have hierarchy easily accessible for hit testing
    // without re-traversing or keeping parent links.
    // However, smaller elements usually sit on top of larger ones.

    FapElement? bestMatch;
    // Heuristic score: lower is better
    double bestScore = double.infinity;

    for (final element in _elements.values) {
      if (element.globalRect.contains(point) && element.isInteractable) {
        final area = element.globalRect.width * element.globalRect.height;

        // Base score is area
        double score = area;

        // Penalty for containers (elements with children usually)
        // We don't have child count here easily, but we can check if it has a tap action.
        // Bonus for having a tap action (makes score smaller)
        if (element.node != null &&
            element.node!.getSemanticsData().hasAction(SemanticsAction.tap)) {
          score *= 0.5; // Prioritize tappable elements significantly
        } else if (element.source == FapElementSource.element) {
          // Element-based widgets are likely interactable buttons/etc
          score *= 0.6;
        }

        if (score < bestScore) {
          bestScore = score;
          bestMatch = element;
        }
      }
    }
    return bestMatch;
  }

  Map<String, dynamic> computeDiff() {
    final added = <Map<String, dynamic>>[];
    final removed = <String>[];
    final updated = <Map<String, dynamic>>[];

    // 1. Find Added and Updated
    for (final entry in _elements.entries) {
      final id = entry.key;
      final element = entry.value;

      if (!_previousElements.containsKey(id)) {
        // New element
        added.add(element.toJson());
      } else {
        // Existing element, check for changes
        final prev = _previousElements[id]!;
        if (_hasChanged(prev, element)) {
          updated.add(element.toJson());
        }
      }
    }

    // 2. Find Removed
    for (final id in _previousElements.keys) {
      if (!_elements.containsKey(id)) {
        removed.add(id);
      }
    }

    return {'added': added, 'removed': removed, 'updated': updated};
  }

  bool _hasChanged(FapElement prev, FapElement curr) {
    // Compare essential fields
    if (prev.type != curr.type) return true;
    if (prev.key != curr.key) return true;
    if (prev.source != curr.source) return true;

    // Semantics Data (only if both have nodes)
    if (prev.node != null && curr.node != null) {
      final prevData = prev.node!.getSemanticsData();
      final currData = curr.node!.getSemanticsData();

      if (prevData.label != currData.label) return true;
      if (prevData.value != currData.value) return true;
      if (prevData.hint != currData.hint) return true;
      if (prevData.tooltip != currData.tooltip) return true;
      if (prevData.actions != currData.actions) return true;
      if (prevData.flags != currData.flags) return true;
    } else if (prev.node != null || curr.node != null) {
      // One has node, other doesn't - definitely changed
      return true;
    } else {
      // Both are element-based, compare extracted label/value
      if (prev.label != curr.label) return true;
      if (prev.value != curr.value) return true;
    }

    // Rect
    if (prev.globalRect != curr.globalRect) return true;

    // Metadata
    if (prev.metadata.length != curr.metadata.length) return true;
    for (final key in prev.metadata.keys) {
      if (prev.metadata[key] != curr.metadata[key]) return true;
    }

    return false;
  }
}
