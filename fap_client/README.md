# FAP Client

`fap_client` is a Node.js/TypeScript client for the Flutter Agent Protocol (FAP). It allows you to control Flutter applications instrumented with `fap_agent`.

## Installation

```bash
npm install
npm run build
```

## Usage

### CLI

You can use the CLI to run scripts:

```bash
node dist/cli.js run <script_path>
```

### Library

```typescript
import { FapClient } from './client';

async function main() {
  const client = new FapClient('ws://localhost:9001');
  await client.connect();

  // Get UI Tree
  const tree = await client.getTree();
  console.log(tree);

  // Tap an element
  await client.tap('text="Submit"');

  // Enter text
  await client.enterText('Hello', 'label="Email"');

  await client.disconnect();
}

main();
```

## API

### `connect()`
Connects to the FAP Agent.

### `getTree()`
Returns a list of `FapElement` objects representing the current UI.

### `tap(selector: string)`
Taps the element matching the selector.
Selectors:
*   `text="Value"`
*   `label="Label"`
*   `id="fap-1"`

### `enterText(text: string, selector: string)`
Enters text into the element matching the selector.
