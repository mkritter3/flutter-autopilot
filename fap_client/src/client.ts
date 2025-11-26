import WebSocket from 'ws';
import { v4 as uuidv4 } from 'uuid';
import * as zlib from 'zlib';
import fs from 'fs';

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

export interface FapWidgetRef {
    id: string;
    type: string;
    key?: string;
    bounds: { x: number; y: number; w: number; h: number };
    properties: Record<string, any>;
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
                const parsed = JSON.parse(decompressed.toString('utf-8'));
                return parsed;
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
        const response: any = await this.request('getTree');

        let elements: FapElement[] = [];
        if (Array.isArray(response)) {
            elements = response;
        } else if (response && response.elements && Array.isArray(response.elements)) {
            elements = response.elements;
        } else {
            console.error('Unexpected getTree response format:', response);
            return [];
        }

        this._elementsCache.clear();
        elements.forEach(e => this._elementsCache.set(e.id.toString(), e));
        return elements;
    }

    // Widget Inspector Methods (NEW)
    async getWidgetTree(): Promise<FapWidgetRef[]> {
        const response: any = await this.request('getWidgetTree');

        if (response && response.widgets && Array.isArray(response.widgets)) {
            return response.widgets;
        }
        return [];
    }

    async findWidget(filter: { type?: string; key?: string; x?: number; y?: number }): Promise<FapWidgetRef[]> {
        const response: any = await this.request('findWidget', filter);
        return Array.isArray(response) ? response : [];
    }

    async findWidgetByType(typeName: string): Promise<FapWidgetRef[]> {
        return this.findWidget({ type: typeName });
    }

    async findWidgetByKey(keyPattern: string): Promise<FapWidgetRef[]> {
        return this.findWidget({ key: keyPattern });
    }

    async findWidgetAt(x: number, y: number): Promise<FapWidgetRef | null> {
        const widgets = await this.findWidget({ x, y });
        return widgets.length > 0 ? widgets[0] : null;
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

    async enterText(text: string, selector?: string, options?: {
        tapFirst?: boolean;
        fallbackToFocused?: boolean;
    }): Promise<any> {
        return this.request('enterText', {
            text,
            selector,
            tap_first: options?.tapFirst,
            fallback_to_focused: options?.fallbackToFocused,
        });
    }

    async setText(selector: string, text: string, options?: {
        tapFirst?: boolean;
        fallbackToFocused?: boolean;
    }): Promise<any> {
        return this.request('setText', {
            selector,
            text,
            tap_first: options?.tapFirst,
            fallback_to_focused: options?.fallbackToFocused,
        });
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

    async smartEnterText(text: string, options: { widgetType?: string; x?: number; y?: number } = {}): Promise<any> {
        const params: any = { text };
        if (options.widgetType) params.widgetType = options.widgetType;
        if (options.x !== undefined && options.y !== undefined) {
            params.x = options.x;
            params.y = options.y;
        }
        return this.request('smartEnterText', params);
    }

    // Text Input Simulation Methods

    async getTextInputStatus(): Promise<{ hasActiveInput: boolean; clientId: number | null; currentText: string }> {
        return this.request('getTextInputStatus');
    }

    async typeText(text: string): Promise<any> {
        return this.request('typeText', { text });
    }

    async setTextDirect(text: string): Promise<any> {
        return this.request('setTextDirect', { text });
    }

    async clearTextInput(): Promise<any> {
        return this.request('clearTextInput');
    }

    async pressKey(key: 'enter' | 'backspace'): Promise<any> {
        return this.request('pressKey', { key });
    }

    // ==========================================
    // Flutter Controller - Direct Widget Access
    // ==========================================

    async findElements(type: string, exact: boolean = false): Promise<any> {
        return this.request('findElements', { type, exact });
    }

    async findElementsAtPosition(x: number, y: number): Promise<any> {
        return this.request('findElementsAtPosition', { x, y });
    }

    async findTextControllers(): Promise<any> {
        return this.request('findTextControllers');
    }

    async setTextByType(widgetType: string, text: string, index: number = 0): Promise<any> {
        return this.request('setTextByType', { widgetType, text, index });
    }

    async executeAction(
        widgetType: string,
        action: string,
        params: Record<string, any> = {},
        index: number = 0
    ): Promise<any> {
        return this.request('executeAction', { widgetType, action, index, ...params });
    }

    async getElementTree(maxDepth: number = 5): Promise<any> {
        return this.request('getElementTree', { maxDepth });
    }

    async findStates(stateType: string): Promise<any> {
        return this.request('findStates', { stateType });
    }

    async findScrollControllers(): Promise<any> {
        return this.request('findScrollControllers');
    }

    async getPerformanceMetrics(): Promise<{ build: number; raster: number; total: number }[]> {
        return this.request('getPerformanceMetrics');
    }

    async getLogs(): Promise<string[]> {
        return this.request('getLogs');
    }

    async getPlaceholders(): Promise<{ count: number; placeholders: FapElement[] }> {
        return this.request('getPlaceholders');
    }

    // ==========================================
    // Generic RPC Call (for new/custom methods)
    // ==========================================

    /**
     * Make a generic RPC call to the FAP agent.
     * Use this for new methods not yet exposed via typed methods.
     */
    async call(method: string, params: Record<string, any> = {}): Promise<any> {
        return this.request(method, params);
    }

    // ==========================================
    // Rich Text Editor Support
    // ==========================================

    async discoverRichTextEditors(): Promise<{ count: number; editors: any[] }> {
        return this.request('discoverRichTextEditors');
    }

    async enterRichText(text: string, useDelta: boolean = true): Promise<any> {
        return this.request('enterRichText', { text, useDelta });
    }

    async richTextInsertText(editorId: number, text: string): Promise<any> {
        return this.request('richText.insertText', { editorId, text });
    }

    async richTextGetContent(editorId: number): Promise<any> {
        return this.request('richText.getContent', { editorId });
    }

    async richTextGetSelection(editorId: number): Promise<any> {
        return this.request('richText.getSelection', { editorId });
    }

    async richTextApplyFormat(editorId: number, format: string): Promise<any> {
        return this.request('richText.applyFormat', { editorId, format });
    }

    // ==========================================
    // Menu / Overlay / Drawer Discovery
    // ==========================================

    async getOverlayState(): Promise<any> {
        return this.request('getOverlayState');
    }

    async waitForOverlay(timeoutMs: number = 5000, pollIntervalMs: number = 50): Promise<any> {
        return this.request('waitForOverlay', { timeoutMs, pollIntervalMs });
    }

    async getOverlayElements(): Promise<{ count: number; elements: any[] }> {
        return this.request('getOverlayElements');
    }

    async getDrawerState(): Promise<{
        hasScaffold: boolean;
        isDrawerOpen: boolean;
        isEndDrawerOpen: boolean;
        anyDrawerOpen: boolean;
    }> {
        return this.request('getDrawerState');
    }

    async discoverMenuTriggers(): Promise<{ count: number; triggers: any[] }> {
        return this.request('discoverMenuTriggers');
    }

    async openDrawer(endDrawer: boolean = false): Promise<any> {
        return this.request('openDrawer', { endDrawer });
    }

    async closeDrawer(): Promise<any> {
        return this.request('closeDrawer');
    }

    async getElementsByCategory(category: string): Promise<{ category: string; count: number; elements: any[] }> {
        return this.request('getElementsByCategory', { category });
    }

    async findRichTextEditors(): Promise<{ editors: any[] }> {
        return this.request('findRichTextEditors');
    }
}
