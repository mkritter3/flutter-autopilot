import { FapClient } from './index';

async function main() {
    console.log('Starting FAP Test...');
    const client = new FapClient();

    try {
        console.log('Connecting...');
        await client.connect();
        console.log('Connected!');

        const tree = await client.getTree();
        console.log('Tree root found:', tree.length > 0);

        await client.disconnect();
        console.log('Test Passed!');
    } catch (e) {
        console.error('Test Failed:', e);
        process.exit(1);
    }
}

main();
