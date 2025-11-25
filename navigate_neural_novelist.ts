import { WebSocket } from "ws";
import { unzipSync } from "zlib";
import * as fs from 'fs';

const FAP_URL = `ws://127.0.0.1:9001`;
const SECRET_Token = 'dev-test-token';

function callRpc(ws: WebSocket, method: string, params?: any): Promise<any> {
    return new Promise((resolve, reject) => {
        const id = Date.now();
        const payload: any = { jsonrpc: '2.0', method, id };
        if (params) payload.params = params;
        const request = JSON.stringify(payload);

        const listener = (data: any) => {
            const response = JSON.parse(data.toString());
            if (response.id === id) {
                ws.removeListener('message', listener);
                if (response.error) reject(response.error);
                else resolve(response.result);
            }
        };
        ws.on('message', listener);
        ws.send(request);
    });
}

async function main() {
    const ws = new WebSocket(FAP_URL, { headers: { 'Authorization': `Bearer ${SECRET_Token}` } });
    await new Promise<void>((resolve) => ws.on('open', resolve));
    console.log("Connected.");

    // Step 1: Fetch current tree to find coordinates
    console.log("Fetching current tree...");
    let target: any;
    for (let i = 0; i < 10; i++) {
        let initialTree = await callRpc(ws, 'getTree');
        if (initialTree.compressed) {
            initialTree = JSON.parse(unzipSync(Buffer.from(initialTree.data, 'base64')).toString());
        }
        const initialElements = Array.isArray(initialTree) ? initialTree : initialTree.elements;
        target = initialElements.find((e: any) => e.label && e.label.includes('Quantum Heist'));

        if (target) break;
        console.log("Waiting for 'Quantum Heist' to appear...");
        await new Promise(r => setTimeout(r, 1000));
    }

    if (!target) {
        console.error("Could not find 'Quantum Heist' in current tree after 10s");
        process.exit(1);
    }

    const x = target.rect.x + target.rect.w / 2;
    const y = target.rect.y + target.rect.h / 2;

    console.log(`Tapping 'Quantum Heist' at (${x}, ${y})...`);
    try {
        await callRpc(ws, 'tapAt', { x, y });
        console.log("Tapped.");
    } catch (e) {
        console.error("Failed to tap:", e);
        process.exit(1);
    }

    // Step 2: Wait for navigation
    console.log("Waiting 3s for navigation...");
    await new Promise(r => setTimeout(r, 3000));

    // Fetch Logs
    console.log("Fetching logs...");
    const logs = await callRpc(ws, 'getLogs');
    console.log("--- AGENT LOGS ---");
    logs.forEach((log: string) => console.log(log));
    console.log("------------------");

    // Step 3: Dump new state
    console.log("Fetching new tree...");
    let tree = await callRpc(ws, 'getTree');
    if (tree.compressed) {
        tree = JSON.parse(unzipSync(Buffer.from(tree.data, 'base64')).toString());
    }

    const elements = Array.isArray(tree) ? tree : tree.elements;
    const simplified = elements.map((e: any) => ({
        id: e.id,
        type: e.type,
        label: e.label,
        actions: e.actions,
        rect: e.rect
    }));

    fs.writeFileSync('neural_novelist_tree_step2.json', JSON.stringify(simplified, null, 2));
    console.log(`Dumped ${elements.length} elements to neural_novelist_tree_step2.json`);

    ws.close();
    process.exit(0);
}

main().catch(console.error);
