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

1. **Add Dependency**: Add `fap_agent` to your Flutter app.
2. **Initialize**: Call `FapAgent.init()` in `main.dart`.
3. **Run**: Run your Flutter app.
4. **Connect**: Use `fap_mcp` or `fap_client` to start controlling your app!

## Architecture

FAP works by inspecting the Flutter Semantics Tree. This ensures that:
- Interactions are accessible by default.
- Selectors are stable and semantic (e.g., "Save Button" vs "Element #42").
- It works on all Flutter platforms (Mobile, Web, Desktop).
