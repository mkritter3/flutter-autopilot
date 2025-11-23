# FAP – Flutter Agent Protocol: Architecture Plan

## A. System Overview & Goals

**What is FAP?**
FAP (Flutter Agent Protocol) is a testing and automation system designed specifically for Flutter applications. It provides a semantic, Playwright-style interface for interacting with Flutter apps, bypassing the limitations of Flutter's canvas-based rendering which hides the UI structure from traditional DOM-based tools.

**Problems it Solves:**
- **Inaccessibility:** Standard web automation tools (Selenium, Playwright) cannot "see" inside the Flutter canvas.
- **AI Agent Integration:** AI agents need a way to discover UI elements, perform actions, and read state programmatically to navigate apps.
- **Cross-Platform Testing:** Provides a unified API for testing Flutter apps across Web, Android, iOS, and Desktop.

**Supported Platforms:**
- Flutter Web
- Flutter Android
- Flutter iOS
- Flutter Desktop (macOS/Windows/Linux)

---

## B. High-Level Architecture

The system consists of three main layers:

1.  **In-App Flutter Agent (Server):**
    - A Dart package (`fap_agent`) embedded in the Flutter app.
    - Runs a WebSocket server (or connects to a relay).
    - Hooks into Flutter's `SemanticsBinding`, `WidgetInspector`, and `GestureBinding`.
    - Exposes the UI tree and accepts commands.

2.  **Transport Layer:**
    - JSON-RPC 2.0 over WebSockets.
    - Handles command messages (Request/Response) and event streams (Logs, Errors).

3.  **Client SDK (Node.js/TypeScript):**
    - A library (`fap-client`) that connects to the Dart agent.
    - Provides a high-level, fluent API (e.g., `await fap.tap('Button[text="Save"]')`).
    - Used by test runners, CI pipelines, and AI agents.

**Auxiliary Components:**
- **Selector Engine:** Parses string selectors into widget matchers.
- **CI Test Runner:** A CLI tool to launch tests and manage the agent lifecycle.

---

## C. Detailed Component Breakdown

### 1. In-App Flutter Agent (`fap_agent`)
*   **Purpose:** The "brain" inside the app that executes commands and reads state.
*   **Public API:** `FapAgent.init(config)`, `FapAgent.attach()`.
*   **Internal Architecture:**
    *   `AgentServer`: Manages WebSocket connections.
    *   `CommandHandler`: Routes RPC methods to specific handlers.
    *   `TreeIndexer`: Traverses the widget/semantics tree to build a queryable index.
    *   `ActionExecutor`: Injects pointer events (taps, drags) into `GestureBinding`.
*   **Dependencies:** `flutter`, `web_socket_channel`, `json_rpc_2`.
*   **Failure Modes:** WebSocket disconnects, app crash during tree traversal, invalid selectors.
*   **Test Strategy:** Unit tests for logic, integration tests within a sample app.

### 2. Selector Engine
*   **Purpose:** Resolves string selectors to specific UI elements.
*   **Public API:** `Selector.parse(String)`, `Selector.match(Element)`.
*   **Internal Architecture:**
    *   `Tokenizer`: Splits selector strings into tokens.
    *   `Parser`: Builds an AST from tokens.
    *   `Matcher`: Evaluates AST against a `FapElement`.
*   **Dependencies:** None (pure Dart).
*   **Failure Modes:** Syntax errors in selectors, ambiguous matches.
*   **Test Strategy:** Extensive unit tests with various selector patterns.

### 3. Node.js Client SDK (`fap-client`)
*   **Purpose:** The external interface for controlling the app.
*   **Public API:** `connect()`, `tap()`, `enterText()`, `waitFor()`, `captureScreenshot()`.
*   **Internal Architecture:**
    *   `ClientSession`: Manages the WebSocket connection and RPC correlation.
    *   `ElementHandle`: Represents a remote UI element.
    *   `Locator`: Builds selectors.
*   **Dependencies:** `ws` (WebSocket), `events`.
*   **Failure Modes:** Connection timeout, protocol mismatch.
*   **Test Strategy:** E2E tests against a running Flutter app.

---

## D. Dart Package Structure (`fap_agent`)

```
lib/
├── fap_agent.dart           # Main entry point (init, config)
├── src/
│   ├── server/
│   │   ├── ws_server.dart   # WebSocket server implementation
│   │   └── rpc_handler.dart # JSON-RPC method routing
│   ├── core/
│   │   ├── selector_parser.dart # Selector parsing logic
│   │   ├── semantics_index.dart # Tree traversal and indexing
│   │   └── actions.dart     # Gesture injection (tap, scroll)
│   ├── utils/
│   │   ├── errors.dart      # Error capturing and formatting
│   │   ├── perf.dart        # Frame timing and metrics
│   │   ├── screenshot.dart  # Screenshot capture logic
│   │   └── logging.dart     # Log interception
```

---

## E. Node.js Client SDK Structure (`fap-client`)

```
client/
├── index.ts                 # Main export
├── session.ts               # WebSocket connection & RPC client
├── selector.ts              # Selector helpers (if needed client-side)
├── actions.ts               # High-level action methods
├── wait.ts                  # Polling and waiting logic
├── errors.ts                # Error types
└── screenshot.ts            # Screenshot handling
```

---

## F. Protocol Specification (JSON-RPC)

**Request Format:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tap",
  "params": { "selector": "role=button & text='Save'" }
}
```

**Response Format:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": { "status": "success" }
}
```

**Error Format:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": { "code": -32000, "message": "Element not found" }
}
```

**Core RPC Methods:**
*   `getTree()`: Returns a snapshot of the current UI tree.
*   `tap(selector)`: Taps an element.
*   `enterText(selector, text)`: Enters text into a field.
*   `scroll(selector, dx, dy)`: Scrolls a container.
*   `waitFor(selector, timeout)`: Waits for an element to appear.
*   `captureScreenshot()`: Returns base64 image data.

**Event Streams:**
*   `log`: Console logs from the app.
*   `flutterError`: Flutter framework errors.

---

## G. Selector Language Spec

The selector language allows precise targeting of widgets.

*   **Attributes:**
    *   `type=Text` (Widget class name)
    *   `key=submitBtn` (Key string)
    *   `role=button` (Semantics role)
    *   `text="Submit"` (Text content)
    *   `label="Submit Form"` (Semantics label)

*   **CSS-Style Syntax:**
    *   `Button[text="Save"]` -> `type=Button & text="Save"`
    *   `#myKey` -> `key=myKey`

*   **Logical Operators:**
    *   `&` (AND): `role=button & text="Save"`
    *   `|` (OR): `text="Save" | text="Submit"`

*   **Custom Metadata:**
    *   `testId=login-screen` (Custom attributes attached via `FapMeta` widget)

---

## H. Security Model

*   **Enabled/Disabled:**
    *   FAP is **disabled by default**.
    *   Must be explicitly enabled via `FapConfig(enabled: true)` or a compile-time flag (`--dart-define=FAP_ENABLED=true`).
    *   **Release Builds:** The library should strictly no-op or throw in release mode unless specifically overridden.

*   **Authentication:**
    *   **Localhost:** Open by default for ease of development.
    *   **Remote:** Requires a `token` in the initial WebSocket handshake if binding to non-loopback interfaces.

---

## I. Test Plan / Quality Gate

1.  **Unit Tests (Dart):**
    *   Verify `SelectorParser` correctly parses complex strings.
    *   Verify `SemanticsIndexer` correctly traverses a mock tree.

2.  **Integration Tests (Dart):**
    *   Run the agent in a headless Flutter app.
    *   Verify gestures trigger `onTap` callbacks.

3.  **Node.js E2E Tests:**
    *   Launch a sample Flutter app.
    *   Connect the Node client.
    *   Perform a full flow: Login -> Navigate -> Scroll -> Logout.
    *   Verify state changes.

4.  **Performance Tests:**
    *   Measure overhead of the agent on frame rates.
    *   Stress test with deep widget trees.

5.  **Artifacts:**
    *   Test reports (JUnit/HTML).
    *   Screenshots of failure states.
