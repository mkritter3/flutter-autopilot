import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
    CallToolRequestSchema,
    ListToolsRequestSchema,
    ListResourcesRequestSchema,
    ReadResourceRequestSchema,
    ErrorCode,
    McpError,
} from "@modelcontextprotocol/sdk/types.js";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { FapClient } from "fap-client";

// Development tools for autonomous testing
import {
    vmService,
    fileOps,
    codeAnalysis,
    testRunner,
    setProjectRoot,
} from "./dev-tools.js";

interface ConfigFile {
    agentUrl?: string;
    agentHost?: string;
    agentPort?: number;
    agentSecure?: boolean;
    secretToken?: string;
    adbReverse?: boolean;
}

interface LoadedConfig {
    path: string;
    data: ConfigFile;
}

interface AgentResolution {
    url: string;
    reason: string;
    secretToken?: string;
}

function resolveAgentEndpoint(): AgentResolution {
    const envUrl = process.env.FAP_AGENT_URL?.trim();
    if (envUrl) {
        return { url: envUrl, reason: "env:FAP_AGENT_URL" };
    }

    const envHost = process.env.FAP_AGENT_HOST?.trim();
    const envPort = parsePort(process.env.FAP_AGENT_PORT);
    const envSecure = parseBoolean(process.env.FAP_AGENT_SECURE);
    if (envHost) {
        return {
            url: formatUrl(envHost, envPort ?? 9001, envSecure),
            reason: "env:FAP_AGENT_HOST/PORT",
        };
    }

    const config = loadConfigFile();
    if (config) {
        const { data } = config;
        if (typeof data.agentUrl === "string" && data.agentUrl.trim().length > 0) {
            return {
                url: data.agentUrl,
                reason: `config:${config.path}`,
                secretToken: data.secretToken,
            };
        }
        if (data.agentHost) {
            const port = data.agentPort ?? envPort ?? 9001;
            return {
                url: formatUrl(data.agentHost, port, data.agentSecure),
                reason: `config:${config.path}`,
                secretToken: data.secretToken,
            };
        }
    }

    const port = envPort ?? config?.data.agentPort ?? 9001;
    if (shouldAttemptAdbReverse(config?.data) && tryAdbReverse(port)) {
        return {
            url: formatUrl("127.0.0.1", port, false),
            reason: "adb reverse (auto)",
            secretToken: config?.data.secretToken,
        };
    }

    const fallback = determineFallbackHost();
    return {
        url: formatUrl(fallback.host, port, false),
        reason: fallback.reason,
        secretToken: config?.data.secretToken,
    };
}

function loadConfigFile(): LoadedConfig | null {
    const specific = process.env.FAP_MCP_CONFIG?.trim();
    const candidates = [
        specific,
        path.join(process.cwd(), "fap_mcp.config.json"),
        path.join(process.cwd(), ".fap_mcp.json"),
        path.join(os.homedir(), ".fap_mcp.json"),
    ].filter((p): p is string => Boolean(p));

    for (const candidate of candidates) {
        try {
            const resolved = path.resolve(candidate);
            if (!fs.existsSync(resolved)) {
                continue;
            }
            const raw = fs.readFileSync(resolved, "utf-8");
            const parsed = JSON.parse(raw);
            if (parsed && typeof parsed === "object") {
                const normalized: ConfigFile = {
                    agentUrl: typeof (parsed as any).agentUrl === "string" ? (parsed as any).agentUrl : undefined,
                    agentHost: typeof (parsed as any).agentHost === "string" ? (parsed as any).agentHost : undefined,
                    agentPort: parsePort((parsed as any).agentPort),
                    agentSecure: parseBoolean((parsed as any).agentSecure),
                    secretToken: typeof (parsed as any).secretToken === "string" ? (parsed as any).secretToken : undefined,
                    adbReverse: typeof (parsed as any).adbReverse === "boolean" ? (parsed as any).adbReverse : undefined,
                };
                return { path: resolved, data: normalized };
            }
        } catch (error) {
            console.error(`FAP MCP: Failed to load config file ${candidate}:`, error);
        }
    }
    return null;
}

function parsePort(value?: string | number | null): number | undefined {
    if (value === undefined || value === null) {
        return undefined;
    }
    if (typeof value === "number") {
        return Number.isFinite(value) ? value : undefined;
    }
    const num = Number(value);
    if (!Number.isNaN(num) && num > 0) {
        return num;
    }
    return undefined;
}

function parseBoolean(value?: string | boolean | null): boolean | undefined {
    if (value === undefined || value === null) {
        return undefined;
    }
    if (typeof value === "boolean") {
        return value;
    }
    const normalized = value.trim().toLowerCase();
    if (normalized === "true") return true;
    if (normalized === "false") return false;
    return undefined;
}

function formatUrl(host: string, port: number, secure?: boolean): string {
    const protocol = secure ? "wss" : "ws";
    const needsBrackets = host.includes(":") && !host.startsWith("[");
    const hostPart = needsBrackets ? `[${host}]` : host;
    return `${protocol}://${hostPart}:${port}`;
}

function shouldAttemptAdbReverse(config?: ConfigFile): boolean {
    const skipEnv = process.env.FAP_SKIP_ADB_REVERSE?.toLowerCase();
    if (skipEnv === "true") {
        return false;
    }
    if (skipEnv === "false") {
        return true;
    }
    if (config?.adbReverse === false) {
        return false;
    }
    return true;
}

function tryAdbReverse(port: number): boolean {
    // Security: Validate port is a safe integer within valid range
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
        console.error(`tryAdbReverse: Invalid port ${port}, must be 1-65535`);
        return false;
    }

    try {
        const result = spawnSync("adb", ["reverse", `tcp:${port}`, `tcp:${port}`], { stdio: "ignore" });
        return result.status === 0;
    } catch {
        return false;
    }
}

function determineFallbackHost(): { host: string; reason: string } {
    const dockerHost = process.env.FAP_DOCKER_HOST?.trim();
    if (dockerHost) {
        return { host: dockerHost, reason: "env:FAP_DOCKER_HOST" };
    }

    if (fs.existsSync("/.dockerenv")) {
        return { host: "host.docker.internal", reason: "docker default host" };
    }

    return { host: "127.0.0.1", reason: "default localhost" };
}

const agentResolution = resolveAgentEndpoint();
const agentUrl = agentResolution.url;
const timeoutEnv = process.env.FAP_AGENT_TIMEOUT_MS;
const timeoutMs = timeoutEnv !== undefined ? Number(timeoutEnv) : undefined;
const normalizedTimeout = timeoutMs !== undefined && !Number.isNaN(timeoutMs) ? timeoutMs : undefined;

if (timeoutEnv !== undefined && normalizedTimeout === undefined) {
    console.error(`Invalid FAP_AGENT_TIMEOUT_MS="${timeoutEnv}". Falling back to default timeout.`);
}

// Initialize FAP Client
const fap = new FapClient({
    url: agentUrl,
    secretToken: process.env.FAP_SECRET_TOKEN ?? agentResolution.secretToken,
    timeoutMs: normalizedTimeout,
});
console.error(`FAP MCP: targeting agent at ${agentUrl} (${agentResolution.reason})`);

// Initialize MCP Server
const server = new Server(
    {
        name: "fap-mcp-server",
        version: "1.0.0",
    },
    {
        capabilities: {
            resources: {},
            tools: {},
        },
    }
);

// --- Tools ---

server.setRequestHandler(ListToolsRequestSchema, async () => {
    return {
        tools: [
            {
                name: "list_elements",
                description: `Get a hierarchical list of all UI elements currently visible on the screen. Returns the Flutter semantics tree with element IDs, types, text, labels, keys, and coordinates.

IMPORTANT - Coordinate System:
- Coordinates returned are in DEVICE PIXELS (not logical points)
- On iOS (iPhone): divide coordinates by 3 before using with tap_at
- On Android/Desktop: coordinates are usually 1:1 with logical points

Use this FIRST to:
1. Discover available selectors (key, text, label, type) for tap/enter_text
2. Get element coordinates for tap_at when selectors don't work
3. Verify UI state after actions

Limitations:
- Custom painters, WebViews, and native platform views may not appear
- Native iOS/Android views presented ON TOP of Flutter (e.g., Plaid SDK, in-app browsers) are NOT controllable via FAP - these run outside Flutter's widget tree
- For elements not in the tree, use tap_at with visual grounding (screenshot analysis)`,
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "tap",
                description: `Tap on a UI element matching the given selector. Use for buttons, links, list items, checkboxes, etc.

Selector types (in order of reliability):
1. key="submit_btn" - Flutter Key (BEST - stable across UI changes)
2. text="Save" - Visible text content
3. label="Submit form" - Accessibility label (semanticsLabel)
4. type="ElevatedButton" - Widget type (least reliable)

Tips:
- Always call list_elements first to discover available selectors
- If tap fails with "element not found", the selector may be wrong or element not in semantics tree
- If element exists but tap doesn't work, try tap_at with coordinates instead
- For native views (Plaid, WebViews), FAP cannot interact - they run outside Flutter`,
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: {
                            type: "string",
                            description: "Selector to identify the element. Format: 'key=\"value\"', 'text=\"value\"', 'label=\"value\"', or 'type=\"value\"'. Use list_elements to discover available selectors.",
                        },
                    },
                    required: ["selector"],
                },
            },
            {
                name: "tap_at",
                description: `Tap at specific screen coordinates (x, y) in LOGICAL POINTS.

CRITICAL - Coordinate Scaling:
- list_elements returns coordinates in DEVICE PIXELS
- tap_at expects LOGICAL POINTS
- iOS (iPhone): DIVIDE coordinates by 3 (device pixel ratio)
- Android/Desktop: coordinates are usually 1:1

Example workflow:
1. list_elements shows button at rect: {left: 900, top: 1200, ...}
2. Calculate center: x=900+(width/2), y=1200+(height/2)
3. On iOS: divide by 3 → tap_at(x/3, y/3)

When to use tap_at instead of tap:
- Element coordinates known but selector doesn't work
- Visual Grounding: using VLM/screenshot analysis to find elements
- Elements not in semantics tree (custom painters, canvas)
- Fallback when tap() fails

Note: Cannot interact with native iOS/Android views (Plaid SDK, WebViews presented over Flutter)`,
                inputSchema: {
                    type: "object",
                    properties: {
                        x: { type: "number", description: "X coordinate in logical points. On iOS: divide device pixel coordinate by 3" },
                        y: { type: "number", description: "Y coordinate in logical points. On iOS: divide device pixel coordinate by 3" },
                    },
                    required: ["x", "y"],
                },
            },
            {
                name: "enter_text",
                description: `Enter text into a text field by APPENDING to existing content. Simulates typing character by character.

Important behavior:
- This APPENDS text to existing field content (doesn't replace)
- To replace text, use set_text instead
- Field should have focus (tap it first if text doesn't appear)
- Works with TextField, TextFormField, and similar widgets

Tips:
- Use list_elements to find the field's selector
- Prefer key="field_name" selectors when available
- If enter_text doesn't work, try: tap the field first, then enter_text
- For obscured fields (passwords), text still enters normally`,
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: {
                            type: "string",
                            description: "Selector to identify the text field. Prefer key selectors (e.g., 'key=\"email_field\"').",
                        },
                        text: {
                            type: "string",
                            description: "Text to type into the field. Will be appended to existing content.",
                        },
                    },
                    required: ["selector", "text"],
                },
            },
            {
                name: "scroll",
                description: `Scroll a scrollable UI element (ListView, SingleChildScrollView, CustomScrollView, etc.).

Scroll direction:
- Positive dy: scroll DOWN (content moves up, reveals items below)
- Negative dy: scroll UP (content moves down, reveals items above)
- Positive dx: scroll RIGHT
- Negative dx: scroll LEFT

Tips:
- Use list_elements to find the scrollable container's selector
- Start with smaller values (100-300) and increase if needed
- If element not found after scroll, it may not be in the current viewport yet
- Very long lists may need multiple scrolls to reach distant items`,
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: {
                            type: "string",
                            description: "Selector for the scrollable element (ListView, ScrollView, etc.).",
                        },
                        dx: {
                            type: "number",
                            description: "Horizontal scroll amount in logical pixels. Positive = right, negative = left.",
                        },
                        dy: {
                            type: "number",
                            description: "Vertical scroll amount in logical pixels. Positive = down, negative = up.",
                        },
                        durationMs: {
                            type: "number",
                            description: "Scroll animation duration in ms (default 300). Longer = smoother.",
                        },
                    },
                    required: ["selector", "dx", "dy"],
                },
            },
            {
                name: "get_route",
                description: `Get the current Flutter route/screen name. Useful for verifying navigation worked.

Returns the route name as configured in the app's routing (e.g., '/home', '/settings', 'LoginScreen').

Use cases:
- Verify navigation to expected screen after tap
- Debug unexpected screen transitions
- Confirm app state before performing actions`,
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "drag",
                description: `Drag an element to another element or by a pixel offset. Use for sliders, reorderable lists, swipe-to-dismiss, etc.

Two modes:
1. targetSelector: Drag from one element TO another element
2. dx/dy offset: Drag from element BY a pixel distance

Use cases:
- Adjust sliders (drag thumb by dx offset)
- Reorder items in lists (drag to targetSelector)
- Swipe-to-dismiss (drag with negative dx for left swipe)
- Pull-to-refresh (drag with positive dy)`,
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: { type: "string", description: "Selector for the element to drag." },
                        targetSelector: { type: "string", description: "Selector for destination element (mutually exclusive with dx/dy)." },
                        dx: { type: "number", description: "X offset in logical pixels (used if targetSelector not provided)." },
                        dy: { type: "number", description: "Y offset in logical pixels (used if targetSelector not provided)." },
                        durationMs: { type: "number", description: "Drag duration in ms (default 300). Slower = more visible animation." },
                    },
                    required: ["selector"],
                },
            },
            {
                name: "long_press",
                description: `Long press (press and hold) on an element. Triggers onLongPress callbacks in Flutter.

Use cases:
- Show context menus
- Enable selection/edit mode
- Trigger haptic feedback actions
- Activate drag-and-drop mode`,
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: { type: "string", description: "Selector for the element to long press." },
                        durationMs: { type: "number", description: "Press duration in ms (default 800). Some widgets need longer holds." },
                    },
                    required: ["selector"],
                },
            },
            {
                name: "double_tap",
                description: `Double tap (two quick taps) on an element. Triggers onDoubleTap callbacks in Flutter.

Use cases:
- Zoom in/out on images or maps
- Select text (word selection)
- Like/favorite content (Instagram-style)
- Activate edit mode`,
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: { type: "string", description: "Selector for the element to double tap." },
                    },
                    required: ["selector"],
                },
            },
            {
                name: "get_logs",
                description: `Get captured console logs (print statements, debugPrint, log calls) from the app.

Use cases:
- Debug app behavior by checking log output
- Verify expected events occurred (e.g., API calls, state changes)
- See developer debugging info
- Monitor app lifecycle events`,
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "get_errors",
                description: `Get captured errors (Flutter framework errors, async exceptions, uncaught errors) from the app.

Use cases:
- Debug red screen errors
- Find async/Future errors that may be swallowed
- Identify framework-level issues
- Debug crashes or unexpected behavior

Returns error messages, stack traces, and error types.`,
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "get_performance_metrics",
                description: `Get frame timing metrics for performance analysis.

Returns:
- Build times (widget tree construction)
- Raster times (GPU rendering)
- Frame counts and rates

Use to identify:
- Jank (frames taking >16ms)
- Performance regressions
- Heavy build/raster operations`,
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "set_text",
                description: `Set (replace) the entire text content of a text field. Unlike enter_text which appends, this REPLACES all existing text.

Use cases:
- Clear and set new value in one operation
- Fill forms where you need exact text content
- Reset field to known state before testing

Note: Field should exist in the widget tree (use list_elements to verify).`,
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: { type: "string", description: "Selector for the text field to modify." },
                        text: { type: "string", description: "New text content (replaces existing)." },
                    },
                    required: ["selector", "text"],
                },
            },
            {
                name: "set_selection",
                description: `Set the text selection range (cursor position) within a text field.

Use cases:
- Position cursor at specific location (set base=extent for cursor, no selection)
- Select portion of text for copy/cut/delete (base != extent)
- Select all text (base=0, extent=text.length)

Parameters:
- base: Start of selection (0-indexed character position)
- extent: End of selection (0-indexed)`,
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: { type: "string", description: "Selector for the text field." },
                        base: { type: "number", description: "Selection start offset (0-indexed)." },
                        extent: { type: "number", description: "Selection end offset (0-indexed). Same as base for cursor position." },
                    },
                    required: ["selector", "base", "extent"],
                },
            },

            {
                name: "start_recording",
                description: `Start recording user interactions to generate a replayable FAP script.

Records:
- Taps and tap coordinates
- Text entry
- Scrolls and gestures
- Navigation events

Use to create test scripts from manual interaction sessions.`,
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "stop_recording",
                description: `Stop the recording session and get the recorded interaction script.

Call this after performing the manual interactions you want to capture.
Returns a script that can be replayed for automated testing.`,
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },

            // === Development Tools ===
            // These tools enable autonomous development workflows:
            // edit code → hot reload → test UI → iterate

            {
                name: "set_project_root",
                description: `Set the Flutter project directory for file operations, code analysis, and test execution.

MUST be called FIRST before using: read_file, write_file, search_code, list_files, analyze_code, apply_fixes, format_code, run_tests.

The path should be the root of the Flutter project (where pubspec.yaml is located).`,
                inputSchema: {
                    type: "object",
                    properties: {
                        path: {
                            type: "string",
                            description: "Absolute path to Flutter project root (where pubspec.yaml lives).",
                        },
                    },
                    required: ["path"],
                },
            },
            {
                name: "set_vm_service_uri",
                description: `Set the Flutter VM Service URI for hot reload/restart capabilities.

How to get the URI:
1. Run 'flutter run' in the terminal
2. Look for output like: "Flutter DevTools at http://127.0.0.1:XXXXX?uri=..."
3. The VM Service URI is in the format: http://127.0.0.1:XXXXX/XXXXX=/

MUST be called before: hot_reload, hot_restart, get_vm_info.`,
                inputSchema: {
                    type: "object",
                    properties: {
                        uri: {
                            type: "string",
                            description: "VM Service URI from flutter run output (e.g., 'http://127.0.0.1:50505/abc123=/').",
                        },
                    },
                    required: ["uri"],
                },
            },
            {
                name: "hot_reload",
                description: `Trigger a hot reload to apply code changes WITHOUT losing app state.

Requires: set_vm_service_uri called first.

Hot reload:
- Injects updated code into running Dart VM
- Preserves app state (variables, navigation, etc.)
- Fast (~sub-second)
- Use for UI changes, minor code tweaks

Won't work for: main() changes, global initializers, enum changes, some static fields.`,
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "hot_restart",
                description: `Trigger a hot restart to fully restart the app with new code.

Requires: set_vm_service_uri called first.

Hot restart:
- Restarts the Dart VM completely
- Loses all app state (returns to initial screen)
- Slower than hot reload (~2-5 seconds)
- Use for: main() changes, initialization changes, global state reset

Use when hot_reload fails or state needs reset.`,
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "read_file",
                description: `Read the contents of a file in the project.

Requires: set_project_root called first.

Supports relative paths (from project root) or absolute paths.
Common uses: read lib/main.dart, read test/widget_test.dart`,
                inputSchema: {
                    type: "object",
                    properties: {
                        path: {
                            type: "string",
                            description: "File path (relative to project root, or absolute). Example: 'lib/main.dart'",
                        },
                    },
                    required: ["path"],
                },
            },
            {
                name: "write_file",
                description: `Write content to a file in the project. Creates parent directories as needed.

Requires: set_project_root called first.

Workflow for code changes:
1. read_file to get current content
2. Modify the content
3. write_file to save changes
4. hot_reload to apply changes to running app`,
                inputSchema: {
                    type: "object",
                    properties: {
                        path: {
                            type: "string",
                            description: "File path (relative or absolute). Parent directories created automatically.",
                        },
                        content: {
                            type: "string",
                            description: "Complete file content to write.",
                        },
                    },
                    required: ["path", "content"],
                },
            },
            {
                name: "search_code",
                description: `Search for code patterns in the project using grep (regex supported).

Requires: set_project_root called first.

Examples:
- search_code('class.*Widget') - find all Widget classes
- search_code('TODO', '*.dart') - find TODOs in Dart files
- search_code('api_key', '*.dart') - security audit for hardcoded keys`,
                inputSchema: {
                    type: "object",
                    properties: {
                        pattern: {
                            type: "string",
                            description: "Search pattern (supports regex). Examples: 'setState', 'class.*StatefulWidget'",
                        },
                        filePattern: {
                            type: "string",
                            description: "File glob pattern (default: *.dart). Examples: '*.yaml', '*.json', 'test/*.dart'",
                        },
                    },
                    required: ["pattern"],
                },
            },
            {
                name: "list_files",
                description: `List files in a directory, optionally filtered by pattern.

Requires: set_project_root called first.

Examples:
- list_files('lib') - list all files in lib/
- list_files('lib', '.dart') - only Dart files
- list_files('test', '_test.dart') - only test files`,
                inputSchema: {
                    type: "object",
                    properties: {
                        path: {
                            type: "string",
                            description: "Directory path relative to project root (default: '.' for project root).",
                        },
                        pattern: {
                            type: "string",
                            description: "Filter pattern (e.g., '.dart', 'test', '_widget').",
                        },
                    },
                },
            },
            {
                name: "analyze_code",
                description: `Run 'dart analyze' to find code issues (errors, warnings, hints, lints).

Requires: set_project_root called first.

Returns:
- Compilation errors (must fix)
- Warnings (should fix)
- Hints and style suggestions (optional)

Run after code changes to catch issues before hot reload.`,
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "apply_fixes",
                description: `Run 'dart fix' to automatically fix code issues.

Requires: set_project_root called first.

Fixes include:
- Deprecated API migrations
- Lint rule violations
- Style corrections

Use dryRun=true first to preview changes.`,
                inputSchema: {
                    type: "object",
                    properties: {
                        dryRun: {
                            type: "boolean",
                            description: "If true, show proposed fixes without applying. Default: false (apply fixes).",
                        },
                    },
                },
            },
            {
                name: "format_code",
                description: `Run 'dart format' to format code files according to Dart style guide.

Requires: set_project_root called first.

Formats code to standard 80-char line width with consistent indentation.
Run before committing code.`,
                inputSchema: {
                    type: "object",
                    properties: {
                        path: {
                            type: "string",
                            description: "File or directory to format (default: entire project).",
                        },
                    },
                },
            },
            {
                name: "run_tests",
                description: `Run Flutter/Dart tests.

Requires: set_project_root called first.

Examples:
- run_tests() - run all tests
- run_tests('test/widget_test.dart') - run specific test
- run_tests('test/unit/', 'expanded') - run directory with verbose output`,
                inputSchema: {
                    type: "object",
                    properties: {
                        path: {
                            type: "string",
                            description: "Test file or directory (optional, defaults to all tests).",
                        },
                        reporter: {
                            type: "string",
                            description: "Output format: 'compact' (default), 'expanded' (verbose), 'json' (machine-readable).",
                        },
                    },
                },
            },
            {
                name: "get_vm_info",
                description: `Get information about the running Flutter VM.

Requires: set_vm_service_uri called first.

Returns:
- Dart version
- Isolate information
- VM uptime and memory usage

Useful for debugging and verifying connection to running app.`,
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
        ],
    };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
    try {
        // Ensure connected
        if (!fap.isConnected) {
            await fap.connect();
        }

        switch (request.params.name) {
            case "list_elements": {
                const elements = await fap.getTree();
                return {
                    content: [
                        {
                            type: "text",
                            text: JSON.stringify(elements, null, 2),
                        },
                    ],
                };
            }

            case "tap": {
                const { selector } = request.params.arguments as { selector: string };
                const result = await fap.tap(selector);
                return {
                    content: [
                        {
                            type: "text",
                            text: `Tapped element: ${JSON.stringify(result)}`,
                        },
                    ],
                };
            }

            case "tap_at": {
                const { x, y } = request.params.arguments as { x: number; y: number };
                const result = await fap.tapAt(x, y);
                return {
                    content: [
                        {
                            type: "text",
                            text: `Tapped at (${x}, ${y}): ${JSON.stringify(result)}`,
                        },
                    ],
                };
            }

            case "enter_text": {
                const { selector, text } = request.params.arguments as { selector: string; text: string };
                const result = await fap.enterText(text, selector);
                return {
                    content: [
                        {
                            type: "text",
                            text: `Entered text: ${JSON.stringify(result)}`,
                        },
                    ],
                };
            }

            case "scroll": {
                const { selector, dx, dy, durationMs } = request.params.arguments as {
                    selector: string;
                    dx: number;
                    dy: number;
                    durationMs?: number;
                };
                const result = await fap.scroll(selector, dx, dy, durationMs);
                return {
                    content: [
                        {
                            type: "text",
                            text: `Scrolled: ${JSON.stringify(result)}`,
                        },
                    ],
                };
            }

            case "get_route": {
                const route = await fap.getRoute();
                return {
                    content: [
                        {
                            type: "text",
                            text: `Current route: ${route}`,
                        },
                    ],
                };
            }

            case "drag": {
                const args = request.params.arguments as {
                    selector: string;
                    targetSelector?: string;
                    dx?: number;
                    dy?: number;
                    durationMs?: number
                };

                let target: string | { x: number; y: number };
                if (args.targetSelector) {
                    target = args.targetSelector;
                } else if (args.dx !== undefined && args.dy !== undefined) {
                    target = { x: args.dx, y: args.dy };
                } else {
                    throw new McpError(ErrorCode.InvalidParams, "Either targetSelector or dx/dy must be provided for drag");
                }

                const result = await fap.drag(args.selector, target, args.durationMs);
                return {
                    content: [{ type: "text", text: `Dragged: ${JSON.stringify(result)}` }],
                };
            }

            case "long_press": {
                const { selector, durationMs } = request.params.arguments as { selector: string; durationMs?: number };
                const result = await fap.longPress(selector, durationMs);
                return {
                    content: [{ type: "text", text: `Long Pressed: ${JSON.stringify(result)}` }],
                };
            }

            case "double_tap": {
                const { selector } = request.params.arguments as { selector: string };
                const result = await fap.doubleTap(selector);
                return {
                    content: [{ type: "text", text: `Double Tapped: ${JSON.stringify(result)}` }],
                };
            }

            case "get_logs": {
                const logs = await fap.getLogs();
                return {
                    content: [{ type: "text", text: JSON.stringify(logs, null, 2) }],
                };
            }

            case "get_errors": {
                const errors = await fap.getErrors();
                return {
                    content: [{ type: "text", text: JSON.stringify(errors, null, 2) }],
                };
            }

            case "get_performance_metrics": {
                const metrics = await fap.getPerformanceMetrics();
                return {
                    content: [{ type: "text", text: JSON.stringify(metrics, null, 2) }],
                };
            }

            case "set_text": {
                const { selector, text } = request.params.arguments as { selector: string; text: string };
                await fap.setText(selector, text);
                return {
                    content: [{ type: "text", text: `Text set to: ${text}` }],
                };
            }

            case "set_selection": {
                const { selector, base, extent } = request.params.arguments as { selector: string; base: number; extent: number };
                await fap.setSelection(selector, base, extent);
                return {
                    content: [{ type: "text", text: `Selection set: ${base}-${extent}` }],
                };

            }

            case "start_recording": {
                await fap.startRecording();
                return {
                    content: [{ type: "text", text: "Recording started" }],
                };
            }

            case "stop_recording": {
                await fap.stopRecording();
                return {
                    content: [{ type: "text", text: "Recording stopped" }],
                };
            }

            // === Development Tools ===

            case "set_project_root": {
                const { path: projectPath } = request.params.arguments as { path: string };
                setProjectRoot(projectPath);
                return {
                    content: [{ type: "text", text: `Project root set to: ${projectPath}` }],
                };
            }

            case "set_vm_service_uri": {
                const { uri } = request.params.arguments as { uri: string };
                vmService.setUri(uri);
                return {
                    content: [{ type: "text", text: `VM Service URI set to: ${uri}` }],
                };
            }

            case "hot_reload": {
                const result = await vmService.hotReload();
                return {
                    content: [{ type: "text", text: result.message }],
                    isError: !result.success,
                };
            }

            case "hot_restart": {
                const result = await vmService.hotRestart();
                return {
                    content: [{ type: "text", text: result.message }],
                    isError: !result.success,
                };
            }

            case "read_file": {
                const { path: filePath } = request.params.arguments as { path: string };
                const result = fileOps.readFile(filePath);
                if (!result.success) {
                    return {
                        content: [{ type: "text", text: `Error: ${result.error}` }],
                        isError: true,
                    };
                }
                return {
                    content: [{ type: "text", text: result.content! }],
                };
            }

            case "write_file": {
                const { path: filePath, content } = request.params.arguments as { path: string; content: string };
                const result = fileOps.writeFile(filePath, content);
                if (!result.success) {
                    return {
                        content: [{ type: "text", text: `Error: ${result.error}` }],
                        isError: true,
                    };
                }
                return {
                    content: [{ type: "text", text: `File written: ${filePath}` }],
                };
            }

            case "search_code": {
                const { pattern, filePattern } = request.params.arguments as { pattern: string; filePattern?: string };
                const result = fileOps.searchCode(pattern, filePattern);
                if (!result.success) {
                    return {
                        content: [{ type: "text", text: `Error: ${result.error}` }],
                        isError: true,
                    };
                }
                return {
                    content: [{ type: "text", text: JSON.stringify(result.matches, null, 2) }],
                };
            }

            case "list_files": {
                const { path: dirPath, pattern } = request.params.arguments as { path?: string; pattern?: string };
                const result = fileOps.listFiles(dirPath, pattern);
                if (!result.success) {
                    return {
                        content: [{ type: "text", text: `Error: ${result.error}` }],
                        isError: true,
                    };
                }
                return {
                    content: [{ type: "text", text: JSON.stringify(result.files, null, 2) }],
                };
            }

            case "analyze_code": {
                const result = codeAnalysis.analyze();
                if (!result.success) {
                    return {
                        content: [{ type: "text", text: `Error: ${result.error}` }],
                        isError: true,
                    };
                }
                const summary = `Found ${result.issues!.length} issues`;
                return {
                    content: [{ type: "text", text: `${summary}\n\n${JSON.stringify(result.issues, null, 2)}` }],
                };
            }

            case "apply_fixes": {
                const { dryRun } = request.params.arguments as { dryRun?: boolean };
                const result = codeAnalysis.applyFixes(dryRun ?? false);
                if (!result.success) {
                    return {
                        content: [{ type: "text", text: `Error: ${result.error}` }],
                        isError: true,
                    };
                }
                return {
                    content: [{ type: "text", text: result.output! }],
                };
            }

            case "format_code": {
                const { path: formatPath } = request.params.arguments as { path?: string };
                const result = codeAnalysis.formatCode(formatPath);
                if (!result.success) {
                    return {
                        content: [{ type: "text", text: `Error: ${result.error}` }],
                        isError: true,
                    };
                }
                return {
                    content: [{ type: "text", text: result.output! }],
                };
            }

            case "run_tests": {
                const { path: testPath, reporter } = request.params.arguments as { path?: string; reporter?: string };
                const result = testRunner.runTests(testPath, reporter);
                if (!result.success && result.error) {
                    return {
                        content: [{ type: "text", text: `Error: ${result.error}` }],
                        isError: true,
                    };
                }
                const summary = `Passed: ${result.passed ?? 0}, Failed: ${result.failed ?? 0}`;
                return {
                    content: [{ type: "text", text: `${summary}\n\n${result.output}` }],
                    isError: !result.success,
                };
            }

            case "get_vm_info": {
                const info = await vmService.getVmInfo();
                return {
                    content: [{ type: "text", text: JSON.stringify(info, null, 2) }],
                };
            }

            default:
                throw new McpError(
                    ErrorCode.MethodNotFound,
                    `Unknown tool: ${request.params.name}`
                );
        }
    } catch (error: any) {
        return {
            content: [
                {
                    type: "text",
                    text: `Error: ${error.message}`,
                },
            ],
            isError: true,
        };
    }
});

// --- Resources ---

server.setRequestHandler(ListResourcesRequestSchema, async () => {
    return {
        resources: [
            {
                uri: "fap://screenshot",
                name: "Current Screenshot",
                mimeType: "image/png",
                description: "A screenshot of the current application state.",
            },
        ],
    };
});

server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
    if (request.params.uri === "fap://screenshot") {
        try {
            if (!fap.isConnected) {
                await fap.connect();
            }
            const buffer = await fap.captureScreenshot();

            return {
                contents: [
                    {
                        uri: "fap://screenshot",
                        mimeType: "image/png",
                        blob: buffer.toString('base64'),
                    }
                ]
            };
        } catch (error: any) {
            throw new McpError(
                ErrorCode.InternalError,
                `Failed to capture screenshot: ${error.message}`
            );
        }
    }

    throw new McpError(
        ErrorCode.InvalidRequest,
        `Unknown resource: ${request.params.uri}`
    );
});

// --- Start Server ---

async function main() {
    const transport = new StdioServerTransport();
    await server.connect(transport);
    console.error("FAP MCP Server running on stdio");

    // Try to connect to FAP Agent on startup (optional, but good for fast feedback)
    try {
        await fap.connect();
        console.error("Connected to FAP Agent");
    } catch (e) {
        console.error("Could not connect to FAP Agent immediately (will retry on request):", e);
    }
}

main().catch((error) => {
    console.error("Server error:", error);
    process.exit(1);
});
