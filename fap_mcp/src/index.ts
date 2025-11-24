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
import { z } from "zod";
import { FapClient } from "fap-client";

// Initialize FAP Client
const fap = new FapClient({
    url: 'ws://127.0.0.1:9001',
    secretToken: process.env.FAP_SECRET_TOKEN // Optional token
});

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
                        target_selector: { type: "string", description: "The element to drag to (optional)." },
                        dx: { type: "number", description: "X offset to drag (optional, used if target_selector not provided)." },
                        dy: { type: "number", description: "Y offset to drag (optional, used if target_selector not provided)." },
                        duration_ms: { type: "number", description: "Duration of drag in ms (default 300)." },
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
                        duration_ms: { type: "number", description: "Duration in ms (default 800)." },
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
                const { selector, dx, dy } = request.params.arguments as { selector: string; dx: number; dy: number };
                const result = await fap.scroll(selector, dx, dy);
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
                    target_selector?: string;
                    dx?: number;
                    dy?: number;
                    duration_ms?: number
                };

                let target: string | { x: number; y: number };
                if (args.target_selector) {
                    target = args.target_selector;
                } else if (args.dx !== undefined && args.dy !== undefined) {
                    target = { x: args.dx, y: args.dy };
                } else {
                    throw new McpError(ErrorCode.InvalidParams, "Either target_selector or dx/dy must be provided for drag");
                }

                const result = await fap.drag(args.selector, target, args.duration_ms);
                return {
                    content: [{ type: "text", text: `Dragged: ${JSON.stringify(result)}` }],
                };
            }

            case "long_press": {
                const { selector, duration_ms } = request.params.arguments as { selector: string; duration_ms?: number };
                const result = await fap.longPress(selector, duration_ms);
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
