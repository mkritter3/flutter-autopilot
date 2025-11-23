1. Overview
1.1 Problem

Flutter’s UI is rendered via a canvas / synthetic DOM and is not easily accessible to browser-based test frameworks like Playwright, nor to AI agents (Gemini / Antigravity / Claude) that want to:

Discover UI elements

Click/tap buttons

Enter text

Navigate screens

Observe errors and performance issues

…as if they were real users.

We want a framework-agnostic, Playwright-style testing layer for Flutter, so agents can drive the app programmatically across:

Flutter Web

Flutter iOS

Flutter Android

(optionally) Flutter Desktop

1.2 Solution (High Level)

Create a Flutter Agent Protocol (FAP) that:

Runs inside the Flutter app as a small package.

Exposes a semantic UI control API over WebSockets / JSON-RPC.

Lets external clients (AI agents, test runners) query and manipulate the UI at the widget / semantics level, not at raw pixels.

Reports errors, logs, performance metrics, and screenshots back to the client.

Can be safely enabled only in test / dev / special “agentic” builds.

Conceptually:

Playwright works on the DOM.

FAP works on the Flutter Widget/Semantics tree.

2. Goals & Non-Goals
2.1 Goals

Provide a Playwright-like API for Flutter UI testing / control.

Work across web, mobile, desktop with a single abstraction.

Allow AI agents to:

Discover elements

Tap, scroll, drag, enter text

Wait for conditions

Verify text & state

Capture screenshots

Inspect errors & performance

Integrate cleanly into:

Local dev workflows

CI pipelines

Agentic tools like Google Antigravity / Gemini

2.2 Non-Goals

Not a DOM-based tool: we will not try to reconstruct a true HTML DOM.

Not a replacement for Flutter’s unit/widget tests; this is end-to-end / agentic.

Not a full visual diffing solution (we can add limited screenshot diffing later).

Not meant for production builds; must be disabled or heavily locked down in prod.

3. Requirements
3.1 Functional

Expose an API for:

Querying widgets by selectors

Retrieving widget metadata (label, role, key, bounds)

Performing actions (tap, longPress, drag, scroll, enterText, submit, back, etc.)

Waiting for conditions (widget appears, text present, route changes)

Getting error logs (FlutterError, assertion failures)

Getting performance metrics (frame timings, jank)

Capturing screenshots

Support:

Flutter Web

Flutter Mobile (Android/iOS)

(Optional) Flutter Desktop

Allow multiple concurrent sessions (e.g., multiple tests / agents).

3.2 Non-functional

Minimal runtime overhead when disabled; manageable overhead when enabled.

Secure: disabled in production or gated behind explicit opt-in and auth.

Extensible: allow app developers to define custom “roles” or metadata.

Stable selectors over time (within reason).

4. High-Level Architecture
4.1 Components

FAP Flutter Agent (in-app library)

Dart package added as a dependency.

Hooks into:

WidgetInspectorService

SemanticsBinding / SemanticsNode

GestureBinding

SchedulerBinding / FrameTiming

FlutterError.onError

Maintains:

A registry of widgets & semantics nodes.

A command handler that executes actions.

Communicates via:

WebSocket server (local)

OR HTTP+WebSocket bridging for web.

FAP Transport Layer

JSON-RPC style messages over WebSocket:

{"id": "123", "method": "tap", "params": {...}}

{"id": "123", "result": {...}} or {"id":"123","error":{...}}

FAP Controller / Client SDKs

Node.js / Python / Go / TS clients.

Helpers like:

fap.getByRole('button', { name: 'Save' })

fap.click('Button[text="Add Meal"]')

Integration with CI / AI agents.

Optional: FAP Test Runner

Simple CLI runner that:

Launches the app (or connects to existing instance).

Runs scripted flows.

Produces artifacts (logs, screenshots, reports).

4.2 Deployment Modes

Dev mode:

FAP enabled, listening on localhost/WebSocket.

CI mode:

FAP enabled, controlled by test runner.

Prod mode:

FAP disabled by default (compile-time flag or environment variable).

Or protected by auth token & restricted network.

5. Flutter Integration Details
5.1 Lifecycle

On app startup:

If FAP is enabled (via FapConfig):

Initialize WebSocket server.

Patch FlutterError.onError.

Register frame timing callbacks.

Hook into SemanticsBinding updates.

5.2 Widget Discovery & Semantics

Use:

WidgetInspectorService.instance to inspect the element tree (widgets & render objects).

SemanticsBinding.instance.pipelineOwner.semanticsOwner to access semantics nodes.

Maintain an internal index of “testable elements”:

Assign each a stable FAP Element ID (e.g., "fap-elem-000123").

Store metadata:

widget type

key

semantics label

role (button, textField, listItem, etc.)

text content

bounding box (local + global coordinates)

enabled/disabled, visible/hidden

This index is updated:

On every rebuild

Or on a debounced schedule (e.g., after frames with semantics changes)

5.3 Actions / Gesture Injection

Use GestureBinding and pointer events:

Tap:

Calculate center of widget bounds

Emit PointerDownEvent → short delay → PointerUpEvent

Drag:

Sequence of move events from start to end coordinates.

Scroll:

Wheel events (web) or drag-on-scrollable.

Text input:

Focus text field via tap.

Use TextInput APIs or send platform text events.

5.4 Error Reporting

Hook into:

FlutterError.onError

PlatformDispatcher.instance.onError (for async errors)

Optionally capture:

Log messages (via debugPrint override or logging layer)

Errors are stored in an in-memory log buffer and exposed via API:

getErrors

subscribeErrors (stream over WebSocket)

5.5 Performance Metrics

Use:

SchedulerBinding.instance!.addTimingsCallback(...) to capture FrameTiming.

Expose metrics like:

average frame time

99th percentile frame time

number of janky frames

FPS estimation

6. Selector Language

We need a selector syntax similar to Playwright but adapted for Flutter.

6.1 Selector Types

By Key

key=saveButton
key="meal-card-2025-01-04"


By Type

type=ElevatedButton
type=MealCard


By Role

role=button
role=textField
role=listItem


By Text or Label

text="Save"
label="Add Meal"
text*="garlic"


Complex / Combined

role=button & text="Add Meal"
type=MealCard & date="2025-01-04"
role=listItem & containsText="Chicken"


CSS-Style Shortcut (optional)

Button[text="Save"]
MealCard[date="2025-01-04"]
Input[label="Email"]

6.2 Selector Resolution

The agent:

Parses the selector.

Filters the indexed elements based on:

key

type

role

text/label substring

custom attributes (see 6.3)

If multiple matches:

Optionally support nth= selectors or index-based selection.

6.3 Custom Attributes & Roles

Allow developers to attach metadata:

FapMeta(
  role: 'meal-card',
  attrs: {
    'date': '2025-01-04',
    'mealType': 'dinner',
  },
  child: MealCard(...),
);


This metadata is included in the index, enabling selectors like:

role=meal-card & date="2025-01-04"

7. Protocol Specification
7.1 Transport

WebSocket connection.

Messages are JSON:

Request:

{
  "id": "uuid-123",
  "method": "tap",
  "params": {
    "selector": "role=button & text='Add Meal'",
    "timeoutMs": 5000
  }
}


Response:

{
  "id": "uuid-123",
  "result": {
    "status": "ok",
    "matchedElementId": "fap-elem-00192"
  }
}


Errors:

{
  "id": "uuid-123",
  "error": {
    "code": "ELEMENT_NOT_FOUND",
    "message": "No element found for selector ...",
    "details": { "selector": "..." }
  }
}

7.2 Core Methods

Discovery / Query

listElements(params)

Filter by role, type, text, key, etc.

getElementDetails({ elementId })

getTreeSnapshot({ includeChildren: boolean })

Actions

tap({ selector })

tapElement({ elementId })

doubleTap(...)

longPress(...)

enterText({ selector, text, clearFirst: boolean })

scroll({ direction, amount, containerSelector? })

drag({ fromSelector, toSelector })

navigateBack()

Waiting / Assertions

waitForElement({ selector, timeoutMs })

waitForText({ text, timeoutMs })

waitForNoElement({ selector, timeoutMs })

waitForRoute({ routeName, timeoutMs })

Observability

getErrors({ sinceTimestamp? })

getPerformanceMetrics({ windowMs? })

getLogs({ level?, sinceTimestamp? })

Screenshots

captureScreenshot({ fullPage?: boolean, rect?: {x,y,w,h} })

Returns base64 PNG or a URL pointer.

Session Control

ping()

resetAppState() (optional, app-specific)

setConfig({ ... })

8. Example Flows
8.1 Simple Login Test (External Client Pseudocode – TS)
const fap = await FapClient.connect("ws://localhost:9001");

// Wait for app ready
await fap.waitForElement({ selector: 'role=textField & label="Email"' });

// Enter credentials
await fap.enterText({ selector: 'role=textField & label="Email"', text: "user@example.com" });
await fap.enterText({ selector: 'role=textField & label="Password"', text: "secret123" });

// Tap login button
await fap.tap({ selector: 'role=button & text="Log In"' });

// Wait for home screen
await fap.waitForElement({ selector: 'role=label & text="Welcome back"', timeoutMs: 10000 });

// Capture screenshot
const png = await fap.captureScreenshot({});
fs.writeFileSync("home.png", Buffer.from(png, "base64"));

8.2 AI Agent Flow (High-Level)

Agent connects to FAP.

Calls listElements to get a high-level overview of the screen.

Uses element metadata to:

Find primary CTA button.

Identify navigation elements.

Chooses a sequence of actions based on task (e.g., “create a weekly meal plan”).

After each action, calls getErrors and getPerformanceMetrics to see:

Whether any new error occurred.

Whether performance degraded.

Logs all actions and observations as an artifact.

9. Security & Configuration
9.1 Enabling FAP

Controlled by:

Environment variable: FAP_ENABLED=true

Or compilation flag

Or explicit initialization in main():

void main() {
  const bool enableAgent = bool.fromEnvironment('fap', defaultValue: false);
  if (enableAgent) {
    FapAgent.init(FapConfig(...));
  }
  runApp(MyApp());
}

9.2 Network Restrictions

Default:

Bind only to localhost / emulator loopback.

For remote / CI:

Bind to specific interface.

Use token-based authentication:

Auth: Bearer <token> header in WebSocket upgrade request params.

Token configured via environment.

9.3 Production

In production builds, either:

Fully disabled (preferred).

Or enabled only behind:

Feature flag

Strong authentication

IP allowlists

10. Extensibility & Roadmap
10.1 Phase 1 – MVP

Basic agent:

Query by key, role, text.

Tap, enter text, scroll.

Error logging.

Frame timing metrics.

Screenshots on mobile & web.

Node.js client library for test scripts.

10.2 Phase 2 – Advanced Selectors & Custom Metadata

FapMeta widget for custom roles/attributes.

Complex logical selectors (AND, OR).

Route-based navigation utilities.

10.3 Phase 3 – AI Optimization

Predefined “semantic maps”:

Label important flows: onboarding, main navigation, primary CTAs.

Provide “screen summary” endpoint:

Returns a compact description of visible UI for LLMs:

{
  "screenTitle": "Meal Calendar",
  "primaryActions": ["Add Meal", "View Grocery List"],
  "elements": [
    { "role": "button", "label": "Add Meal", "id": "..." },
    ...
  ]
}

10.4 Phase 4 – CI Tooling

CLI:

fap run tests/e2e/*.spec.ts

GitHub Actions examples.

HTML test reports with screenshots & error logs.