import 'selector_parser.dart';
import 'semantics_index.dart';

class SelectorGenerator {
  /// Generates a stable selector for the given [element].
  /// 
  /// Priorities:
  /// 1. Key (if it looks stable, e.g., not containing #hash)
  /// 2. Text/Label (if unique enough)
  /// 3. Type + Text
  /// 4. Tooltip
  /// 5. Type + Index (fallback)
  static String generate(FapElement element, SemanticsIndexer indexer) {
    // 1. Key
    if (element.key != null && element.key!.isNotEmpty) {
      if (_isStableKey(element.key!)) {
        return 'key="${element.key}"';
      }
    }

    // Get text from semantics data or element properties
    String text = '';
    String tooltip = '';

    if (element.node != null) {
      final data = element.node!.getSemanticsData();
      text = data.label.isNotEmpty ? data.label : (data.value.isNotEmpty ? data.value : data.hint);
      tooltip = data.tooltip;
    } else {
      // For element-based discovery, use extracted label/value
      text = element.label ?? element.value ?? '';
    }

    // 2. Text / Label
    if (text.isNotEmpty) {
      final escapedText = text.replaceAll('"', '\\"');
      final selector = 'text="$escapedText"';

      // Verify uniqueness
      if (_isUnique(selector, indexer)) {
        return selector;
      }
    }

    // 3. Tooltip (only for semantics-based elements)
    if (tooltip.isNotEmpty) {
       final escapedTooltip = tooltip.replaceAll('"', '\\"');
       final selector = 'tooltip="$escapedTooltip"';
       if (_isUnique(selector, indexer)) {
         return selector;
       }
    }

    // 4. Type (fallback)
    if (element.type != null) {
       // Try adding text to type for uniqueness
       if (text.isNotEmpty) {
         final escapedText = text.replaceAll('"', '\\"');
         final selector = '${element.type}[text="$escapedText"]';
         if (_isUnique(selector, indexer)) {
           return selector;
         }
       }
       return 'type="${element.type}"';
    }

    // 5. ID (Last resort, but unstable across runs)
    // We try to avoid this for recording.
    return 'id="${element.id}"';
  }

  static bool _isUnique(String selectorString, SemanticsIndexer indexer) {
    try {
      final selector = Selector.parse(selectorString);
      final matches = indexer.find(selector);
      return matches.length == 1;
    } catch (e) {
      return false;
    }
  }

  static bool _isStableKey(String key) {
    // Heuristic: keys with # usually imply hash codes (e.g. "[<'foo'>#123]")
    // But FapElement.key logic already tries to clean that up.
    // If it still contains #, it might be unstable.
    if (key.contains('#')) return false;
    
    // Very short numeric keys might be list indices, which are okay-ish but maybe not unique globally.
    // But if the user assigned Key('my_btn'), it's good.
    return true;
  }
}
