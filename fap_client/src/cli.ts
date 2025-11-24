#!/usr/bin/env node
import { spawn } from 'child_process';
import path from 'path';

const args = process.argv.slice(2);
const command = args[0];

if (command === 'run') {
    const filePattern = args[1];
    if (!filePattern) {
        console.error('Usage: fap run <file>');
        process.exit(1);
    }

    console.log(`Running tests: ${filePattern}`);

    // Simple runner: execute with ts-node
    // We assume ts-node is available or we use the one in devDependencies
    // In a real CLI we might bundle everything.

    const tsNodePath = path.resolve(__dirname, '../node_modules/.bin/ts-node');

    const child = spawn(tsNodePath, [filePattern], {
        stdio: 'inherit',
        env: { ...process.env, FAP_ENABLED: 'true' }
    });

    child.on('exit', (code) => {
        process.exit(code ?? 0);
    });
} else if (command === 'record') {
    const { FapClient } = require('./client');
    const client = new FapClient();

    (async () => {
        try {
            console.log('Connecting to FAP Agent...');
            await client.connect();
            console.log('Connected! Starting recording...');

            console.log('\n--- Generated Script ---\n');
            console.log("import { FapClient } from 'fap-client';");
            console.log("(async () => {");
            console.log("  const client = new FapClient();");
            console.log("  await client.connect();\n");

            client.onEvent((event: any) => {
                if (event.method === 'recording.event') {
                    const { action, selector, text } = event.params;
                    if (action === 'tap') {
                        console.log(`  await client.tap('${selector}');`);
                    } else if (action === 'enterText') {
                        console.log(`  await client.enterText('${text}', '${selector}');`);
                    }
                }
            });

            await client.startRecording();
            console.log('// Recording... Press Ctrl+C to stop.');

            // Keep process alive
            await new Promise(() => { });

        } catch (e) {
            console.error('Error:', e);
            process.exit(1);
        }
    })();

    process.on('SIGINT', async () => {
        console.log('\n// Stopping recording...');
        try {
            await client.stopRecording();
            await client.disconnect();
        } catch (e) {
            // ignore
        }
        console.log("\n  await client.disconnect();");
        console.log("})();");
        process.exit(0);
    });

} else {
    console.log('FAP CLI');
    console.log('Usage: fap run <file>');
    console.log('Usage: fap record');
}
