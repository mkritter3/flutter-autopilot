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
                description: "Get a hierarchical list of all UI elements currently visible on the screen. Returns the Flutter semantics tree with element IDs, types, text, labels, keys, and other attributes. Use this FIRST to discover available selectors before attempting to tap or enter text. Note: Custom painters, WebViews, and some platform views may not appear in this tree - use tap_at with visual grounding for those.",
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "tap",
                description: "Tap on a UI element matching the given selector. Use this for buttons, links, list items, etc. If an element is not exposed in the semantics tree, use tap_at with coordinates instead.",
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: {
                            type: "string",
                            description: "The selector to identify the element. Examples: 'text=\"Save\"' (button text), 'key=\"submit_btn\"' (Flutter Key - best), 'type=\"ElevatedButton\"' (widget type), 'label=\"Submit form\"' (accessibility label). Use list_elements first to see available selectors.",
                        },
                    },
                    required: ["selector"],
                },
            },
            {
                name: "tap_at",
                description: "Tap at specific screen coordinates (x, y). Use this for Visual Grounding workflows when: 1) An element is visible in the screenshot but not in the semantics tree (e.g., WebView content, custom painters, platform views), 2) You're using a VLM to identify element positions. Always analyze the screenshot first to determine coordinates.",
                inputSchema: {
                    type: "object",
                    properties: {
                        x: { type: "number", description: "X coordinate in pixels from the left edge of the screen" },
                        y: { type: "number", description: "Y coordinate in pixels from the top edge of the screen" },
                    },
                    required: ["x", "y"],
                },
            },
            {
                name: "enter_text",
                description: "Enter text into a text field matching the given selector. Use this to type into input fields, textareas, etc. The field must have focus (tap it first if needed).",
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: {
                            type: "string",
                            description: "The selector to identify the text field. Examples: 'key=\"email_field\"' (best - uses Flutter Key), 'text=\"Email\"' (label text), 'type=\"TextField\"' (widget type). Prefer key selectors when available.",
                        },
                        text: {
                            type: "string",
                            description: "The text to type into the field (e.g., 'user@example.com', 'password123').",
                        },
                    },
                    required: ["selector", "text"],
                },
            },
            {
                name: "scroll",
                description: "Scroll a UI element.",
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: {
                            type: "string",
                            description: "The selector to identify the scrollable element.",
                        },
                        dx: {
                            type: "number",
                            description: "Horizontal scroll amount.",
                        },
                        dy: {
                            type: "number",
                            description: "Vertical scroll amount.",
                        },
                        durationMs: {
                            type: "number",
                            description: "Duration of scroll animation in milliseconds (default 300).",
                        },
                    },
                    required: ["selector", "dx", "dy"],
                },
            },
            {
                name: "get_route",
                description: "Get the name of the current route.",
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "drag",
                description: "Drag an element to another element or by an offset.",
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: { type: "string", description: "The element to drag." },
                        targetSelector: { type: "string", description: "The element to drag to (optional)." },
                        dx: { type: "number", description: "X offset to drag (optional, used if targetSelector not provided)." },
                        dy: { type: "number", description: "Y offset to drag (optional, used if targetSelector not provided)." },
                        durationMs: { type: "number", description: "Duration of drag in ms (default 300)." },
                    },
                    required: ["selector"],
                },
            },
            {
                name: "long_press",
                description: "Long press on an element.",
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: { type: "string" },
                        durationMs: { type: "number", description: "Duration in ms (default 800)." },
                    },
                    required: ["selector"],
                },
            },
            {
                name: "double_tap",
                description: "Double tap on an element.",
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: { type: "string" },
                    },
                    required: ["selector"],
                },
            },
            {
                name: "get_logs",
                description: "Get captured console logs from the app.",
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "get_errors",
                description: "Get captured errors (framework and async) from the app.",
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "get_performance_metrics",
                description: "Get frame timing metrics (build/raster times).",
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "set_text",
                description: "Set the text of a text field directly (replaces existing text).",
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: { type: "string" },
                        text: { type: "string" },
                    },
                    required: ["selector", "text"],
                },
            },
            {
                name: "set_selection",
                description: "Set the selection range (cursor position) of a text field.",
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: { type: "string" },
                        base: { type: "number", description: "Start offset of selection." },
                        extent: { type: "number", description: "End offset of selection." },
                    },
                    required: ["selector", "base", "extent"],
                },
            },

            {
                name: "start_recording",
                description: "Start recording user interactions (taps, text entry) to generate a FAP script.",
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "stop_recording",
                description: "Stop the recording session.",
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
