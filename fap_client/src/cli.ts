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
} else {
    console.log('FAP CLI');
    console.log('Usage: fap run <file>');
}
