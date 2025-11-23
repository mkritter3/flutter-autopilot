# FAP Selector Guide

The Flutter Agent Protocol (FAP) uses a flexible selector syntax to identify UI elements. This guide covers all available selector types.

## Basic Selectors

### Key
Target elements by their Flutter `Key`.
```
key="submit_button"
key='user_avatar'
```

### Text / Label / Value / Hint
Target elements by their visible text or semantic properties.
```
text="Save"
label="Enter your name"
value="John Doe"
hint="Email Address"
```

### Type
Target elements by their runtime type.
```
type="ElevatedButton"
type="TextField"
```

## CSS-Style Selectors

You can combine a Type with attributes using square brackets `[]`.

```
Button[text="Save"]
TextField[key="email_input"]
Container[label="Header"]
```

## Combinators

### Descendant (Space)
Find an element that is a descendant of another.
```
// Finds a Text widget anywhere inside a Column
Column Text
```

### Direct Child (>)
Find an element that is a direct child of another.
```
// Finds a Text widget that is a direct child of a SizedBox
SizedBox > Text
```

## Regex Selectors

Use `~/pattern/` syntax to match attributes using Regular Expressions.

```
// Match any text starting with "Item" followed by digits
text=~/^Item \d+$/

// Match a key ending in "_btn"
key=~/.*_btn$/
```

## Metadata Selectors

Target elements with custom metadata attached via `FapMeta`.

```dart
// Flutter Code
FapMeta(
  metadata: {'test-id': 'login-btn'},
  child: ElevatedButton(...),
)
```

```
// Selector
test-id="login-btn"
```

## Role Selectors

Target elements by their semantic role.

```
role="button"
role="textField"
role="slider"
role="switch"
role="image"
role="link"
role="header"
```

## Complex Examples

```
// Find a button with text "Submit" inside a Form
Form Button[text="Submit"]

// Find a specific item in a list by regex
ListView ListTile[text=~/^Order #\d+$/]

// Find a text field by test-id
TextField[test-id="password-input"]
```
