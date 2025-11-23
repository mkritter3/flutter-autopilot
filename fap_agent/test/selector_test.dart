import 'package:fap_agent/src/core/selector_parser.dart';
import 'package:test/test.dart';

void main() {
  group('Selector Parser', () {
    test('parses simple key selector', () {
      final s = Selector.parse('key=myKey');
      expect(s.key, equals('myKey'));
    });

    test('parses simple role selector', () {
      final s = Selector.parse('role=button');
      expect(s.role, equals('button'));
    });

    test('parses quoted text selector', () {
      final s = Selector.parse('text="Hello World"');
      expect(s.text, equals('Hello World'));
    });

    test('parses combined selector (AND)', () {
      final s = Selector.parse('role=button & text="Save"');
      expect(s.role, equals('button'));
      expect(s.text, equals('Save'));
    });

    test('parses CSS-style selector', () {
      final s = Selector.parse('Button[text="Save"]');
      expect(s.type, equals('Button'));
      expect(s.text, equals('Save'));
    });

    test('parses multiple attributes', () {
      final s = Selector.parse('type=Card & key=card1 & label="My Card"');
      expect(s.type, equals('Card'));
      expect(s.key, equals('card1'));
      expect(s.label, equals('My Card'));
    });
  });
}
