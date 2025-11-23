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
                description: "Get a hierarchical list of all UI elements on the screen, including their IDs, types, and attributes.",
                inputSchema: {
                    type: "object",
                    properties: {},
                },
            },
            {
                name: "tap",
                description: "Tap on a UI element matching the given selector.",
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: {
                            type: "string",
                            description: "The selector to identify the element (e.g., 'text=\"Save\"', 'key=\"submit_btn\"').",
                        },
                    },
                    required: ["selector"],
                },
            },
            {
                name: "enter_text",
                description: "Enter text into a text field matching the given selector.",
                inputSchema: {
                    type: "object",
                    properties: {
                        selector: {
                            type: "string",
                            description: "The selector to identify the text field.",
                        },
                        text: {
                            type: "string",
                            description: "The text to enter.",
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

            case "enter_text": {
                const { selector, text } = request.params.arguments as { selector: string; text: string };
                const result = await fap.enterText(selector, text);
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
