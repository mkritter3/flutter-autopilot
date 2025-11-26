---
name: flutter-autopilot
description: Control and test Flutter apps via semantics tree. Use when interacting with Flutter UI, automating forms, testing navigation, debugging UI state, or developing with hot reload. Always call list_elements first to discover available selectors.
---

# Flutter Autopilot

Flutter Autopilot (FAP) enables autonomous control of Flutter applications through the semantics tree. It provides 40+ tools for UI interaction, debugging, and development workflows.

## When to Use This Skill

Activate when you see patterns like:
- "test the Flutter app" / "automate this flow"
- "tap/click the button" / "fill the form"
- "what's on screen" / "check UI state"
- "hot reload" / "edit code and test"
- "debug this UI" / "why isn't this working"

## The Golden Rule

**ALWAYS call `list_elements` FIRST** before any interaction to discover:
- Available selectors (key, text, label, type)
- Element coordinates (for tap_at fallback)
- Current UI state for verification

## Critical Gotchas

| Gotcha | Problem | Solution |
|--------|---------|----------|
| iOS Coordinates | list_elements returns device pixels | Divide by 3 for tap_at on iOS |
| Selector Priority | type selectors match many elements | Prefer: key > text > label > type |
| Native Views | Plaid, WebViews outside Flutter | Cannot interact - inform user |
| Text Fields | Field may not have focus | Use tap_first=true parameter |
| Scroll Direction | Confusing +/- values | Positive dy = DOWN |
| Hot Reload | Fails for some changes | Use hot_restart for main/enums |
| Rich Text Editors | SuperEditor not standard TextField | Use enter_rich_text, not enter_text |

## Core Workflows

### Basic Interaction
```
1. list_elements           → discover UI state and selectors
2. tap('text="Save"')      → interact with element
3. list_elements           → verify result
```

### Form Filling
```
1. list_elements                          → find form fields
2. tap('label="Email"') + enter_text()    → fill each field
3. tap('text="Submit"')                   → submit form
4. list_elements                          → verify success state
```

### Development Loop
```
1. set_project_root('/path/to/project')   → enable file tools
2. set_vm_service_uri('http://...')       → enable hot reload
3. read_file / write_file                 → modify code
4. hot_reload                             → apply changes
5. list_elements                          → verify UI update
```

### Debugging
```
1. list_elements    → see current UI state
2. get_errors       → check for Flutter errors
3. get_logs         → check console output
4. get_route        → verify navigation
```

### Rich Text Editing (SuperEditor, etc.)
```
1. list_elements                    → find the editor
2. tap on the editor area           → focus it
3. enter_rich_text('My text')       → use rich text input
```

### Menu/Overlay Interaction
```
1. discover_menu_triggers           → find dropdown/popup triggers
2. tap on trigger                   → open menu
3. wait_for_overlay                 → wait for menu animation
4. get_overlay_state                → get menu items
5. tap on menu item                 → select option
```

## Error Recovery Quick Reference

| Error | Try This |
|-------|----------|
| "element not found" | list_elements to find correct selector |
| Tap doesn't work | tap_at with coordinates (÷3 on iOS) |
| Text input fails | tap_first=true or tap field first |
| Hot reload fails | Use hot_restart for main/enum changes |
| Menu not opening | wait_for_overlay after tap |
| Rich text fails | Use enter_rich_text, not enter_text |

## Tool Categories

### UI Inspection
- `list_elements` - Get full UI tree (ALWAYS START HERE)
- `get_elements_by_category` - Filter by type (button, textField, etc.)
- `get_placeholders` - Find stub/unimplemented UI
- `get_route` - Current navigation route

### Basic Interaction
- `tap` - Tap by selector
- `tap_at` - Tap by coordinates (remember iOS ÷3)
- `enter_text` - Type into text fields
- `set_text` - Replace text field content
- `scroll` - Scroll containers

### Advanced Gestures
- `long_press` - Long press for context menus
- `double_tap` - Double tap for zoom/select
- `drag` - Drag elements or by offset

### Rich Text
- `discover_rich_text_editors` - Find SuperEditor, QuillEditor, etc.
- `enter_rich_text` - IME-based text input for rich editors

### Menus & Overlays
- `discover_menu_triggers` - Find dropdown/popup buttons
- `get_overlay_state` - Check open menus/dialogs
- `wait_for_overlay` - Wait for menu to open
- `open_drawer` / `close_drawer` - Drawer control

### Debugging
- `get_errors` - Flutter errors and exceptions
- `get_logs` - Console output
- `get_performance_metrics` - Frame timing

### Development Tools
- `set_project_root` - Enable file operations
- `set_vm_service_uri` - Enable hot reload
- `hot_reload` - Apply code changes (preserves state)
- `hot_restart` - Full restart (loses state)
- `read_file` / `write_file` - Code modification
- `analyze_code` - Run dart analyze
- `run_tests` - Run flutter tests

### Recording
- `start_recording` - Record interactions
- `stop_recording` - Get recorded script

## Reference Files

For detailed information, see:
- `references/workflows.md` - Multi-step workflow recipes
- `references/selectors.md` - Full selector syntax guide
- `references/troubleshooting.md` - Error recovery patterns
- `examples.md` - Annotated real session examples

## Setup

Run `/fap-setup` to configure:
1. FAP Agent connection (running Flutter app)
2. Project root (for file tools)
3. VM Service URI (for hot reload)
