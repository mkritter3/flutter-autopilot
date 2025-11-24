import { FapClient } from '../src/client';

async function main() {
    const client = new FapClient({ secretToken: 'my-secret-token' });

    try {
        console.log('Connecting...');
        await client.connect();
        console.log('Connected.');

        let eventReceived = false;
        client.onEvent((event) => {
            console.log('Received Event:', event);
            if (event.method === 'recording.event' && event.params.action === 'tap') {
                eventReceived = true;
                console.log('✅ Recording event verified!');
            }
        });

        console.log('Starting recording...');
        await client.startRecording();

        // Perform a tap to trigger an event
        // We'll tap the Details button
        console.log('Performing tap...');
        try {
            await client.tap('key="details_button"');
        } catch (e) {
            console.log('Tap failed (maybe element not found), but that might be expected if app not ready.');
        }

        // Wait for event
        await new Promise(resolve => setTimeout(resolve, 2000));

        console.log('Stopping recording...');
        await client.stopRecording();

        if (eventReceived) {
            console.log('TEST PASSED');
            process.exit(0);
        } else {
            console.error('TEST FAILED: No recording event received');
            process.exit(1);
        }

    } catch (e) {
        console.error('Error:', e);
        process.exit(1);
    } finally {
        await client.disconnect();
    }
}

main();
