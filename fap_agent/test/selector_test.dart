import 'package:flutter_test/flutter_test.dart';
import 'package:fap_agent/src/core/selector_parser.dart';

void main() {
  group('Selector Parser', () {
    test('parses simple key selector', () {
      final selector = Selector.parse('key="my_button"');
      expect(selector.key, equals('my_button'));
      expect(selector.attributes, isEmpty);
      expect(selector.next, isNull);
    });

    test('parses simple text selector', () {
      final selector = Selector.parse('text="Submit"');
      expect(selector.text, equals('Submit'));
    });

    test('parses simple label selector', () {
      final selector = Selector.parse('label="Enter Text"');
      expect(selector.label, equals('Enter Text'));
    });

    test('parses type selector with attributes', () {
      final selector = Selector.parse('ElevatedButton[text="Save"]');
      expect(selector.type, equals('ElevatedButton'));
      expect(selector.text, equals('Save'));
    });

    test('parses multiple attributes', () {
      final selector = Selector.parse('Container[key="box" label="Container"]');
      expect(selector.type, equals('Container'));
      expect(selector.key, equals('box'));
      expect(selector.label, equals('Container'));
    });

    test('parses descendant combinator', () {
      final selector = Selector.parse('Column Text');
      expect(selector.type, equals('Column'));
      expect(selector.combinator, equals(SelectorCombinator.descendant));
      expect(selector.next, isNotNull);
      expect(selector.next!.type, equals('Text'));
    });

    test('parses child combinator', () {
      final selector = Selector.parse('Column > Text');
      expect(selector.type, equals('Column'));
      expect(selector.combinator, equals(SelectorCombinator.child));
      expect(selector.next, isNotNull);
      expect(selector.next!.type, equals('Text'));
    });

    test('parses complex chain', () {
      final selector = Selector.parse('Scaffold > Column Text[key="target"]');
      
      // 1. Scaffold
      expect(selector.type, equals('Scaffold'));
      expect(selector.combinator, equals(SelectorCombinator.child));
      
      // 2. Column
      final next1 = selector.next!;
      expect(next1.type, equals('Column'));
      expect(next1.combinator, equals(SelectorCombinator.descendant));
      
      // 3. Text
      final next2 = next1.next!;
      expect(next2.type, equals('Text'));
      expect(next2.key, equals('target'));
      expect(next2.next, isNull);
    });

    test('parses regex in attributes', () {
      final selector = Selector.parse('text="~/^Dynamic ID: \\d+/"');
      expect(selector.regexAttributes, contains('text'));
      expect(selector.regexAttributes['text']!.pattern, equals('^Dynamic ID: \\d+'));
    });

    test('parses regex in type attributes', () {
      final selector = Selector.parse('Button[label=~/Submit/]');
      expect(selector.type, equals('Button'));
      expect(selector.regexAttributes, contains('label'));
      expect(selector.regexAttributes['label']!.pattern, equals('Submit'));
    });

    test('parses metadata selector', () {
      final selector = Selector.parse('test-id="my-id"');
      expect(selector.attributes['test-id'], equals('my-id'));
    });

    test('handles quotes correctly', () {
      final selector = Selector.parse('text="Hello World"');
      expect(selector.text, equals('Hello World'));
      
      final selectorSingle = Selector.parse("text='Hello World'");
      expect(selectorSingle.text, equals('Hello World'));
    });

    test('handles escaped quotes', () {
      final selector = Selector.parse('text="Hello \\"World\\""');
      expect(selector.text, equals('Hello "World"'));
    });
  });
}
