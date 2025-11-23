# FAP Integration Guide

This guide explains how to add the Flutter Agent Protocol (FAP) to your existing Flutter application.

## 1. Add Dependency

Add `fap_agent` to your `pubspec.yaml` under `dependencies` (or `dev_dependencies` if you prefer).

```yaml
dependencies:
  fap_agent:
    path: ../fap_agent # Or git/pub dependency
```

## 2. Initialize FAP Agent

In your `main.dart`, initialize the `FapAgent` before `runApp`.

```dart
import 'package:fap_agent/fap_agent.dart';

void main() {
  // Initialize FAP
  FapAgent.init(const FapConfig(
    port: 9001, // Default port
    enabled: true, // Defaults to !kReleaseMode
    secretToken: 'your-secret-token', // Optional security
  ));

  runApp(const MyApp());
}
```

## 3. Enable Semantics

FAP relies on Flutter's Semantics tree. Ensure it is enabled in your `build` method or `main`.

```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Force semantics (optional but recommended for reliability)
    SemanticsBinding.instance.ensureSemantics();
    
    return MaterialApp(
      // ...
    );
  }
}
```

## 4. Add Route Observer (Optional)

To enable `getRoute()` functionality, add the FAP navigator observer to your `MaterialApp`.

```dart
return MaterialApp(
  navigatorObservers: [FapAgent.instance.navigatorObserver],
  // ...
);
```

## 5. Add Metadata (Optional)

Use `FapMeta` to tag widgets with custom IDs for easier selection.

```dart
FapMeta(
  metadata: {'test-id': 'login-submit-btn'},
  child: ElevatedButton(
    onPressed: _submit,
    child: const Text('Login'),
  ),
)
```

## 6. Run Your App

Run your app as usual. The FAP Agent will start a WebSocket server on port 9001.

```bash
flutter run -d macos
```

## 7. Connect Client

You can now connect using the FAP Client SDK or the MCP Server.

```typescript
import { FapClient } from 'fap-client';

const client = new FapClient({ secretToken: 'your-secret-token' });
await client.connect();
const tree = await client.listElements();
console.log(tree);
```
