import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function main() {
    console.log("Starting Text Control Verification...");

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

    // Helper to sleep
    const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

    // 1. Navigate to Form
    console.log("Navigating to Form Screen...");
    await client.callTool({ name: "tap", arguments: { selector: 'key="form_button"' } });
    await sleep(1000);

    // 2. Set Text
    console.log("Setting text to 'Hello World'...");
    const textFieldSelector = 'type="TextField"';
    await client.callTool({ name: "set_text", arguments: { selector: textFieldSelector, text: "Hello World" } });
    await sleep(500);

    // 3. Set Selection
    console.log("Selecting 'World' (6-11)...");
    await client.callTool({ name: "set_selection", arguments: { selector: textFieldSelector, base: 6, extent: 11 } });
    await sleep(500);

    // 4. Verify via List Elements (Optional, check value)
    console.log("Verifying value...");
    const treeResult = await client.callTool({ name: "list_elements", arguments: {} });
    const treeContent = (treeResult as any).content[0].text;
    if (treeContent.includes("Hello World")) {
        console.log("SUCCESS: 'Hello World' found in tree.");
    } else {
        console.error("FAILURE: 'Hello World' not found in tree.");
        console.log("Tree Content Snippet:", treeContent.substring(0, 500) + "...");

        console.log("Fetching Logs to debug...");
        const logsResult = await client.callTool({ name: "get_logs", arguments: {} });
        const logs = JSON.parse((logsResult as any).content[0].text);
        console.log("Agent Logs:", logs.slice(-5)); // Last 5 logs

        process.exit(1);
    }

    // 5. Navigate Back
    console.log("Navigating back...");
    await client.callTool({ name: "tap", arguments: { selector: 'key="back_home_button"' } });

    console.log("Verification Successful!");
    process.exit(0);
}

main().catch((error) => {
    console.error("Verification failed:", error);
    process.exit(1);
});
