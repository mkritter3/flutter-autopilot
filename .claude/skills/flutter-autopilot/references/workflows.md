# Flutter Autopilot Workflows

Detailed recipes for common automation tasks.

## Navigation Testing

### Verify Route Changes
```
1. get_route                        → note current route (e.g., '/home')
2. tap('text="Settings"')           → tap navigation element
3. get_route                        → verify new route (e.g., '/settings')
```

### Test Back Navigation
```
1. Navigate to deep screen
2. get_route                        → confirm deep route
3. tap('type="BackButton"')         → or use system back
4. get_route                        → verify previous route
```

### Drawer Navigation
```
1. discover_menu_triggers           → find drawer trigger (hamburger icon)
2. open_drawer                      → open programmatically (or tap trigger)
3. get_drawer_state                 → verify drawer is open
4. list_elements                    → find drawer items
5. tap('text="Profile"')            → select drawer item
6. get_drawer_state                 → verify drawer closed
7. get_route                        → verify navigation occurred
```

### Tab Navigation
```
1. list_elements                    → find tab bar
2. tap('text="Tab 2"')              → tap inactive tab
3. list_elements                    → verify tab content changed
```

## Form Testing

### Login Form
```
1. list_elements                    → discover form fields
2. tap('label="Email"')             → focus email field
3. enter_text(text: 'user@test.com')
4. tap('label="Password"')          → focus password field
5. enter_text(text: 'password123')
6. tap('text="Login"')              → submit
7. list_elements                    → verify success (new screen or message)
```

### Form with Validation
```
1. list_elements                    → find form
2. tap('text="Submit"')             → submit empty form
3. list_elements                    → check for validation errors
4. Fill fields with valid data
5. tap('text="Submit"')             → resubmit
6. list_elements                    → verify success
```

### Clearing and Replacing Text
```
1. list_elements                    → find field with existing text
2. set_text(selector: 'label="Name"', text: 'New Name')  → replaces all text
3. list_elements                    → verify text changed
```

### Text Selection
```
1. tap('label="Description"')       → focus field
2. set_selection(selector: 'label="Description"', base: 0, extent: 5)  → select first 5 chars
```

## Menu Interaction

### Dropdown Menu
```
1. discover_menu_triggers           → find dropdown buttons
2. tap on dropdown trigger
3. wait_for_overlay                 → wait for menu animation
4. get_overlay_state                → see menu items
5. tap('text="Option B"')           → select item
6. list_elements                    → verify selection
```

### Popup Menu (3-dot menu)
```
1. list_elements                    → find PopupMenuButton
2. tap('type="PopupMenuButton"')    → open menu
3. wait_for_overlay
4. get_overlay_state                → get menu items
5. tap on desired item
```

### Context Menu (Long Press)
```
1. long_press('text="Item to edit"')  → trigger context menu
2. wait_for_overlay
3. get_overlay_state                → get menu options
4. tap('text="Delete"')             → select option
```

## Rich Text Editing (SuperEditor, QuillEditor)

### Basic Rich Text Entry
```
1. discover_rich_text_editors       → find rich text widgets
2. list_elements                    → get editor bounds
3. tap on editor area               → focus it (use tap_at if needed)
4. enter_rich_text(text: 'Hello World')  → type text
5. list_elements                    → verify text appeared
```

### Multiple Paragraphs
```
1. Focus editor
2. enter_rich_text(text: 'First paragraph')
3. enter_rich_text(text: '\n\nSecond paragraph')  → double newline for new paragraph
```

### Why enter_rich_text vs enter_text?
- `enter_text` uses standard Flutter text input
- `enter_rich_text` uses IME delta simulation
- SuperEditor and similar rich text widgets require IME deltas
- Always use `enter_rich_text` for rich text editors

## Edit-Reload-Test Loop

### Quick Iteration Cycle
```
1. set_project_root('/path/to/flutter/project')
2. set_vm_service_uri('http://127.0.0.1:XXXXX/XXXXX=/')

--- Iteration Loop ---
3. read_file('lib/screens/home.dart')      → examine code
4. write_file('lib/screens/home.dart', modifiedContent)
5. hot_reload                              → apply changes
6. list_elements                           → verify UI update
7. Repeat steps 3-6 as needed
```

### When Hot Reload Fails
```
Hot reload failed? Try:
1. hot_restart                     → full restart (loses state)
2. If still fails, check analyze_code for syntax errors
```

### Changes Requiring Hot Restart
- Changes to `main()`
- Enum modifications
- Global variable initializers
- Some static field changes

## Recording and Playback

### Create Test Script
```
1. start_recording                  → begin capturing
2. Perform manual interactions:
   - tap, scroll, enter_text, etc.
3. stop_recording                   → get script
4. Save script for later replay
```

## Debugging Workflows

### UI Not Responding
```
1. list_elements                    → check if element exists
2. Verify selector is correct
3. Check if element is enabled
4. Try tap_at with coordinates
5. get_errors                       → check for Flutter errors
```

### Unexpected UI State
```
1. list_elements                    → full UI tree
2. get_route                        → verify current screen
3. get_logs                         → check for clues
4. get_errors                       → check for exceptions
```

### Performance Issues
```
1. get_performance_metrics          → frame timing data
2. Look for frames > 16ms (jank)
3. Check build vs raster times
```

### Finding Incomplete Features
```
1. get_placeholders                 → find stub/WIP elements
2. Review disabled buttons, TODO text patterns
3. Create TODO list for implementation
```

## Scrolling Patterns

### Scroll to Find Element
```
1. list_elements                    → element not visible
2. scroll(selector: 'type="ListView"', dx: 0, dy: 300)  → scroll down
3. list_elements                    → check if element appeared
4. Repeat until found
```

### Scroll Direction Reference
- `dy: 300` = scroll DOWN (content moves up)
- `dy: -300` = scroll UP (content moves down)
- `dx: 300` = scroll RIGHT
- `dx: -300` = scroll LEFT

### Pull to Refresh
```
1. drag(selector: 'type="ListView"', dx: 0, dy: 200)  → pull down
2. wait briefly
3. list_elements                    → verify refreshed content
```

## Testing Workflows

### Run All Tests
```
1. set_project_root('/path/to/project')
2. run_tests                        → run all tests
3. Review results
```

### Run Specific Test File
```
run_tests(path: 'test/widget_test.dart')
```

### Test with Verbose Output
```
run_tests(path: 'test/unit/', reporter: 'expanded')
```

## Code Quality

### Pre-Commit Checks
```
1. set_project_root('/path/to/project')
2. analyze_code                     → find issues
3. Fix any errors/warnings
4. format_code                      → apply dart format
5. run_tests                        → verify tests pass
```

### Auto-Fix Issues
```
1. apply_fixes(dryRun: true)        → preview fixes
2. apply_fixes(dryRun: false)       → apply fixes
3. analyze_code                     → verify fixes worked
```
