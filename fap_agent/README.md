# Flutter Agent Protocol (FAP) Agent

`fap_agent` is a Dart package that embeds an agent interface into your Flutter application, allowing external AI agents to inspect the UI and perform actions.

## Features

*   **UI Inspection**: Exposes the Flutter Semantics tree as a simplified JSON structure.
*   **Actions**: Supports tapping and entering text on UI elements.
*   **WebSocket Server**: Runs a WebSocket server on the device to communicate with clients.
*   **Zero-Config**: Automatically discovers interactive elements.

## Getting Started

1.  Add `fap_agent` to your `pubspec.yaml` (currently a local dependency).
2.  Initialize the agent in your `main.dart`.

## Usage

```dart
import 'package:fap_agent/fap_agent.dart';
import 'package:flutter/material.dart';

void main() {
  // Initialize FAP Agent
  FapAgent.init();
  
  runApp(const MyApp());
}
```

The agent will start a WebSocket server on port `9001` (default).

## Architecture

The agent uses:
*   `SemanticsBinding` to access the accessibility tree.
*   `shelf` and `shelf_web_socket` for the server.
*   `json_rpc_2` for the protocol.
