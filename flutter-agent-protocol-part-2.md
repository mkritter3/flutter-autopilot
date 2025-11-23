⭐ NEXT STEPS & SUCCESS CRITERIA

(Based on what your design doc already covers — this list contains ONLY what remains to be built.)

1. Implement Core FAP Engine (Dart)
Next Steps

Implement in-app WebSocket server

Implement JSON-RPC dispatcher

Build element indexer using:

WidgetInspectorService

SemanticsBinding

RenderObject bounds extraction

Implement gesture injector:

Tap

Double-tap

Long-press

Drag

Scroll

Implement text entry & text manipulation

Implement error capture + error buffer

Implement performance capture (frame timing)

Implement screenshot pipeline (web/mobile/desktop)

Success Criteria

Connecting to FAP returns a valid hello/ping response

Calling listElements() returns accurate metadata for on-screen widgets

Calling tap() updates the UI as expected

Error buffer receives new errors on UI failures

Frame timing metrics stream appears with correct values

captureScreenshot() works in:

Flutter Web

Flutter iOS simulator

Flutter Android emulator

Desktop (optional)

2. Selector Engine Implementation
Next Steps

Implement selector tokenizer → AST parser

Implement matcher over the indexed elements

Support:

type=

role=

text= / contains

key=

logical & and |

custom metadata attributes (from FapMeta)

Success Criteria

All selector types resolve correctly

Ambiguous selectors produce multi-match lists

Invalid selectors produce structured errors

Complex selectors (role=button & text*="Add") resolve correctly

3. Add WYSIWYG / Advanced Text Control Module

(Needed for your custom editor use cases)

Next Steps

Expose text editing controllers via FapMeta

Implement:

caret movement

text selection by offset

selection by word / line / paragraph

selecting via gestures (dragging)

Implement querying:

selection range

visible text spans

popup menu items

Success Criteria

AI can select text programmatically

AI can click toolbar items (Bold, Italic, etc.)

Selecting text updates selection range

Popup menus appear in listElements()

4. Node.js Client SDK (FAP Client)
Next Steps

Implement WebSocket session handling

Build helper APIs:

tap(selector)

enterText(selector, text)

scroll(selector)

waitFor(selector)

listElements()

Add screenshot utilities

Add error + performance fetching

Success Criteria

Client can connect to running Flutter app

All core methods work end-to-end

Errors surfaced in structured form

Screenshots can be saved to disk

SDK works in plain Node (no frameworks needed)

5. MCP Wrapper (Optional but Recommended)
Next Steps

Define MCP tool catalog

Map MCP tool calls → FAP client methods

Implement streaming screenshot returns

Implement MCP error mapping

Provide tool schemas for Gemini / Claude

Success Criteria

MCP client (Gemini / Claude Desktop) can:

list elements

tap

enter text

scroll

take screenshots

fetch errors

Agentic step-by-step exploration works without writing tests

6. Example Demo Flutter App (for validation)
Next Steps

Build simple app with:

Text fields

Form

List + scrolling

Buttons

Navigation

Dialogs

Popup menu

Custom WYSIWYG editor (or placeholder)

Add FapMeta roles/attributes

Success Criteria

Full automated journey (login → navigate → edit text → submit) works via FAP

AI can run explorations and modify text

Errors intentionally triggered in the app are caught

Performance metrics stream is valid

7. Full E2E Verification Suite
Next Steps

Write integration tests using Node FAP client

Test across:

Flutter Web

iOS simulator

Android emulator

Desktop (optional)

Include:

selection tests

popup tests

navigation tests

screenshot tests

error-detection tests

Success Criteria

Entire suite passes locally

Entire suite passes in CI

Screenshots captured in CI environment

Errors displayed correctly in reports

Performance metrics stable with no regressions

8. Documentation & Developer Experience
Next Steps

Write:

API reference

Quickstart guide

“How to enable FAP in your Flutter app”

“Selector language guide”

“WYSIWYG extensions guide”

“MCP integration guide”

Provide example code snippets

Success Criteria

New developers can integrate FAP in under 10 minutes

Agents can run workflows without developer help

Docs cover all major flows + troubleshooting