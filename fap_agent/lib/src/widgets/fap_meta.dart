import 'package:flutter/widgets.dart';

/// A widget that annotates its child with metadata that can be queried by FAP.
///
/// This widget does not affect the UI layout or rendering. It simply attaches
/// metadata to the element tree, which the FAP Agent extracts during indexing.
///
/// Example:
/// ```dart
/// FapMeta(
///   metadata: {'test-id': 'submit-button', 'role': 'primary'},
///   child: ElevatedButton(...),
/// )
/// ```
///
/// For marking placeholder/stub components:
/// ```dart
/// FapMeta(
///   isPlaceholder: true,
///   placeholderReason: 'Feature coming in v2.0',
///   child: ElevatedButton(
///     onPressed: null,
///     child: Text('Export PDF'),
///   ),
/// )
/// ```
class FapMeta extends ProxyWidget {
  /// Custom metadata key-value pairs
  final Map<String, String> metadata;

  /// Whether this widget is a placeholder/stub that is not yet implemented
  final bool isPlaceholder;

  /// Reason why this widget is a placeholder (e.g., "Coming in v2.0", "Requires premium")
  final String? placeholderReason;

  const FapMeta({
    super.key,
    this.metadata = const {},
    this.isPlaceholder = false,
    this.placeholderReason,
    required super.child,
  });

  @override
  Element createElement() => _FapMetaElement(this);
}

class _FapMetaElement extends ProxyElement {
  _FapMetaElement(super.widget);

  @override
  void notifyClients(covariant FapMeta oldWidget) {
    // Metadata changes don't require notifying clients (render objects)
    // as this is purely for the FAP Agent's traversal.
  }
}
