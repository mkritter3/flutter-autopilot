---
name: fap-setup
description: Initialize Flutter Autopilot connection and configure project settings for UI automation
---

Help the user set up Flutter Autopilot (FAP) for their Flutter project. Guide them through connection verification, project configuration, and hot reload setup.

## Steps

### 1. Verify FAP Agent Connection

Test the connection by calling `list_elements`.

**If it succeeds:** FAP Agent is connected and ready.

**If it fails:** Guide the user to:
- Ensure their Flutter app is running with FAP Agent initialized:
  ```dart
  import 'package:fap_agent/fap_agent.dart';

  void main() {
    FapAgent.init(const FapConfig(
      port: 9001,
      enabled: true,
    ));
    runApp(const MyApp());
  }
  ```
- Check the MCP server is configured in Claude Code settings
- For Android emulator: run `adb reverse tcp:9001 tcp:9001`

### 2. Configure Project Root (for code tools)

Ask the user for their Flutter project path (where `pubspec.yaml` is located).

Call:
```
set_project_root(path='/path/to/flutter/project')
```

This enables:
- `read_file` / `write_file` - Code modification
- `search_code` / `list_files` - Code exploration
- `analyze_code` / `apply_fixes` / `format_code` - Code quality
- `run_tests` - Test execution

### 3. Configure VM Service (for hot reload)

Guide the user to find the VM Service URI from `flutter run` output:

1. Look for output like: `The Dart VM service is listening on http://127.0.0.1:XXXXX/XXXXX=/`
2. Or find it in: `Flutter DevTools at http://127.0.0.1:XXXXX?uri=http%3A%2F%2F127.0.0.1%3AYYYYY%2FZZZZZ%3D%2F`

The URI format is: `http://127.0.0.1:XXXXX/XXXXX=/`

Call:
```
set_vm_service_uri(uri='http://127.0.0.1:XXXXX/XXXXX=/')
```

This enables:
- `hot_reload` - Apply code changes (preserves state)
- `hot_restart` - Full restart (resets state)
- `get_vm_info` - VM information

### 4. Verify Setup

After configuration, verify all components:

1. Call `list_elements` - Confirm UI tree access
2. If project root set: verify with `list_files('lib')`
3. If VM service set: verify with `get_vm_info`

### 5. Report Status

Provide configuration status summary:

```
Flutter Autopilot Setup Complete
================================
FAP Agent:    ✓ Connected (port 9001)
Project Root: ✓ /path/to/project
VM Service:   ✓ http://127.0.0.1:XXXXX/XXXXX=/

Ready for:
- UI Interaction (tap, scroll, enter_text, etc.)
- Code Editing (read_file, write_file)
- Hot Reload (hot_reload, hot_restart)
- Testing (run_tests, analyze_code)
- Debugging (get_errors, get_logs)
```

Or if partially configured:

```
Flutter Autopilot Setup
=======================
FAP Agent:    ✓ Connected
Project Root: ✗ Not set (code tools disabled)
VM Service:   ✗ Not set (hot reload disabled)

Ready for:
- UI Interaction only

To enable more features, provide:
- Project root path for code editing
- VM Service URI for hot reload
```

## Notes

- FAP Agent connection is required - without it, no tools work
- Project root is optional but enables the development workflow
- VM Service is optional but enables rapid iteration with hot reload
- All three together enable the full edit-reload-test cycle
