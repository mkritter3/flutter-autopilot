# Flutter Autopilot Selectors

Complete guide to element selection syntax.

## Basic Selectors

### Key Selector (MOST RELIABLE)
```dart
// In Flutter code:
ElevatedButton(
  key: Key('submit_button'),
  onPressed: () {},
  child: Text('Submit'),
)

// In FAP:
tap('key="submit_button"')
```

Keys are:
- Stable across UI changes
- Unique by design
- Best for test automation
- Set by developers for testability

### Text Selector
```dart
// Matches visible text content
tap('text="Save Changes"')
tap('text="Cancel"')

// Case-sensitive exact match
```

Works with:
- Text widgets
- Button labels
- List items
- Any widget with text content

### Label Selector (Accessibility)
```dart
// In Flutter code:
Semantics(
  label: 'Close dialog',
  child: IconButton(...),
)

// In FAP:
tap('label="Close dialog"')
```

Matches:
- semanticsLabel property
- Semantics widget labels
- Accessibility text

### Type Selector (LEAST RELIABLE)
```dart
// Matches widget type
tap('type="ElevatedButton"')
tap('type="TextField"')
tap('type="Checkbox"')
```

Caution:
- Many widgets of same type
- May match wrong element
- Use only when unique or combined with other selectors

## Selector Priority

When choosing selectors, prefer in this order:

1. **key** - Most reliable, stable, unique
2. **text** - Good for buttons with unique labels
3. **label** - Good for icons/images with a11y labels
4. **type** - Last resort, often ambiguous

## Auto-Normalization

FAP automatically normalizes selectors for better matching:

### Whitespace Normalization
```
// These all match the same element:
label="Project Title"
label="Project Title\nMy Amazing Novel"  // contains newline
label="Project  Title"                    // extra spaces
```

### Partial Matching
```
// Field has label "Project Title\nMy Amazing Novel"
// These partial matches work:
enter_text(selector: 'label="Project Title"', text: '...')
enter_text(selector: 'label="Project"', text: '...')
```

## Special Cases

### Multiple Words
```
tap('text="Save and Continue"')
tap('label="Add new item"')
```

### Special Characters
```
// Quotes and special chars work
tap('text="Don\'t save"')
tap('text="Item #1"')
```

### Empty or Numeric Text
```
tap('text="0"')
tap('text=""')  // empty text
```

## Using list_elements Output

When you call `list_elements`, you get output like:
```json
{
  "id": 42,
  "type": "ElevatedButton",
  "text": "Submit",
  "label": "Submit form",
  "key": "submit_btn",
  "rect": {"left": 100, "top": 200, "width": 120, "height": 48}
}
```

From this, you can use any of:
- `tap('key="submit_btn"')` - Best choice
- `tap('text="Submit"')` - Good
- `tap('label="Submit form"')` - Good
- `tap('type="ElevatedButton"')` - Risky if multiple buttons

## Fallback Strategy

When selectors fail, use coordinates:

```
1. list_elements                    → get rect: {left: 100, top: 200, ...}
2. Calculate center: x = 100 + 60 = 160, y = 200 + 24 = 224
3. On iOS: divide by 3: x = 53, y = 75
4. tap_at(x: 53, y: 75)             → tap by coordinates
```

## Platform-Specific Coordinates

### iOS (iPhone)
```
// list_elements returns DEVICE PIXELS
// tap_at expects LOGICAL POINTS
// iPhone device pixel ratio is typically 3

rect from list_elements: {left: 300, top: 600, width: 180, height: 60}
center in device pixels: x = 300 + 90 = 390, y = 600 + 30 = 630
center in logical points: x = 390/3 = 130, y = 630/3 = 210
tap_at(x: 130, y: 210)
```

### Android/Desktop
```
// Usually 1:1 ratio (but check device)
rect: {left: 100, top: 200, width: 120, height: 48}
center: x = 100 + 60 = 160, y = 200 + 24 = 224
tap_at(x: 160, y: 224)
```

## Category Filtering

Use `get_elements_by_category` for targeted discovery:

```
get_elements_by_category(category: 'button')     → all buttons
get_elements_by_category(category: 'textField')  → all text inputs
get_elements_by_category(category: 'menuItem')   → menu items
get_elements_by_category(category: 'richEditor') → SuperEditor, etc.
```

Available categories:
- `button` - Various button types
- `textField` - TextField, TextFormField
- `menu` - PopupMenu, DropdownMenu
- `menuItem` - Individual menu items
- `drawer` - Drawer widgets
- `dialog` - Dialog, AlertDialog
- `richEditor` - SuperEditor, QuillEditor
- `standard` - Other elements

## Common Patterns

### Login Form
```
enter_text(selector: 'label="Email"', text: 'user@test.com')
enter_text(selector: 'label="Password"', text: 'secret')
tap('text="Sign In"')
```

### List Item Selection
```
tap('text="Item 3"')
// or by key if available
tap('key="list_item_3"')
```

### Icon Buttons (no text)
```
// Icons typically have accessibility labels
tap('label="Menu"')
tap('label="Search"')
tap('label="Close"')
```

### Checkbox/Switch
```
tap('label="Remember me"')
tap('key="dark_mode_switch"')
```

## Debugging Selectors

If a selector doesn't work:

1. Call `list_elements` and examine output
2. Check exact text/label spelling
3. Verify element is in semantics tree
4. Try different selector types
5. Fall back to tap_at with coordinates

### Element Not in Tree?

Some elements don't appear in semantics:
- Custom painters
- Canvas drawings
- Native platform views
- WebViews

For these, use:
1. Visual grounding (screenshot analysis)
2. tap_at with known coordinates
