import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function main() {
    console.log("Starting Visual Grounding Verification...");

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
    const tools = await client.listTools();
    const toolNames = tools.tools.map(t => t.name);
    if (!toolNames.includes("tap_at")) throw new Error("Missing tool: tap_at");

    // 2. Test tap_at
    console.log("\n--- Testing tap_at ---");

    // We'll tap at a safe location (e.g., center of screen)
    // In a real scenario, we'd get these coords from a VLM.
    // For now, we just verify the RPC call succeeds.
    const x = 200;
    const y = 300;

    console.log(`Tapping at (${x}, ${y})...`);
    const result = await client.callTool({
        name: "tap_at",
        arguments: { x, y }
    });

    console.log("Result:", JSON.stringify(result, null, 2));

    const content = (result as any).content[0].text;
    if (!content.includes("Tapped at")) throw new Error("Unexpected response");

    console.log("\nVerification Successful!");
    process.exit(0);
}

main().catch((error) => {
    console.error("Verification failed:", error);
    process.exit(1);
});
