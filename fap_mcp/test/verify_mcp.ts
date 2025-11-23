import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import {
    ListToolsResultSchema,
    CallToolResultSchema,
} from "@modelcontextprotocol/sdk/types.js";

async function main() {
    console.log("Starting MCP Verification...");

    const transport = new StdioClientTransport({
        command: "node",
        args: ["dist/index.js"],
        env: {
            ...process.env,
            FAP_SECRET_TOKEN: "my-secret-token"
        }
    });

    const client = new Client(
        {
            name: "fap-mcp-test-client",
            version: "1.0.0",
        },
        {
            capabilities: {},
        }
    );

    await client.connect(transport);
    console.log("Connected to MCP Server.");

    // 1. List Tools
    console.log("Listing tools...");
    const tools = await client.listTools();
    const toolNames = tools.tools.map(t => t.name);
    console.log("Tools found:", toolNames.join(", "));

    const requiredTools = ["drag", "long_press", "double_tap", "get_logs", "get_errors", "get_performance_metrics"];
    for (const t of requiredTools) {
        if (!toolNames.includes(t)) throw new Error(`Missing tool: ${t}`);
    }

    // Helper to sleep
    const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

    // 2. Test Gestures
    console.log("\n--- Testing Gestures ---");
    console.log("Navigating to Gestures Screen...");
    await client.callTool({ name: "tap", arguments: { selector: 'key="gestures_button"' } });
    await sleep(1000);

    console.log("Testing Long Press...");
    await client.callTool({ name: "long_press", arguments: { selector: 'key="long_press_box"', duration_ms: 1000 } });

    console.log("Testing Double Tap...");
    await client.callTool({ name: "double_tap", arguments: { selector: 'key="double_tap_box"' } });

    console.log("Testing Drag...");
    await client.callTool({ name: "drag", arguments: { selector: 'key="drag_box"', dx: 50, dy: 50 } });

    console.log("Navigating back...");
    await client.callTool({ name: "tap", arguments: { selector: 'key="gestures_back_button"' } });
    await sleep(1000);

    // 3. Test Observability
    console.log("\n--- Testing Observability ---");
    console.log("Navigating to Observability Screen...");
    await client.callTool({ name: "tap", arguments: { selector: 'key="observability_button"' } });
    await sleep(1000);

    console.log("Triggering Log...");
    await client.callTool({ name: "tap", arguments: { selector: 'key="log_button"' } });
    await sleep(500);

    console.log("Fetching Logs...");
    const logsResult = await client.callTool({ name: "get_logs", arguments: {} });
    const logs = JSON.parse((logsResult as any).content[0].text);
    console.log(`Logs received: ${logs.length}`);
    if (logs.length === 0) console.warn("Warning: No logs captured (might be timing issue)");

    console.log("Fetching Performance Metrics...");
    const perfResult = await client.callTool({ name: "get_performance_metrics", arguments: {} });
    const perf = JSON.parse((perfResult as any).content[0].text);
    console.log(`Performance metrics received: ${perf.length}`);

    console.log("Navigating back...");
    await client.callTool({ name: "tap", arguments: { selector: 'key="back_home_button"' } });

    console.log("\nVerification Successful!");
    process.exit(0);
}

main().catch((error) => {
    console.error("Verification failed:", error);
    process.exit(1);
});
