# Flutter Agent Protocol (FAP)

FAP is a protocol and set of tools that enables AI agents to interact with Flutter applications reliably and semantically.

## Components

- **[fap_agent](fap_agent/)**: The Dart package that runs inside your Flutter app. It exposes the WebSocket server and handles UI introspection and interaction.
- **[fap_client](fap_client/)**: A Node.js/TypeScript client SDK for connecting to the FAP Agent.
- **[fap_mcp](fap_mcp/)**: An MCP (Model Context Protocol) Server wrapper. See [fap_mcp/README.md](fap_mcp/README.md) for installation instructions.

## Documentation

- **[Integration Guide](docs/integration_guide.md)**: How to add FAP to your app.
- **[Selector Guide](docs/selector_guide.md)**: How to select UI elements using the FAP selector syntax.

## Quick Start

### 1. Setup the MCP Server

```bash
git clone https://github.com/mkritter3/flutter-autopilot.git
cd flutter-autopilot
./setup.sh
```

The setup script will:
- Build `fap_client` and `fap_mcp`
- Optionally configure Claude Code MCP server

### 2. Add FAP to Your Flutter App

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  fap_agent:
    git:
      url: https://github.com/mkritter3/flutter-autopilot.git
      path: fap_agent
```

Initialize in your `main.dart`:

```dart
import 'package:fap_agent/fap_agent.dart';

void main() {
  FapAgent.init(const FapConfig(port: 9001, enabled: true));
  runApp(const MyApp());
}
```

### 3. Connect

1. Run your Flutter app
2. In Claude Code, run `/fap-setup` to verify the connection
3. Start automating!

## Architecture

FAP works by inspecting the Flutter Semantics Tree. This ensures that:
- Interactions are accessible by default.
- Selectors are stable and semantic (e.g., "Save Button" vs "Element #42").
- It works on all Flutter platforms (Mobile, Web, Desktop).
