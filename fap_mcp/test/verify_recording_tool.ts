import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function main() {
    console.log("Starting MCP Recording Verification...");

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

    if (!toolNames.includes("start_recording")) throw new Error("Missing tool: start_recording");
    if (!toolNames.includes("stop_recording")) throw new Error("Missing tool: stop_recording");

    // 2. Test Recording
    console.log("\n--- Testing Recording ---");
    console.log("Starting Recording...");
    await client.callTool({ name: "start_recording", arguments: {} });

    console.log("Recording started. Waiting 2 seconds...");
    await new Promise(resolve => setTimeout(resolve, 2000));

    console.log("Stopping Recording...");
    await client.callTool({ name: "stop_recording", arguments: {} });

    console.log("\nVerification Successful!");
    process.exit(0);
}

main().catch((error) => {
    console.error("Verification failed:", error);
    process.exit(1);
});
