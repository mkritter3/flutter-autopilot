import { WebSocket } from "ws";
import { unzipSync } from "zlib";

// Simple JSON-RPC Client for FAP Direct Connection (bypassing MCP for direct agent test)
// Or we can use the MCP if it's running.
// Let's try direct WebSocket connection to FAP Agent first as it's the "raw" control.

const FAP_PORT = 9001;
const FAP_URL = `ws://127.0.0.1:${FAP_PORT}`;
const SECRET_Token = 'dev-test-token';

function connectToFap() {
    return new Promise((resolve, reject) => {
        const ws = new WebSocket(FAP_URL, {
            headers: {
                'Authorization': `Bearer ${SECRET_Token}`
            }
        });

        ws.on('open', () => {
            console.log('Connected to FAP Agent!');
            resolve(ws);
        });

        ws.on('error', (err) => {
            console.error('Connection failed:', err.message);
            reject(err);
        });
    });
}

function callRpc(ws: WebSocket, method: string, params?: any): Promise<any> {
    return new Promise((resolve, reject) => {
        const id = Date.now();
        const payload: any = { jsonrpc: '2.0', method, id };
        if (params) {
            payload.params = params;
        }
        const request = JSON.stringify(payload);

        const listener = (data: any) => {
            const response = JSON.parse(data.toString());
            if (response.id === id) {
                ws.removeListener('message', listener);
                if (response.error) {
                    reject(response.error);
                } else {
                    resolve(response.result);
                }
            }
        };

        ws.on('message', listener);
        ws.send(request);
    });
}

async function main() {
    console.log("Attempting to control North Star...");

    try {
        const ws = await connectToFap() as WebSocket;

        // 1. Get Semantics Tree
        console.log("Fetching semantics tree...");
        let tree = await callRpc(ws, 'getTree');

        if (tree.compressed) {
            console.log("Tree is compressed. Decompressing...");
            const buffer = Buffer.from(tree.data, 'base64');
            const decompressed = unzipSync(buffer);
            tree = JSON.parse(decompressed.toString());
        }

        // Tree is a list of elements
        const elements = Array.isArray(tree) ? tree : tree.elements;

        console.log(`Received semantics tree with ${elements.length} elements.`);

        if (elements.length === 0) {
            console.error("FAIL: Semantics tree is empty!");

            // Fetch logs to debug
            console.log("Fetching logs...");
            const logs = await callRpc(ws, 'getLogs');
            console.log("--- AGENT LOGS ---");
            logs.forEach((log: string) => console.log(log));
            console.log("------------------");

            process.exit(1);
        }

        // 2. Find a button (e.g., "Login" or similar)
        const buttons = elements.filter((e: any) => e.type.includes('Button') || (e.label && e.label.toLowerCase().includes('login')));
        console.log(`Found ${buttons.length} potential interactable elements.`);

        // 3. Get Performance Metrics
        console.log("Fetching performance metrics...");
        const metrics = await callRpc(ws, 'getPerformanceMetrics');
        console.log(`Received ${metrics.length} frame timing records.`);

        ws.close();
        console.log("Verification SUCCESS: App is controllable.");
        process.exit(0);

    } catch (error) {
        console.error("Verification FAILED:", error);
        process.exit(1);
    }
}

main();
