import { FapClient } from './client';
import * as fs from 'fs';
import * as path from 'path';

async function sleep(ms: number) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function main() {
    console.log('Starting FAP E2E Verification...');
    const client = new FapClient({ url: 'ws://localhost:9001' });

    try {
        // 1. Connect
        console.log('Connecting to FAP Agent...');
        await client.connect();
        console.log('Connected!');

        // 2. List Elements (Home Screen)
        console.log('Fetching UI Tree...');
        let tree = await client.getTree();
        let retries = 0;
        while (tree.length === 0 && retries < 10) {
            console.log('Tree empty, retrying...');
            await sleep(500);
            tree = await client.getTree();
            retries++;
        }
        console.log(`Found ${tree.length} elements.`);
        // Debug: print all elements with rects
        console.log('UI Tree:', tree.map(e => `[${e.id}] "${e.label || e.value || e.hint}" @ (${e.rect.x}, ${e.rect.y}) ${e.rect.w}x${e.rect.h}`).join('\n'));

        if (tree.length === 0) {
            throw new Error('Failed to find any elements in UI tree');
        }

        // 3. Find and Tap "Go to Form"
        console.log('Navigating to Form Screen (by key)...');
        // Using key selector
        const tapResult = await client.tap('key=form_button');
        console.log('Tap Result:', JSON.stringify(tapResult, null, 2));

        // Wait for navigation
        await sleep(1000);

        // 4. Enter Text
        console.log('Tapping text field...');
        await client.tap('label="Enter Text"');
        await sleep(500);

        const treeAfterTap = await client.getTree();
        const textFieldAfterTap = treeAfterTap.find(e => e.label === 'Enter Text');
        console.log('TextField after tap:', textFieldAfterTap);

        console.log('Entering text...');
        await client.enterText('Hello FAP', 'label="Enter Text"');

        await sleep(500);

        // Verify text updated
        const treeAfterText = await client.getTree();
        const textField = treeAfterText.find(e => e.label === 'Enter Text' || e.value === 'Hello FAP');
        console.log('TextField after entry:', textField);

        // 5. Tap Submit
        console.log('Submitting form...');
        // Debug: print tree
        const formTree = await client.getTree();
        console.log('Form Screen Elements:', formTree.map(e => `[${e.id}] ${e.label || e.value || e.hint}`).join(', '));

        await client.tap('text="Submit"');

        await sleep(500);

        // 6. Verify Result
        console.log('Verifying result...');
        const newTree = await client.getTree();
        const found = newTree.find(e => e.label === 'Submitted: Hello FAP' || e.value === 'Submitted: Hello FAP');

        if (found) {
            console.log('SUCCESS: Found submitted text!');
        } else {
            console.log('FAILURE: Could not find "Submitted: Hello FAP"');
            // Print tree for debugging
            console.log('Current Tree Labels:', newTree.map(e => e.label || e.value).filter(Boolean));
        }

        // 7. Advanced Gestures Verification
        console.log('--- Advanced Gestures Verification ---');

        // Navigate back home
        console.log('Navigating back to Home...');
        await client.tap('key=back_home_button');
        await sleep(1000);

        // Navigate to Gestures
        console.log('Navigating to Gestures Screen...');
        await client.tap('key=gestures_button');
        await sleep(1000);

        // Wait for gestures screen to load
        console.log('Waiting for Gestures Screen...');
        let gesturesRetries = 0;
        let gesturesTree = await client.getTree();
        while (!gesturesTree.find(e => e.key === 'long_press_box') && gesturesRetries < 10) {
            await sleep(500);
            gesturesTree = await client.getTree();
            gesturesRetries++;
        }
        if (!gesturesTree.find(e => e.key === 'long_press_box')) {
            throw new Error('Gestures Screen failed to load');
        }

        // 7a. Long Press
        console.log('Testing Long Press...');
        await client.longPress('key=long_press_box');
        await sleep(500);
        gesturesTree = await client.getTree();
        let status = gesturesTree.find(e => e.key === 'gesture_status')?.label || gesturesTree.find(e => e.key === 'gesture_status')?.value;
        console.log('Status after Long Press:', status);
        if (status !== 'Status: Long Pressed') console.error('Long Press Failed!');

        // 7b. Double Tap
        console.log('Testing Double Tap...');
        await client.doubleTap('key=double_tap_box');
        await sleep(500);
        gesturesTree = await client.getTree();
        status = gesturesTree.find(e => e.key === 'gesture_status')?.label || gesturesTree.find(e => e.key === 'gesture_status')?.value;
        console.log('Status after Double Tap:', status);
        if (status !== 'Status: Double Tapped') console.error('Double Tap Failed!');

        // 7c. Drag
        console.log('Testing Drag...');
        await client.drag('key=drag_box', { x: 50, y: 50 }, 1000); // Slower drag
        await sleep(500);
        gesturesTree = await client.getTree();
        status = gesturesTree.find(e => e.key === 'gesture_status')?.label || gesturesTree.find(e => e.key === 'gesture_status')?.value;
        console.log('Status after Drag:', status);
        if (!status?.includes('Dragging')) console.error('Drag Failed!');

        // 7d. Scroll
        console.log('Testing Scroll...');
        // Scroll the list down
        await client.scroll('key=scroll_container', 0, 300, 1000); // Slower scroll
        await sleep(1000);
        gesturesTree = await client.getTree();
        // Check if "Item 10" is visible (it shouldn't be visible initially)
        const item10 = gesturesTree.find(e => e.label === 'Item 10' || e.value === 'Item 10');
        console.log('Item 10 visible:', !!item10);
        if (!item10) console.warn('Scroll might not have worked or Item 10 is not in view yet.');

        // 8. Capture Screenshot
        console.log('Capturing screenshot...');
        const screenshot = await client.captureScreenshot();
        const screenshotPath = path.resolve('e2e_screenshot.png');
        fs.writeFileSync(screenshotPath, screenshot);
        console.log(`Screenshot captured (${screenshot.length} bytes)`);
        console.log(`Saved to: ${screenshotPath}`);

        await client.disconnect();

    } catch (e) {
        console.error('E2E Test Failed:', e);
        process.exit(1);
    }
}

main();
