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
    console.log("Tools found:", tools.tools.map(t => t.name).join(", "));

    if (!tools.tools.find(t => t.name === "list_elements")) {
        throw new Error("Missing list_elements tool");
    }

    // 2. Get Route
    console.log("Calling get_route...");
    const routeResult = await client.callTool({
        name: "get_route",
        arguments: {}
    });
    console.log("Get Route Result:", JSON.stringify(routeResult));

    // 3. List Elements
    console.log("Calling list_elements...");
    const treeResult = await client.callTool({
        name: "list_elements",
        arguments: {}
    });
    // Don't print the whole tree, just length check or something
    const treeContent = (treeResult as any).content[0].text;
    const tree = JSON.parse(treeContent);
    console.log(`Tree received. Root element: ${tree[0]?.type}`);

    console.log("Verification Successful!");
    process.exit(0);
}

main().catch((error) => {
    console.error("Verification failed:", error);
    process.exit(1);
});
