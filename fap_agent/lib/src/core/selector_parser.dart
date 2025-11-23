class Selector {
  final String? id;
  final String? type;
  final String? key;
  final String? role;
  final String? text;
  final String? label;
  final Map<String, String> attributes;
  final List<Selector> children;
  final bool isAnd; // true for AND, false for OR logic combining children

  const Selector({
    this.id,
    this.type,
    this.key,
    this.role,
    this.text,
    this.label,
    this.attributes = const {},
    this.children = const [],
    this.isAnd = true,
  });

  static Selector parse(String input) {
    String? id;
    String? type;
    String? key;
    String? role;
    String? text;
    String? label;
    final Map<String, String> attrs = {};

    var processedInput = input.trim();

    // Check for CSS-style: Type[attrs]
    // Regex: ^([a-zA-Z0-9_]+)\[(.*)\]$
    final cssRegex = RegExp(r'^([a-zA-Z0-9_]+)\[(.*)\]$');
    final match = cssRegex.firstMatch(processedInput);
    
    if (match != null) {
      type = match.group(1);
      processedInput = match.group(2) ?? '';
    }

    // Split by '&' but respect quotes (simple split for MVP, better regex needed for robust quotes)
    // For MVP we assume no '&' inside values unless we implement a tokenizer.
    final parts = processedInput.split('&').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    for (final part in parts) {
      if (part.contains('=')) {
        final kv = part.split('=');
        final k = kv[0].trim();
        var v = kv.sublist(1).join('=').trim();
        
        // Strip quotes
        if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
          v = v.substring(1, v.length - 1);
        }

        switch (k) {
          case 'id':
            id = v;
            break;
          case 'type':
            type = v;
            break;
          case 'key':
            key = v;
            break;
          case 'role':
            role = v;
            break;
          case 'text':
            text = v;
            break;
          case 'label':
            label = v;
            break;
          default:
            attrs[k] = v;
        }
      } else {
        // If it's just a word and we haven't set type yet and it's not a key=value
        // It might be a type shorthand if we didn't use CSS syntax?
        // But let's stick to explicit for now unless it matches CSS syntax above.
      }
    }

    return Selector(
      id: id,
      type: type,
      key: key,
      role: role,
      text: text,
      label: label,
      attributes: attrs,
    );
  }
  
  @override
  String toString() {
    return 'Selector(type: $type, key: $key, role: $role, text: $text, label: $label, attrs: $attributes)';
  }
}
