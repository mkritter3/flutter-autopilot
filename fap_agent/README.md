# fap_agent

The core Dart package for the Flutter Agent Protocol (FAP). This package embeds a lightweight WebSocket server into your Flutter application, allowing external agents to inspect the UI tree and perform actions.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  fap_agent:
    git:
      url: https://github.com/mkritter3/flutter-agent-protocol.git
      path: fap_agent
```

For local development, you can use a path dependency instead:

```yaml
dependencies:
  fap_agent:
    path: /path/to/fap_agent
```

## Usage

Initialize the agent in your `main()` function (import `dart:io` if you want to customize the bind address):

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

## Configuration

To listen on all interfaces (emulators/devices), drop the `const` and pass a runtime `InternetAddress`:

```dart
import 'dart:io';

FapAgent.init(FapConfig(
  bindAddress: InternetAddress.anyIPv4,
));
```

`FapConfig` options:
- `port`: The WebSocket port (default 9001).
- `enabled`: Whether the agent is active (default: `!kReleaseMode`).
- `secretToken`: Optional bearer token for authentication.
- `bindAddress`: The interface to bind the WebSocket server to (default `loopback`). Provide an `InternetAddress` or use `FAP_BIND_ADDRESS` (e.g., `FAP_BIND_ADDRESS=0.0.0.0`).
- `maxFrameTimings`: Buffer size for frame timing metrics.
- `maxLogs`: Buffer size for console logs.
- `maxErrors`: Buffer size for error tracking.

See the [Integration Guide](../docs/integration_guide.md) for more details.
