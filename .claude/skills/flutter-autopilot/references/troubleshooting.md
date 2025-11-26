# Flutter Autopilot Troubleshooting

Solutions for common issues and error recovery patterns.

## Connection Issues

### "Cannot connect to FAP Agent"

**Symptoms:**
- All tools fail with connection errors
- "WebSocket connection failed"

**Solutions:**
1. Verify Flutter app is running with FAP Agent initialized
2. Check the agent is listening on expected port (default: 9001)
3. Verify MCP server config points to correct host/port
4. For Android emulator: ensure adb reverse is set up
5. For iOS simulator: use localhost (127.0.0.1)

```dart
// Verify FAP Agent is initialized in your Flutter app:
void main() {
  FapAgent.init(const FapConfig(
    port: 9001,
    enabled: true,
  ));
  runApp(const MyApp());
}
```

### "Connection timeout"

**Solutions:**
1. App might be slow to start - wait and retry
2. Check if app is responding (not frozen)
3. Increase timeout: `FAP_AGENT_TIMEOUT_MS=30000`

## Element Not Found

### "element not found" with Correct Selector

**Diagnosis:**
```
1. list_elements            → check actual selectors available
2. Compare your selector with list output
```

**Common Causes:**
- Typo in selector
- Element not visible (need to scroll)
- Element on different screen
- Element hidden by overlay/dialog
- Element not in semantics tree

**Solutions:**

**Typo:**
```
// Your attempt:
tap('text="Sumbit"')  // typo: "Sumbit"

// Correct:
tap('text="Submit"')
```

**Element needs scroll:**
```
1. scroll(selector: 'type="ListView"', dx: 0, dy: 300)
2. list_elements            → check if element visible now
3. Repeat scrolling until found
```

**Element on different screen:**
```
1. get_route                → verify current screen
2. Navigate to correct screen
3. list_elements            → find element
```

**Element hidden by overlay:**
```
1. get_overlay_state        → check for open dialogs/menus
2. Dismiss overlay (tap outside, press back)
3. list_elements            → element should be visible
```

### Element Not in Semantics Tree

Some Flutter widgets don't create semantics nodes:
- Custom painters
- Canvas/CustomPaint widgets
- Native platform views (WebViews, Plaid SDK)

**Solutions:**
1. Use `tap_at` with coordinates
2. For canvas elements, find surrounding elements for reference
3. For native views: **FAP cannot interact** - inform user

```
// Fallback to coordinates:
1. list_elements            → find nearby element with known position
2. Calculate target coordinates relative to known element
3. tap_at(x: calculated_x, y: calculated_y)
```

## Tap Issues

### Tap Executes But Nothing Happens

**Diagnosis:**
- Element found and tapped
- But UI doesn't respond

**Possible Causes:**
1. Element is disabled
2. Tap hit wrong element
3. Element has no onTap handler
4. Element blocked by invisible overlay

**Solutions:**

**Check if disabled:**
```
1. list_elements            → check isEnabled flag
2. If disabled, cannot tap - inform user
```

**Try coordinates:**
```
1. list_elements            → get rect
2. Calculate center
3. iOS: divide by 3
4. tap_at(x, y)
```

**Check for overlays:**
```
1. get_overlay_state        → look for invisible overlays
2. Dismiss any overlays
```

### iOS Coordinate Scaling

**Symptom:** tap_at hits wrong location on iOS

**Cause:** iOS device pixel ratio is 3x

**Solution:**
```
// list_elements returns device pixels
rect: {left: 300, top: 600, width: 180, height: 60}

// Calculate center in device pixels
center_x = 300 + 90 = 390
center_y = 600 + 30 = 630

// Convert to logical points (divide by 3)
tap_at(x: 130, y: 210)
```

## Text Input Issues

### enter_text Does Nothing

**Diagnosis:**
- Command succeeds but text doesn't appear

**Solutions:**

**Field not focused:**
```
// Option 1: Use tap_first
enter_text(selector: 'label="Name"', text: 'John', tap_first: true)

// Option 2: Tap first manually
tap('label="Name"')
enter_text(text: 'John')  // no selector, uses focused field
```

**Rich text editor:**
```
// SuperEditor, QuillEditor need special handling
discover_rich_text_editors        → verify it's a rich editor
tap on editor                     → focus it
enter_rich_text(text: 'Content')  → use rich text entry
```

### Text Appends Instead of Replaces

**Use set_text for replacement:**
```
set_text(selector: 'label="Name"', text: 'New Name')
```

### Special Characters Not Working

**For newlines in rich text:**
```
enter_rich_text(text: 'Line 1\n\nLine 2')  // double newline for paragraph
```

## Hot Reload Issues

### "VM Service URI not set"

**Solution:**
```
1. Run: flutter run
2. Find URI in output: "Flutter DevTools at http://127.0.0.1:XXXXX?uri=..."
3. Extract VM Service URI: http://127.0.0.1:XXXXX/XXXXX=/
4. Call: set_vm_service_uri('http://127.0.0.1:XXXXX/XXXXX=/')
```

### Hot Reload Fails

**Common causes:**
- Syntax errors in code
- Changes to main()
- Enum changes
- Global initializer changes

**Solutions:**
```
// Check for syntax errors
analyze_code                → look for compilation errors

// If code is valid but hot reload fails
hot_restart                 → full restart (loses state)
```

### Changes Not Appearing After Reload

**Possible causes:**
- Widget state not rebuilding
- Cached data not cleared
- Change requires restart

**Solutions:**
```
// Force full restart
hot_restart

// Or manually trigger rebuild in code
// (add call to setState or notifyListeners)
```

## Menu/Overlay Issues

### Menu Doesn't Open

**Diagnosis:**
```
1. tap on menu trigger
2. wait_for_overlay(timeoutMs: 5000)
3. get_overlay_state
```

**Solutions:**
- Ensure correct trigger tapped
- Wait longer for animation
- Check if menu is disabled

### Can't Find Menu Items

**After opening menu:**
```
1. wait_for_overlay              → wait for animation
2. get_overlay_state             → get menu items
3. tap('text="Menu Item"')       → tap item
```

**Menu items not in overlay state?**
- Some menus use custom implementations
- Try list_elements instead
- Use tap_at with visual reference

### Drawer Won't Open

**Solutions:**
```
// Method 1: Programmatic
open_drawer

// Method 2: Find and tap trigger
discover_menu_triggers           → find drawer trigger
tap on trigger
get_drawer_state                 → verify opened
```

## Performance Issues

### Tools Running Slowly

**Possible causes:**
- App under heavy load
- Large widget tree
- Network latency

**Solutions:**
- Reduce widget tree size in test scenarios
- Wait between rapid operations
- Check get_performance_metrics for app-side issues

### list_elements Returns Huge Output

**Solutions:**
- Use get_elements_by_category for targeted queries
- Look for specific elements rather than parsing entire tree

## Platform-Specific Issues

### Android Emulator Connection

**Setup:**
```bash
adb reverse tcp:9001 tcp:9001
```

FAP MCP tries this automatically, but may fail if:
- adb not in PATH
- Multiple devices connected
- Emulator not running

### iOS Simulator

- Uses localhost automatically
- No special setup needed
- Remember to divide coordinates by 3 for tap_at

### Desktop (macOS/Windows/Linux)

- Localhost connection
- Coordinates usually 1:1 (no scaling)
- Check window focus issues

## Debugging Checklist

When things don't work:

1. **Verify connection:** Does list_elements return data?
2. **Check element exists:** Is it in list_elements output?
3. **Verify selector:** Does selector exactly match?
4. **Check enabled state:** Is element interactive?
5. **Check visibility:** Is it scrolled out of view?
6. **Check overlays:** Is something blocking it?
7. **Try coordinates:** Does tap_at work?
8. **Check errors:** What does get_errors show?
9. **Check logs:** What does get_logs show?

## Getting Help

If issues persist:
1. Capture `list_elements` output
2. Capture `get_errors` output
3. Note exact tool calls and responses
4. Check FAP Agent console output in Flutter app
