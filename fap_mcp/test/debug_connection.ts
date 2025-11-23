import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function main() {
    console.log("Starting Debug Connection...");

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
            name: "fap-mcp-debug-client",
            version: "1.0.0",
        },
        {
            capabilities: {},
        }
    );

    await client.connect(transport);
    console.log("Connected to MCP Server.");

    console.log("Listing Elements...");
    const treeResult = await client.callTool({ name: "list_elements", arguments: {} });
    const treeContent = (treeResult as any).content[0].text;
    console.log("Tree received. Length:", treeContent.length);

    process.exit(0);
}

main().catch((error) => {
    console.error("Debug failed:", error);
    process.exit(1);
});
