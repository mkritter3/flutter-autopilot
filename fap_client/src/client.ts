import WebSocket from 'ws';
import { v4 as uuidv4 } from 'uuid';

export interface FapConfig {
    url?: string;
    timeoutMs?: number;
}

export interface FapElement {
    id: string;
    type?: string;
    key?: string;
    label?: string;
    value?: string;
    hint?: string;
    rect: { x: number; y: number; w: number; h: number };
    actions: string[];
}

export class FapClient {
    private ws: WebSocket | null = null;
    private pendingRequests = new Map<string, { resolve: (val: any) => void; reject: (err: any) => void }>();
    private url: string;

    constructor(config: FapConfig = {}) {
        this.url = config.url || 'ws://localhost:9001';
    }

    async connect(): Promise<void> {
        return new Promise((resolve, reject) => {
            this.ws = new WebSocket(this.url);

            this.ws.on('open', () => {
                resolve();
            });

            this.ws.on('error', (err) => {
                reject(err);
            });

            this.ws.on('message', (data) => {
                const msg = JSON.parse(data.toString());
                if (msg.id && this.pendingRequests.has(msg.id)) {
                    const { resolve, reject } = this.pendingRequests.get(msg.id)!;
                    this.pendingRequests.delete(msg.id);
                    if (msg.error) {
                        reject(msg.error);
                    } else {
                        resolve(msg.result);
                    }
                }
            });
        });
    }

    async disconnect(): Promise<void> {
        this.ws?.close();
        this.ws = null;
    }

    private async request<T>(method: string, params: any = {}): Promise<T> {
        if (!this.ws) throw new Error('Not connected');

        const id = uuidv4();
        const payload: any = {
            jsonrpc: '2.0',
            id,
            method,
        };

        if (params && Object.keys(params).length > 0) {
            payload.params = params;
        }

        return new Promise((resolve, reject) => {
            this.pendingRequests.set(id, { resolve, reject });
            this.ws!.send(JSON.stringify(payload));

            // Timeout
            setTimeout(() => {
                if (this.pendingRequests.has(id)) {
                    this.pendingRequests.delete(id);
                    reject(new Error(`Request ${method} timed out`));
                }
            }, 10000);
        });
    }

    async getTree(): Promise<FapElement[]> {
        return this.request<FapElement[]>('getTree');
    }

    async tap(selector: string): Promise<any> {
        return this.request('tap', { selector });
    }

    async enterText(text: string, selector?: string): Promise<void> {
        await this.request('enterText', { text, selector });
    }

    async captureScreenshot(): Promise<Buffer> {
        const res = await this.request<{ base64: string }>('captureScreenshot');
        return Buffer.from(res.base64, 'base64');
    }

    async getErrors(): Promise<any[]> {
        return this.request<any[]>('getErrors');
    }

    async scroll(selector: string, dx: number, dy: number, durationMs: number = 300): Promise<any> {
        return this.request('scroll', { selector, dx, dy, durationMs });
    }

    async drag(selector: string, targetSelectorOrOffset: string | { x: number; y: number }, durationMs: number = 300): Promise<any> {
        const params: any = { selector, durationMs };
        if (typeof targetSelectorOrOffset === 'string') {
            params.targetSelector = targetSelectorOrOffset;
        } else {
            params.dx = targetSelectorOrOffset.x;
            params.dy = targetSelectorOrOffset.y;
        }
        return this.request('drag', params);
    }

    async longPress(selector: string, durationMs: number = 800): Promise<any> {
        return this.request('longPress', { selector, durationMs });
    }

    async doubleTap(selector: string): Promise<any> {
        return this.request('doubleTap', { selector });
    }
}
