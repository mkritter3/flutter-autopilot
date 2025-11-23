import { FapClient } from './client';

function sleep(ms: number) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function main() {
    const client = new FapClient({ url: 'ws://localhost:9001' });

    console.log('Connecting to FAP Agent...');
    await client.connect();
    console.log('Connected!');

    const maxSteps = 10;

    for (let i = 0; i < maxSteps; i++) {
        console.log(`\n--- Step ${i + 1}/${maxSteps} ---`);

        const tree = await client.getTree();
        console.log(`Found ${tree.length} elements.`);

        // Filter for interactive elements (have tap action)
        const interactive = tree.filter(e => e.actions.includes('tap'));

        if (interactive.length === 0) {
            console.log('No interactive elements found. Stopping.');
            break;
        }

        // Pick a random element
        const element = interactive[Math.floor(Math.random() * interactive.length)];
        console.log(`Decided to tap: ${element.label || element.id} (${element.id})`);

        try {
            await client.tap(`id="${element.id}"`);
            console.log('Tap successful.');
        } catch (e) {
            console.error('Tap failed:', e);
        }

        await sleep(2000);
    }

    await client.disconnect();
    console.log('Exploration finished.');
}

main().catch(console.error);
