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
class FapMeta extends ProxyWidget {
  final Map<String, String> metadata;

  const FapMeta({
    super.key,
    required this.metadata,
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
