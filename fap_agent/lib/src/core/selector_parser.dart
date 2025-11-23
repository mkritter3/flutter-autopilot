enum SelectorCombinator {
  descendant,
  child,
}

class Selector {
  final String? id;
  final String? text;
  final String? label;
  final String? role;
  final String? key;
  final String? type;
  final Map<String, String> attributes;
  final Map<String, RegExp> regexAttributes;
  
  final Selector? next;
  final SelectorCombinator? combinator;

  Selector({
    this.id,
    this.text,
    this.label,
    this.role,
    this.key,
    this.type,
    this.attributes = const {},
    this.regexAttributes = const {},
    this.next,
    this.combinator,
  });

  static final Map<String, Selector> _cache = {};

  static Selector parse(String input) {
    if (_cache.containsKey(input)) {
      return _cache[input]!;
    }

    final tokens = _tokenize(input);
    if (tokens.isEmpty) return Selector();

    final selector = _buildChain(tokens);
    _cache[input] = selector;
    return selector;
  }

  static Selector _buildChain(List<String> tokens) {
    // Tokens are alternating: [SelectorStr, Combinator, SelectorStr, ...]
    // But my tokenizer might just return selector strings and I need to handle combinators.
    // Let's make _tokenize return a list of (String, Combinator?) tuples or similar.
    // Simplified: _tokenize returns [SelectorStr, CombinatorStr, SelectorStr...]
    
    // Actually, let's parse the first selector, then if there are more tokens, recurse.
    
    final currentStr = tokens[0];
    final current = _parseSingle(currentStr);
    
    if (tokens.length > 1) {
      final combinatorStr = tokens[1];
      final combinator = combinatorStr == '>' ? SelectorCombinator.child : SelectorCombinator.descendant;
      
      final remainingTokens = tokens.sublist(2);
      final nextSelector = _buildChain(remainingTokens);
      
      return Selector(
        id: current.id,
        text: current.text,
        label: current.label,
        role: current.role,
        key: current.key,
        type: current.type,
        attributes: current.attributes,
        regexAttributes: current.regexAttributes,
        next: nextSelector,
        combinator: combinator,
      );
    }
    
    return current;
  }

  static Selector _parseSingle(String input) {
    String? id;
    String? text;
    String? label;
    String? role;
    String? key;
    String? type;
    final Map<String, String> attributes = {};
    final Map<String, RegExp> regexAttributes = {};

    var processedInput = input.trim();
    
    // 1. Check for CSS-style selector: Type[attr=val]
    final cssRegex = RegExp(r'^([a-zA-Z0-9_]+)\[(.*)\]$');
    final match = cssRegex.firstMatch(processedInput);
    if (match != null) {
      type = match.group(1);
      processedInput = match.group(2) ?? '';
    }

    // 2. Parse attributes
    final parts = _splitAttributes(processedInput);
    for (var part in parts) {
      part = part.trim();
      if (part.isEmpty) continue;

      final kv = part.split('=');
      if (kv.length >= 2) {
        final k = kv[0].trim();
        var v = kv.sublist(1).join('=').trim(); // Handle values with =
        
        // Remove quotes and unescape
        if ((v.startsWith('"') && v.endsWith('"'))) {
          v = v.substring(1, v.length - 1).replaceAll(r'\"', '"');
        } else if ((v.startsWith("'") && v.endsWith("'"))) {
          v = v.substring(1, v.length - 1).replaceAll(r"\'", "'");
        }

        // Check for regex value: ~/pattern/
        if (v.startsWith('~/') && v.endsWith('/')) {
          final pattern = v.substring(2, v.length - 1);
          regexAttributes[k] = RegExp(pattern);
          continue;
        }

        switch (k) {
          case 'id': id = v; break;
          case 'text': text = v; break;
          case 'label': label = v; break;
          case 'role': role = v; break;
          case 'key': key = v; break;
          case 'type': type = v; break;
          default: attributes[k] = v;
        }
      } else {
        // No '=' found, check if it's a bare type name
        if (type == null && RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(part)) {
          type = part;
        }
      }
    }

    print('Parsed Selector: input="$input" -> attributes=$attributes, regexAttributes=$regexAttributes');
    return Selector(
      id: id,
      text: text,
      label: label,
      role: role,
      key: key,
      type: type,
      attributes: attributes,
      regexAttributes: regexAttributes,
    );
  }

  static List<String> _tokenize(String input) {
    // First, check if this is a single selector with attribute separators (&, ,)
    // or if it contains actual combinator syntax (>, or spaces between distinct selectors)
    bool hasAttributeSeparators = false;
    bool inQuote = false;
    bool inBracket = false;

    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      if (char == '"' || char == "'") {
        inQuote = !inQuote;
      } else if (char == '[' && !inQuote) {
        inBracket = true;
      } else if (char == ']' && !inQuote) {
        inBracket = false;
      } else if (!inQuote && !inBracket) {
        if (char == '&' || char == ',') {
          hasAttributeSeparators = true;
          break;
        }
      }
    }

    // If has attribute separators, treat entire string as single selector
    if (hasAttributeSeparators) {
      return [input.trim()];
    }

    // Otherwise, tokenize for combinators
    final tokens = <String>[];
    var current = StringBuffer();
    inQuote = false;
    inBracket = false;
    bool inRegex = false; // New flag for regex

    for (int i = 0; i < input.length; i++) {
      final char = input[i];

      if (char == '"' || char == "'") {
        inQuote = !inQuote;
        current.write(char);
      } else if (char == '[' && !inQuote) {
        inBracket = true;
        current.write(char);
      } else if (char == ']' && !inQuote) {
        inBracket = false;
        current.write(char);
      } else if (char == '~' && !inQuote && !inBracket && !inRegex) {
        // Potential start of regex
        if (i + 1 < input.length && input[i+1] == '/') {
           inRegex = true;
           current.write(char); // write ~
           i++; // consume /
           current.write(input[i]); // write /
           continue;
        }
        current.write(char);
      } else if (char == '/' && inRegex) {
        // Potential end of regex
        // Check if previous char was not escape
        if (i > 0 && input[i-1] != '\\') {
           inRegex = false;
        }
        current.write(char);
      } else if (!inQuote && !inBracket && !inRegex) {
        if (char == '>') {
          if (current.isNotEmpty) tokens.add(current.toString().trim());
          tokens.add('>');
          current.clear();
        } else if (char == ' ') {
          if (current.isNotEmpty) {
             tokens.add(current.toString().trim());
             current.clear();
          }
        } else {
          current.write(char);
        }
      } else {
        current.write(char);
      }
    }
    if (current.isNotEmpty) tokens.add(current.toString().trim());

    // Post-process tokens to insert implicit descendant combinators
    final result = <String>[];
    for (int i = 0; i < tokens.length; i++) {
      result.add(tokens[i]);
      if (i < tokens.length - 1) {
        final curr = tokens[i];
        final next = tokens[i+1];
        if (curr != '>' && next != '>') {
          result.add(' '); // Implicit descendant
        }
      }
    }
    return result;
  }

  static List<String> _splitAttributes(String input) {
    // Split by & or , but respect quotes
    final parts = <String>[];
    var current = StringBuffer();
    bool inQuote = false;
    
    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      if (char == '"' || char == "'") {
        inQuote = !inQuote;
        current.write(char);
      } else if ((char == '&' || char == ',' || char == ' ') && !inQuote) {
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
