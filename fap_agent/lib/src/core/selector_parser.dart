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

    // Simple parser for now: key=value pairs separated by &
    // e.g. "text=Submit & role=button"
    // or "id=fap-1"
    
    var processedInput = input.trim();
    
    // 1. Check for CSS-style selector: Type[attr=val]
    // e.g. Button[text="Save"]
    final cssRegex = RegExp(r'^([a-zA-Z0-9_]+)\[(.*)\]$');
    final match = cssRegex.firstMatch(processedInput);
    if (match != null) {
      type = match.group(1);
      processedInput = match.group(2) ?? '';
    }

    // 2. Parse attributes (key=value pairs)
    // e.g. "text=Submit & role=button"
    // or inside brackets: "text="Save""
    
    // Split by & or just parse the remaining string
    // If it was a CSS selector, processedInput is the content inside []
    
    final parts = processedInput.split(RegExp(r'[&,]')); // Allow & or , as separator
    for (var part in parts) {
      part = part.trim();
      if (part.isEmpty) continue;

      final kv = part.split('=');
      if (kv.length == 2) {
        final k = kv[0].trim();
        var v = kv[1].trim();
        
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
            type = v; // Allow overriding type if specified explicitly
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
}
