# FAP Client SDK

A Node.js/TypeScript client for the Flutter Agent Protocol (FAP).

## Installation

```bash
npm install fap-client
```

## Usage

```typescript
import { FapClient } from 'fap-client';

async function main() {
    const client = new FapClient({
        url: 'ws://127.0.0.1:9001',
        secretToken: 'your-secret-token'
    });

    await client.connect();

    // Get the UI tree
    const tree = await client.getTree();
    console.log(tree);

    // Tap an element
    await client.tap('key="submit_btn"');

    // Enter text
    await client.enterText('Hello World', 'key="email_field"');

    // Visual Grounding (Tap at coordinates)
    await client.tapAt(100, 200);

    // Recording
    await client.startRecording();
    // ... perform actions ...
    await client.stopRecording();

    await client.disconnect();
}

main();
```

## Features

*   **Semantic Selection**: Find elements by `key`, `text`, `type`, `tooltip`, and more.
*   **Robust Actions**: `tap`, `enterText`, `scroll`, `drag`, `longPress`, `doubleTap`.
*   **Visual Grounding**: `tapAt(x, y)` for clicking elements by coordinate.
*   **Recording**: Record user sessions to generate scripts.
*   **Observability**: Access logs, errors, and performance metrics.
*   **Performance**: Automatic Gzip compression and incremental tree updates.
