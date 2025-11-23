# fap_agent

The core Dart package for the Flutter Agent Protocol (FAP). This package embeds a lightweight WebSocket server into your Flutter application, allowing external agents to inspect the UI tree and perform actions.

## Installation

Add to `pubspec.yaml`:

```yaml
dependencies:
  fap_agent:
    path: /path/to/fap_agent
```

## Usage

Initialize the agent in your `main()` function:

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

`FapConfig` options:
- `port`: The WebSocket port (default 9001).
- `enabled`: Whether the agent is active (default: `!kReleaseMode`).
- `secretToken`: Optional bearer token for authentication.
- `maxFrameTimings`: Buffer size for frame timing metrics.
- `maxLogs`: Buffer size for console logs.
- `maxErrors`: Buffer size for error tracking.

See the [Integration Guide](../docs/integration_guide.md) for more details.
