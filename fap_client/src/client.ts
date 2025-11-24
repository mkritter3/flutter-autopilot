import WebSocket from 'ws';
import { v4 as uuidv4 } from 'uuid';
import * as zlib from 'zlib';

export interface FapConfig {
    url?: string;
    timeoutMs?: number;
    secretToken?: string;
}

export interface FapElement {
    id: number;
    rect: { x: number; y: number; w: number; h: number };
    label?: string;
    value?: string;
    hint?: string;
    key?: string;
    metadata?: Record<string, string>;
}

export class FapClient {
    private ws: WebSocket | null = null;
    private pendingRequests = new Map<string, { resolve: (val: any) => void; reject: (err: any) => void }>();
    private url: string;
    private config: FapConfig;
    private _elementsCache: Map<string, FapElement> = new Map();

    private eventListeners: ((event: any) => void)[] = [];

    constructor(config: FapConfig = {}) {
        this.config = config;
        this.url = config.url || 'ws://localhost:9001';
    }

    async connect(): Promise<void> {
        return new Promise((resolve, reject) => {
            const options: any = {};
            if (this.config.secretToken) {
                options.headers = {
                    Authorization: `Bearer ${this.config.secretToken}`
                };
            }

            this.ws = new WebSocket(this.url, options);

            this.ws.on('open', () => {
                resolve();
            });

            this.ws.on('error', (err) => {
                reject(err);
            });

            this.ws.on('message', (data) => {
                const msg = JSON.parse(data.toString());

                // Handle Notifications
                if (msg.method && !msg.id) {
                    this.eventListeners.forEach(listener => listener(msg));
                    return;
                }

                // Handle Responses
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

    onEvent(callback: (event: any) => void) {
        this.eventListeners.push(callback);
    }

    async disconnect(): Promise<void> {
        this.ws?.close();
        this.ws = null;
    }

    get isConnected(): boolean {
        return this.ws !== null && this.ws.readyState === WebSocket.OPEN;
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
            }, this.config.timeoutMs || 10000);
        }).then((result: any) => {
            // Handle Compression
            if (result && typeof result === 'object' && result.compressed && result.data) {
                const buffer = Buffer.from(result.data, 'base64');
                const decompressed = zlib.gunzipSync(buffer);
                return JSON.parse(decompressed.toString('utf-8'));
            }
            return result;
        });
    }

    async startRecording(): Promise<void> {
        await this.request('startRecording');
    }

    async stopRecording(): Promise<void> {
        await this.request('stopRecording');
    }

    async getTree(): Promise<FapElement[]> {
        try {
            const diff = await this.request<any>('getTreeDiff');
            this._applyDiff(diff);
            return Array.from(this._elementsCache.values());
        } catch (e) {
            // Fallback to full tree if diff fails (e.g. old agent)
            const elements = await this.request<FapElement[]>('getTree');
            this._elementsCache.clear();
            elements.forEach(e => this._elementsCache.set(e.id.toString(), e));
            return elements;
        }
    }

    private _applyDiff(diff: { added: FapElement[], removed: string[], updated: FapElement[] }) {
        // 1. Removed
        diff.removed.forEach(id => this._elementsCache.delete(id));

        // 2. Added
        diff.added.forEach(e => this._elementsCache.set(e.id.toString(), e));

        // 3. Updated
        diff.updated.forEach(e => this._elementsCache.set(e.id.toString(), e));
    }

    async getRoute(): Promise<string | null> {
        return this.request<string | null>('getRoute');
    }

    async waitFor(selector: string, timeoutMs: number = 5000): Promise<FapElement> {
        const startTime = Date.now();
        while (Date.now() - startTime < timeoutMs) {
            try {
                const elements = await this.request<FapElement[]>('getTree');

                // Simple parser
                let match: FapElement | undefined;
                if (selector.startsWith('key=')) {
                    const key = selector.split('=')[1].replace(/['"]/g, '');
                    match = elements.find(e => e.key === key);
                } else if (selector.startsWith('text=')) {
                    const text = selector.split('=')[1].replace(/['"]/g, '');
                    match = elements.find(e => e.label === text || e.value === text || e.hint === text);
                } else if (selector.startsWith('label=')) {
                    const label = selector.split('=')[1].replace(/['"]/g, '');
                    match = elements.find(e => e.label === label);
                } else if (selector.startsWith('test-id=')) {
                    const testId = selector.split('=')[1].replace(/['"]/g, '');
                    match = elements.find(e => e.metadata && e.metadata['test-id'] === testId);
                }

                if (match) return match;

            } catch (e) {
                // ignore
            }
            await new Promise(resolve => setTimeout(resolve, 500));
        }
        throw new Error(`Timeout waiting for element: ${selector}`);
    }

    async tap(selector: string): Promise<any> {
        return this.request('tap', { selector });
    }

    async tapAt(x: number, y: number): Promise<any> {
        return this.request('tapAt', { x, y });
    }

    async enterText(text: string, selector?: string): Promise<void> {
        await this.request('enterText', { text, selector });
    }

    async setText(selector: string, text: string): Promise<void> {
        await this.request('setText', { selector, text });
    }

    async setSelection(selector: string, base: number, extent: number): Promise<void> {
        await this.request('setSelection', { selector, base, extent });
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

    async getPerformanceMetrics(): Promise<{ build: number; raster: number; total: number }[]> {
        return this.request('getPerformanceMetrics');
    }

    async getLogs(): Promise<string[]> {
        return this.request('getLogs');
    }
}
