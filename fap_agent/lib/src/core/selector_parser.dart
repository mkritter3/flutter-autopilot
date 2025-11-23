class Selector {
  final String? id;
  final String? text;
  final String? label;
  final String? role;
  final String? key;
  final String? type;
  final Map<String, String> attributes;

  Selector({
    this.id,
    this.text,
    this.label,
    this.role,
    this.key,
    this.type,
    this.attributes = const {},
  });

  static Selector parse(String input) {
    String? id;
    String? text;
    String? label;
    String? role;
    String? key;
    String? type;
    final Map<String, String> attributes = {};

    var processedInput = input.trim();
    
    // 1. Check for CSS-style selector: Type[attr=val]
    final cssRegex = RegExp(r'^([a-zA-Z0-9_]+)\[(.*)\]$');
    final match = cssRegex.firstMatch(processedInput);
    if (match != null) {
      type = match.group(1);
      processedInput = match.group(2) ?? '';
    }

    // 2. Parse attributes (key=value pairs)
    final parts = _splitRespectingQuotes(processedInput);
    
    for (var part in parts) {
      part = part.trim();
      if (part.isEmpty) continue;

      final kv = part.split('=');
      if (kv.length >= 2) {
        final k = kv[0].trim();
        // Join the rest back in case value contained =
        var v = kv.sublist(1).join('=').trim();
        
        // Remove quotes if present
        if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
          v = v.substring(1, v.length - 1);
        }

        switch (k) {
          case 'id':
            id = v;
            break;
          case 'text':
            text = v;
            break;
          case 'label':
            label = v;
            break;
          case 'role':
            role = v;
            break;
          case 'key':
            key = v;
            break;
          case 'type':
            type = v;
            break;
          default:
            attributes[k] = v;
        }
      }
    }

    return Selector(
      id: id,
      text: text,
      label: label,
      role: role,
      key: key,
      type: type,
      attributes: attributes,
    );
  }

  static List<String> _splitRespectingQuotes(String input) {
    final parts = <String>[];
    final current = StringBuffer();
    bool inQuote = false;
    String? quoteChar;

    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      if ((char == '"' || char == "'") && (quoteChar == null || quoteChar == char)) {
        inQuote = !inQuote;
        quoteChar = inQuote ? char : null;
        current.write(char);
      } else if ((char == '&' || char == ',') && !inQuote) {
        if (current.isNotEmpty) parts.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }
    if (current.isNotEmpty) parts.add(current.toString());
    return parts;
  }
}
