import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Handler for menus, drawers, and overlay-based UI components
///
/// This handler discovers and tracks:
/// - DropdownButton / DropdownMenu (Material 3)
/// - PopupMenuButton / PopupMenu
/// - Drawer / NavigationDrawer
/// - BottomSheet
/// - Dialog / AlertDialog
///
/// Key insight: When these components are opened, they create widgets
/// in Flutter's Overlay system. This handler provides methods to:
/// - Discover menu triggers
/// - Track overlay state
/// - Get overlay content when menus are open
class MenuDiscoveryHandler {
  static final MenuDiscoveryHandler instance = MenuDiscoveryHandler._();
  MenuDiscoveryHandler._();

  // Track known menu triggers
  final Map<int, MenuTriggerRef> _menuTriggers = {};

  // Track current overlay state
  List<OverlayContentRef> _currentOverlayContent = [];
  int _overlayEntryCount = 0;
  bool _initialized = false;

  // Polling for overlay changes
  Timer? _pollTimer;

  /// Initialize overlay tracking with optional polling
  void initialize({bool enablePolling = false}) {
    if (_initialized) return;
    _initialized = true;

    if (enablePolling) {
      _startOverlayPolling();
    }

    debugPrint('MenuDiscoveryHandler: Initialized');
  }

  void _startOverlayPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _checkOverlayState();
    });
  }

  /// Check current overlay state
  void _checkOverlayState() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;

    final newOverlayContent = <OverlayContentRef>[];
    int entryCount = 0;

    void visit(Element element) {
      final typeName = element.widget.runtimeType.toString();

      // Count overlay entries
      if (typeName.contains('_OverlayEntryWidget') ||
          typeName.contains('_Theater')) {
        entryCount++;
      }

      // Detect overlay content (menu items, etc.)
      if (_isOverlayContent(typeName)) {
        final ref = _createOverlayContentRef(element, typeName);
        if (ref != null) {
          newOverlayContent.add(ref);
        }
      }

      element.visitChildren(visit);
    }

    visit(root);

    _overlayEntryCount = entryCount;
    _currentOverlayContent = newOverlayContent;
  }

  /// Check if a widget type is overlay content
  bool _isOverlayContent(String typeName) {
    return typeName.contains('_DropdownRoutePage') ||
        typeName.contains('_DropdownMenu') ||
        typeName.contains('_PopupMenuRouteLayout') ||
        typeName.contains('PopupMenuItem') ||
        typeName.contains('DropdownMenuItem') ||
        typeName.contains('MenuItemButton') ||
        typeName.contains('SubmenuButton') ||
        typeName.contains('_ModalBottomSheetRoute') ||
        typeName.contains('_DialogRoute') ||
        typeName.contains('AlertDialog') ||
        typeName.contains('SimpleDialog') ||
        typeName.contains('_ModalBarrier');
  }

  /// Create a reference to overlay content
  OverlayContentRef? _createOverlayContentRef(Element element, String typeName) {
    try {
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

      // Try to extract label from menu item
      String? label;
      bool isEnabled = true;

      try {
        final dynamic dynWidget = element.widget;

        // PopupMenuItem has 'child' which is often Text
        try {
          final child = dynWidget.child;
          if (child != null &&
              child.runtimeType.toString().contains('Text')) {
            label = (child as dynamic).data;
          }
        } catch (_) {}

        // Check enabled state
        try {
          isEnabled = dynWidget.enabled ?? true;
        } catch (_) {}

        // DropdownMenuItem has 'value' and 'child'
        try {
          if (label == null) {
            final child = dynWidget.child;
            if (child != null) {
              // Try to extract text from child
              _extractTextFromWidget(child, (text) {
                label = text;
              });
            }
          }
        } catch (_) {}
      } catch (_) {}

      return OverlayContentRef(
        id: element.hashCode,
        type: typeName,
        bounds: bounds ?? Rect.zero,
        label: label,
        isEnabled: isEnabled,
        overlayType: _classifyOverlayType(typeName),
      );
    } catch (_) {
      return null;
    }
  }

  /// Recursively extract text from a widget
  void _extractTextFromWidget(dynamic widget, void Function(String) callback) {
    if (widget == null) return;

    final typeName = widget.runtimeType.toString();

    if (typeName.contains('Text') && !typeName.contains('TextField')) {
      try {
        final data = (widget as dynamic).data;
        if (data != null) {
          callback(data);
          return;
        }
      } catch (_) {}
    }

    // Try child
    try {
      final child = (widget as dynamic).child;
      if (child != null) {
        _extractTextFromWidget(child, callback);
      }
    } catch (_) {}
  }

  /// Classify the type of overlay
  String _classifyOverlayType(String typeName) {
    if (typeName.contains('Dropdown')) return 'dropdown';
    if (typeName.contains('PopupMenu')) return 'popup_menu';
    if (typeName.contains('MenuItem') || typeName.contains('Menu')) {
      return 'menu_item';
    }
    if (typeName.contains('Drawer')) return 'drawer';
    if (typeName.contains('BottomSheet')) return 'bottom_sheet';
    if (typeName.contains('Dialog')) return 'dialog';
    if (typeName.contains('ModalBarrier')) return 'modal_barrier';
    return 'overlay';
  }

  /// Discover all menu/drawer triggers in the widget tree
  List<MenuTriggerRef> discoverMenuTriggers() {
    final results = <MenuTriggerRef>[];
    _menuTriggers.clear();

    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return results;

    void visit(Element element) {
      final typeName = element.widget.runtimeType.toString();

      if (_isMenuTrigger(typeName)) {
        final ref = _createMenuTriggerRef(element, typeName);
        if (ref != null) {
          results.add(ref);
          _menuTriggers[element.hashCode] = ref;
        }
      }

      element.visitChildren(visit);
    }

    visit(root);
    debugPrint('MenuDiscoveryHandler: Found ${results.length} menu triggers');
    return results;
  }

  /// Check if a widget type is a menu trigger
  bool _isMenuTrigger(String typeName) {
    return typeName.contains('DropdownButton') ||
        typeName.contains('PopupMenuButton') ||
        typeName.contains('MenuAnchor') ||
        typeName.contains('DrawerButton') ||
        typeName == 'IconButton'; // Could be hamburger menu
  }

  /// Create a reference to a menu trigger
  MenuTriggerRef? _createMenuTriggerRef(Element element, String typeName) {
    try {
      final widget = element.widget;

      // Determine trigger type
      MenuTriggerType type = MenuTriggerType.popupMenu;
      if (typeName.contains('Dropdown')) {
        type = MenuTriggerType.dropdown;
      } else if (typeName.contains('Drawer')) {
        type = MenuTriggerType.drawer;
      } else if (typeName.contains('MenuAnchor')) {
        type = MenuTriggerType.menuAnchor;
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

      // Try to get label
      String? label;
      try {
        final dynamic dynWidget = widget;
        // DropdownButton has 'hint' and 'value'
        try {
          final hint = dynWidget.hint;
          if (hint != null) {
            _extractTextFromWidget(hint, (text) {
              label = text;
            });
          }
        } catch (_) {}

        try {
          if (label == null) {
            final value = dynWidget.value;
            if (value != null) {
              label = value.toString();
            }
          }
        } catch (_) {}

        // PopupMenuButton might have tooltip
        try {
          if (label == null) {
            label = dynWidget.tooltip as String?;
          }
        } catch (_) {}
      } catch (_) {}

      return MenuTriggerRef(
        id: element.hashCode,
        type: type,
        element: element,
        bounds: bounds ?? Rect.zero,
        label: label,
      );
    } catch (_) {
      return null;
    }
  }

  /// Get current overlay state
  OverlayState getCurrentOverlayState() {
    _checkOverlayState();

    return OverlayState(
      entryCount: _overlayEntryCount,
      hasOverlay: _currentOverlayContent.isNotEmpty,
      contentCount: _currentOverlayContent.length,
      content: _currentOverlayContent,
    );
  }

  /// Get all current overlay content
  List<OverlayContentRef> getOverlayContent() {
    _checkOverlayState();
    return List.unmodifiable(_currentOverlayContent);
  }

  /// Check if any overlay is currently visible
  bool get hasVisibleOverlay {
    _checkOverlayState();
    return _currentOverlayContent.isNotEmpty;
  }

  /// Wait for an overlay to appear (with timeout)
  Future<OverlayWaitResult> waitForOverlay({
    int timeoutMs = 2000,
    int pollIntervalMs = 50,
  }) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));

    while (DateTime.now().isBefore(deadline)) {
      _checkOverlayState();

      if (_currentOverlayContent.isNotEmpty) {
        return OverlayWaitResult(
          found: true,
          content: _currentOverlayContent,
          entryCount: _overlayEntryCount,
        );
      }

      await Future.delayed(Duration(milliseconds: pollIntervalMs));
    }

    return OverlayWaitResult(
      found: false,
      content: [],
      entryCount: _overlayEntryCount,
      timedOut: true,
    );
  }

  /// Get drawer state via ScaffoldState
  DrawerState getDrawerState() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return DrawerState(
        hasScaffold: false,
        isDrawerOpen: false,
        isEndDrawerOpen: false,
      );
    }

    bool hasScaffold = false;
    bool isDrawerOpen = false;
    bool isEndDrawerOpen = false;

    void visit(Element element) {
      if (element is StatefulElement) {
        final stateType = element.state.runtimeType.toString();

        if (stateType.contains('ScaffoldState')) {
          hasScaffold = true;
          try {
            final dynamic state = element.state;
            isDrawerOpen = state.isDrawerOpen as bool? ?? false;
            isEndDrawerOpen = state.isEndDrawerOpen as bool? ?? false;
          } catch (e) {
            debugPrint('MenuDiscoveryHandler: Error reading ScaffoldState: $e');
          }
          return; // Found scaffold, stop searching
        }
      }

      element.visitChildren(visit);
    }

    visit(root);

    return DrawerState(
      hasScaffold: hasScaffold,
      isDrawerOpen: isDrawerOpen,
      isEndDrawerOpen: isEndDrawerOpen,
    );
  }

  /// Open drawer programmatically
  Future<Map<String, dynamic>> openDrawer({bool endDrawer = false}) async {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return {'success': false, 'error': 'No root element'};
    }

    ScaffoldState? scaffoldState;

    void visit(Element element) {
      if (element is StatefulElement) {
        if (element.state is ScaffoldState) {
          scaffoldState = element.state as ScaffoldState;
          return;
        }
      }
      if (scaffoldState == null) {
        element.visitChildren(visit);
      }
    }

    visit(root);

    if (scaffoldState == null) {
      return {'success': false, 'error': 'No Scaffold found'};
    }

    try {
      if (endDrawer) {
        scaffoldState!.openEndDrawer();
      } else {
        scaffoldState!.openDrawer();
      }

      return {
        'success': true,
        'drawer': endDrawer ? 'end' : 'start',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Close any open drawer
  Future<Map<String, dynamic>> closeDrawer() async {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return {'success': false, 'error': 'No root element'};
    }

    ScaffoldState? scaffoldState;

    void visit(Element element) {
      if (element is StatefulElement) {
        if (element.state is ScaffoldState) {
          scaffoldState = element.state as ScaffoldState;
          return;
        }
      }
      if (scaffoldState == null) {
        element.visitChildren(visit);
      }
    }

    visit(root);

    if (scaffoldState == null) {
      return {'success': false, 'error': 'No Scaffold found'};
    }

    try {
      // Close drawer by popping the route if a drawer is open
      final drawerState = getDrawerState();
      if (drawerState.isDrawerOpen || drawerState.isEndDrawerOpen) {
        // Navigator.pop() is usually how drawers are closed
        // But ScaffoldState doesn't expose a close method directly
        // The drawer closes automatically when tapping outside or pressing back
        return {
          'success': false,
          'error': 'Use Navigator.pop() or tap outside to close drawer',
          'hint': 'Drawers are closed via route popping, not directly',
        };
      }

      return {
        'success': true,
        'message': 'No drawer was open',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _menuTriggers.clear();
    _currentOverlayContent.clear();
    _initialized = false;
  }
}

/// Reference to a menu trigger widget
class MenuTriggerRef {
  final int id;
  final MenuTriggerType type;
  final Element element;
  final Rect bounds;
  final String? label;

  MenuTriggerRef({
    required this.id,
    required this.type,
    required this.element,
    required this.bounds,
    this.label,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'label': label,
        'bounds': {
          'x': bounds.left,
          'y': bounds.top,
          'w': bounds.width,
          'h': bounds.height,
        },
      };
}

enum MenuTriggerType {
  dropdown,
  popupMenu,
  menuAnchor,
  drawer,
  bottomSheet,
}

/// Reference to overlay content (menu items, etc.)
class OverlayContentRef {
  final int id;
  final String type;
  final Rect bounds;
  final String? label;
  final bool isEnabled;
  final String overlayType;

  OverlayContentRef({
    required this.id,
    required this.type,
    required this.bounds,
    this.label,
    required this.isEnabled,
    required this.overlayType,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'overlayType': overlayType,
        'label': label,
        'isEnabled': isEnabled,
        'bounds': {
          'x': bounds.left,
          'y': bounds.top,
          'w': bounds.width,
          'h': bounds.height,
        },
      };
}

/// Current state of overlay system
class OverlayState {
  final int entryCount;
  final bool hasOverlay;
  final int contentCount;
  final List<OverlayContentRef> content;

  OverlayState({
    required this.entryCount,
    required this.hasOverlay,
    required this.contentCount,
    required this.content,
  });

  Map<String, dynamic> toJson() => {
        'entryCount': entryCount,
        'hasOverlay': hasOverlay,
        'contentCount': contentCount,
        'content': content.map((c) => c.toJson()).toList(),
      };
}

/// Result of waiting for overlay
class OverlayWaitResult {
  final bool found;
  final List<OverlayContentRef> content;
  final int entryCount;
  final bool timedOut;

  OverlayWaitResult({
    required this.found,
    required this.content,
    required this.entryCount,
    this.timedOut = false,
  });

  Map<String, dynamic> toJson() => {
        'found': found,
        'timedOut': timedOut,
        'entryCount': entryCount,
        'contentCount': content.length,
        'content': content.map((c) => c.toJson()).toList(),
      };
}

/// State of drawer
class DrawerState {
  final bool hasScaffold;
  final bool isDrawerOpen;
  final bool isEndDrawerOpen;

  DrawerState({
    required this.hasScaffold,
    required this.isDrawerOpen,
    required this.isEndDrawerOpen,
  });

  Map<String, dynamic> toJson() => {
        'hasScaffold': hasScaffold,
        'isDrawerOpen': isDrawerOpen,
        'isEndDrawerOpen': isEndDrawerOpen,
        'anyDrawerOpen': isDrawerOpen || isEndDrawerOpen,
      };
}
