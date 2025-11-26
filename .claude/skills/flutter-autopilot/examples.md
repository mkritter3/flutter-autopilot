# Flutter Autopilot Examples

Annotated real-world session examples.

## Example 1: Login Flow Test

**Goal:** Test login form with email/password

### Session
```
USER: Test the login screen in my Flutter app

CLAUDE: I'll test the login flow. First, let me discover the UI elements.

[list_elements]
→ Returns UI tree including:
  - TextField with label="Email"
  - TextField with label="Password"
  - ElevatedButton with text="Sign In"

CLAUDE: Found the login form. Let me fill it out.

[tap('label="Email"')]
→ Tapped element

[enter_text(text: 'test@example.com')]
→ Entered text

[tap('label="Password"')]
→ Tapped element

[enter_text(text: 'password123')]
→ Entered text

[tap('text="Sign In"')]
→ Tapped element

[list_elements]
→ UI changed - now shows dashboard screen with "Welcome, Test User"

CLAUDE: Login successful! The app navigated to the dashboard and shows
"Welcome, Test User".
```

### Key Points
- Started with `list_elements` to discover form structure
- Used `label` selectors for text fields
- Used `text` selector for button
- Verified result with another `list_elements`

---

## Example 2: Debugging Missing Button

**Goal:** Find why a button isn't appearing

### Session
```
USER: The "Export" button isn't showing up. Can you help debug?

CLAUDE: Let me inspect the current UI state.

[list_elements]
→ Returns UI tree - no element with text="Export"

CLAUDE: The Export button isn't in the UI tree. Let me check the current route.

[get_route]
→ '/settings'

CLAUDE: We're on the settings screen. Let me check for errors.

[get_errors]
→ No errors captured

CLAUDE: No Flutter errors. Let me scroll to see if it's below the fold.

[scroll(selector: 'type="SingleChildScrollView"', dx: 0, dy: 300)]
→ Scrolled

[list_elements]
→ Now shows ElevatedButton with text="Export Data"

CLAUDE: Found it! The "Export Data" button was below the visible area.
I had to scroll down 300 pixels to reveal it. The button is now
visible and ready to tap.

[tap('text="Export Data"')]
→ Tapped element

[list_elements]
→ Shows dialog with export options
```

### Key Points
- Methodical debugging: check elements, route, errors
- Scrolling revealed hidden element
- Element was "Export Data" not just "Export"

---

## Example 3: Development Cycle with Hot Reload

**Goal:** Change button color and verify

### Session
```
USER: Change the primary button color to green and test it

CLAUDE: I'll set up the development tools first.

[set_project_root('/Users/dev/my_flutter_app')]
→ Project root set

[set_vm_service_uri('http://127.0.0.1:50505/abc123=/')]
→ VM Service URI set

CLAUDE: Now let me read the current button styling.

[read_file('lib/widgets/primary_button.dart')]
→ Returns file content showing:
   color: Colors.blue

CLAUDE: Found the button widget. Changing color to green.

[write_file('lib/widgets/primary_button.dart', <content with Colors.green>)]
→ File written

[hot_reload]
→ Hot reload successful

[list_elements]
→ UI refreshed, button now green (verified visually in app)

CLAUDE: Done! I've changed the button color from blue to green.
The hot reload applied the change instantly while preserving app state.
```

### Key Points
- Set up project root and VM service first
- Read before modify
- Hot reload for instant feedback
- State preserved during reload

---

## Example 4: Menu Interaction

**Goal:** Select an option from a dropdown menu

### Session
```
USER: Select "Dark Mode" from the theme dropdown

CLAUDE: Let me find the dropdown menu.

[discover_menu_triggers]
→ Returns:
  - type: "dropdown", label: "Theme", bounds: {...}

CLAUDE: Found the theme dropdown. Opening it.

[tap('label="Theme"')]
→ Tapped element

[wait_for_overlay]
→ Overlay appeared

[get_overlay_state]
→ Returns:
  - hasOverlay: true
  - content: [
      {label: "Light Mode", ...},
      {label: "Dark Mode", ...},
      {label: "System", ...}
    ]

CLAUDE: Menu is open with three options. Selecting Dark Mode.

[tap('text="Dark Mode"')]
→ Tapped element

[list_elements]
→ Dropdown now shows "Dark Mode" selected, app theme changed

CLAUDE: Selected Dark Mode. The app theme has switched to dark mode.
```

### Key Points
- Used `discover_menu_triggers` for menu discovery
- `wait_for_overlay` ensures menu animation complete
- `get_overlay_state` reveals menu items
- Menu closed automatically after selection

---

## Example 5: Rich Text Editor (SuperEditor)

**Goal:** Enter formatted text in a document editor

### Session
```
USER: Add a title to the document in the rich text editor

CLAUDE: Let me find the rich text editor.

[discover_rich_text_editors]
→ Returns:
  - id: 1, editorType: "SuperEditor", hasDocument: true

CLAUDE: Found a SuperEditor. I need to focus it first, then use
rich text entry.

[list_elements]
→ Shows SuperEditor bounds: {left: 0, top: 100, width: 400, height: 600}

[tap_at(x: 200, y: 150)]  // Tap center-top of editor
→ Tapped at coordinates

[enter_rich_text(text: 'My Document Title')]
→ Text entered via IME delta simulation

[list_elements]
→ Editor now contains "My Document Title"

CLAUDE: Added the title "My Document Title" to the document.
```

### Key Points
- `discover_rich_text_editors` identifies SuperEditor
- Must focus editor before typing
- Use `enter_rich_text` NOT `enter_text` for rich editors
- IME delta simulation works with SuperEditor

---

## Example 6: Form Validation Testing

**Goal:** Verify form shows validation errors

### Session
```
USER: Test that the form shows errors for invalid input

CLAUDE: Let me find the form and test validation.

[list_elements]
→ Shows form with:
  - TextField label="Email"
  - TextField label="Phone"
  - ElevatedButton text="Submit"

CLAUDE: I'll submit the empty form first to trigger validation.

[tap('text="Submit"')]
→ Tapped element

[list_elements]
→ Now shows:
  - TextField label="Email" with error text "Email is required"
  - TextField label="Phone" with error text "Phone is required"

CLAUDE: Validation working - shows required field errors. Now let me
test with invalid email format.

[tap('label="Email"')]
[enter_text(text: 'notanemail')]
[tap('text="Submit"')]
[list_elements]
→ Shows error: "Invalid email format"

CLAUDE: Form validation is working correctly:
1. Shows "required" errors for empty fields
2. Shows format validation for invalid email
```

### Key Points
- Submit empty form to test required validation
- Submit invalid data to test format validation
- `list_elements` reveals error messages

---

## Example 7: iOS Coordinate Handling

**Goal:** Tap a canvas element using coordinates on iOS

### Session
```
USER: Tap the center of the canvas to place a marker

CLAUDE: Canvas elements aren't in the semantics tree. I'll use
coordinates. Since this is iOS, I need to account for the pixel ratio.

[list_elements]
→ Shows canvas container:
  - bounds: {left: 0, top: 150, width: 1170, height: 1800}
  (These are device pixels on iOS)

CLAUDE: Calculating logical coordinates for iOS:
- Center in device pixels: x=585, y=1050
- Divide by 3 for logical points: x=195, y=350

[tap_at(x: 195, y: 350)]
→ Tapped at coordinates

CLAUDE: Tapped the center of the canvas. The marker should now appear
at that location.
```

### Key Points
- Canvas/CustomPaint not in semantics tree
- iOS coordinates from list_elements are device pixels
- Divide by 3 (device pixel ratio) for tap_at
- tap_at expects logical points

---

## Common Patterns Summary

| Task | Pattern |
|------|---------|
| Discover UI | `list_elements` first, always |
| Fill form | `tap` field → `enter_text` → repeat |
| Submit form | `tap` button → `list_elements` verify |
| Open menu | `tap` trigger → `wait_for_overlay` → `get_overlay_state` |
| Select menu item | `tap` item in overlay |
| Rich text | Focus → `enter_rich_text` |
| Scroll to find | `scroll` → `list_elements` → repeat |
| Debug issues | `get_errors` → `get_logs` → `get_route` |
| Edit code | `read_file` → modify → `write_file` → `hot_reload` |
| iOS tap_at | Get coords → divide by 3 → tap |
