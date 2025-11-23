# Contributing to Flutter Agent Protocol (FAP)

We welcome contributions to FAP! This guide will help you get started.

## Project Structure

- **fap_agent**: The Dart package for the Flutter app.
- **fap_client**: The TypeScript client SDK.
- **fap_mcp**: The MCP Server wrapper.
- **docs**: Documentation.

## Development Setup

### Prerequisites
- Flutter SDK
- Node.js & npm

### Running the Example App
1. `cd fap_agent/example`
2. `flutter run -d macos` (or your preferred device)

### Running the MCP Server
1. `cd fap_mcp`
2. `npm install`
3. `npm run build`
4. `npm start`

## Testing

### FAP Agent
Run unit tests:
```bash
cd fap_agent
flutter test
```

### FAP Client / MCP
Run verification scripts (requires running example app):
```bash
cd fap_mcp
npx ts-node test/verify_mcp.ts
```

## Pull Requests
1. Fork the repo.
2. Create a feature branch.
3. Submit a PR with a description of your changes.
4. Ensure all tests pass.
