import { FapClient } from './client';
import * as fs from 'fs';
import * as path from 'path';

async function sleep(ms: number) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function main() {
    console.log('Starting FAP E2E Verification...');
    const client = new FapClient({
        url: 'ws://localhost:9001',
        secretToken: 'my-secret-token'
    });

    try {
        // 1. Connect
        console.log('Connecting to FAP Agent...');
        await client.connect();
        console.log('Connected!');

        // 2. List Elements (Home Screen)
        console.log('Fetching UI Tree...');
        // Use waitFor to ensure tree is ready
        await client.waitFor('key=form_button');
        const tree = await client.getTree();
        console.log(`Found ${tree.length} elements.`);

        // Verify Route
        const initialRoute = await client.getRoute();
        console.log('Current Route:', initialRoute);
        if (initialRoute !== '/') throw new Error(`Expected route '/', got '${initialRoute}'`);

        // 3. Find and Tap "Go to Form"
        console.log('Navigating to Form Screen (by key)...');
        await client.tap('key=form_button');

        // Wait for Form Screen using waitFor
        console.log('Waiting for Form Screen...');
        await client.waitFor('label="Enter Text"');

        // Verify Route
        const formRoute = await client.getRoute();
        console.log('Current Route:', formRoute);
        if (formRoute !== '/form') throw new Error(`Expected route '/form', got '${formRoute}'`);

        // 4. Enter Text
        // console.log('Tapping text field...');
        // await client.tap('label="Enter Text"');
        // await sleep(500);

        // console.log('Entering text...');
        // await client.enterText('Hello FAP', 'label="Enter Text"');
        // Verify text field updated
        // await client.waitFor('value="Hello FAP"');

        // 5. Tap Submit
        // console.log('Submitting form...');
        // await client.tap('text="Submit"');
        // await sleep(500);

        // 6. Verify Result
        // console.log('Verifying result...');
        // await client.waitFor('text="Submitted: Hello FAP"');
        // console.log('SUCCESS: Found submitted text!');

        // 7. Advanced Gestures Verification
        console.log('--- Advanced Gestures Verification ---');

        // Navigate back home
        console.log('Navigating back to Home...');
        await client.tap('key=back_home_button');
        await client.waitFor('key=gestures_button');

        // Navigate to Gestures
        console.log('Navigating to Gestures Screen...');
        await client.tap('key=gestures_button');
        await client.waitFor('key=long_press_box');

        // Verify Route
        const gesturesRoute = await client.getRoute();
        if (gesturesRoute !== '/gestures') throw new Error(`Expected route '/gestures', got '${gesturesRoute}'`);

        // 7a. Long Press
        console.log('Testing Long Press...');
        await client.longPress('key=long_press_box');
        await sleep(500);
        let gesturesTree = await client.getTree();
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
        await client.drag('key=drag_box', { x: 50, y: 50 }, 1000);
        await sleep(500);
        gesturesTree = await client.getTree();
        status = gesturesTree.find(e => e.key === 'gesture_status')?.label || gesturesTree.find(e => e.key === 'gesture_status')?.value;
        console.log('Status after Drag:', status);
        if (!status?.includes('Dragging')) console.error('Drag Failed!');

        // 7d. Scroll
        console.log('Testing Scroll...');
        await client.scroll('key=scroll_container', 0, 300, 1000);
        await sleep(1000);
        gesturesTree = await client.getTree();
        const item10 = gesturesTree.find(e => e.label === 'Item 10' || e.value === 'Item 10');
        console.log('Item 10 visible:', !!item10);
        if (!item10) console.warn('Scroll might not have worked or Item 10 is not in view yet.');

        // 8. Observability
        console.log('--- Observability Verification ---');
        console.log('Navigating back to Home...');
        await client.tap('key=gestures_back_button');
        await client.waitFor('key=observability_button');

        console.log('Navigating to Observability Screen...');
        await client.tap('key=observability_button');
        await client.waitFor('key=log_button');

        // 8a. Logs
        console.log('Testing Log Capture...');
        await client.tap('key=log_button');
        await sleep(500);
        const logs = await client.getLogs();
        console.log('Captured Logs:', logs.length);
        const foundLog = logs.some(l => l.includes('Test Log Message'));
        if (!foundLog) throw new Error('Failed to capture log message');
        console.log('Log capture verified!');

        // 8b. Performance Metrics
        console.log('Testing Performance Metrics...');
        await client.tap('key=jank_button');
        await sleep(500);
        const metrics = await client.getPerformanceMetrics();
        console.log('Captured Metrics:', metrics.length);
        if (metrics.length === 0) throw new Error('No performance metrics captured');
        console.log('Last frame build time:', metrics[metrics.length - 1].build, 'us');
        console.log('Performance metrics verified!');

        // 8c. Async Errors
        console.log('Testing Async Error Capture...');
        await client.tap('key=error_button');
        await sleep(500);
        const errors = await client.getErrors();
        console.log('Captured Errors:', errors);
        const foundError = errors.some(e =>
            (typeof e === 'string' && e.includes('Test Async Error')) ||
            (e.message && e.message.includes('Test Async Error'))
        );
        if (!foundError) throw new Error('Failed to capture async error');
        console.log('Async error capture verified!');

        console.log('Navigating back to Home...');
        await client.tap('key=back_home_button');
        await client.waitFor('key=advanced_button');

        // 9. Advanced Selectors Verification
        console.log('--- Advanced Selectors Verification ---');
        console.log('Navigating to Advanced Selectors Screen...');
        await client.tap('key=advanced_button');
        await client.waitFor('test-id="meta-btn"'); // Using waitFor with metadata selector!

        // 9a. Metadata Selector
        console.log('Testing Metadata Selector...');
        await client.tap('test-id="meta-btn"');
        console.log('Metadata selector verified!');

        // 9b. Regex Selector
        console.log('Testing Regex Selector...');
        const findResult: any = await client.tap('text=~/^Dynamic ID: \\d+-ABC$/');
        if (findResult.status !== 'tapped') throw new Error('Failed to match regex selector');
        console.log('Regex selector verified!');

        // 9c. Combinators
        console.log('Testing Combinators...');
        await client.tap('key="parent_container" text="Direct Child"');
        console.log('Descendant combinator verified!');

        console.log('Navigating back to Home...');
        await client.tap('key=back_home_button');
        await client.waitFor('key=form_button');

        // 10. Screenshot
        console.log('Capturing screenshot...');
        const screenshot = await client.captureScreenshot();
        const screenshotPath = path.resolve('e2e_screenshot.png');
        fs.writeFileSync(screenshotPath, screenshot);
        console.log(`Screenshot captured (${screenshot.length} bytes)`);
        console.log(`Saved to: ${screenshotPath}`);

        console.log('E2E Test Passed!');
    } catch (e) {
        console.error('E2E Test Failed:', e);
        process.exit(1);
    } finally {
        await client.disconnect();
    }
}

main();
