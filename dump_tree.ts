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
    console.log("Connected. Waiting 2s for UI to settle...");
    await new Promise(r => setTimeout(r, 2000));
    console.log("Fetching tree...");

    let tree = await callRpc(ws, 'getTree');
    if (tree.compressed) {
        tree = JSON.parse(unzipSync(Buffer.from(tree.data, 'base64')).toString());
    }

    const elements = Array.isArray(tree) ? tree : tree.elements;

    // Filter for interesting elements to reduce noise
    const simplified = elements.map((e: any) => ({
        id: e.id,
        type: e.type,
        label: e.label,
        value: e.value,
        hint: e.hint,
        actions: e.actions,
        rect: e.rect
    }));

    fs.writeFileSync('neural_novelist_tree.json', JSON.stringify(simplified, null, 2));
    console.log(`Dumped ${elements.length} elements to neural_novelist_tree.json`);

    if (elements.length === 0) {
        console.log("Tree is empty. Fetching logs...");
        const logs = await callRpc(ws, 'getLogs');
        console.log("--- AGENT LOGS ---");
        logs.forEach((log: string) => console.log(log));
        console.log("------------------");
    }

    ws.close();
    process.exit(0);
}

main().catch(console.error);
