import { FapClient } from './fap_client/dist/client.js';
import * as fs from 'fs';

async function main() {
    const client = new FapClient({
        url: 'ws://127.0.0.1:9001',
        secretToken: 'dev-test-token',
    });

    try {
        console.log('Connecting to FAP Agent...');
        await client.connect();
        console.log('Connected!');

        // Wait for app to load
        await new Promise(resolve => setTimeout(resolve, 2000));

        // 1. Test Widget Inspector - Get full tree
        console.log('\n=== Testing Widget Inspector ===');
        console.log('Getting widget tree...');
        const widgets = await client.getWidgetTree();
        console.log(`Found ${widgets.length} widgets`);

        // Save to file for inspection
        fs.writeFileSync('widget_tree_dump.json', JSON.stringify(widgets, null, 2));
        console.log('Widget tree saved to widget_tree_dump.json');

        // 2. Find Super Editor widgets specifically
        console.log('\n=== Finding Super Editor ===');
        const editors = await client.findWidgetByType('SuperEditor');
        console.log(`Found ${editors.length} SuperEditor widgets`);

        if (editors.length > 0) {
            console.log('\nFirst SuperEditor:');
            console.log(JSON.stringify(editors[0], null, 2));

            const editorBounds = editors[0].bounds;
            console.log(`\nEditor bounds: x=${editorBounds.x}, y=${editorBounds.y}, w=${editorBounds.w}, h=${editorBounds.h}`);
            console.log(`Editor center: (${editorBounds.x + editorBounds.w / 2}, ${editorBounds.y + editorBounds.h / 2})`);
        }

        // 3. Find other interesting widgets
        console.log('\n=== Finding Text-related Widgets ===');
        const textWidgets = widgets.filter(w =>
            w.type.includes('Text') ||
            w.type.includes('Editor') ||
            w.type.includes('Field')
        );
        console.log(`Found ${textWidgets.length} text-related widgets:`);
        textWidgets.slice(0, 5).forEach(w => {
            console.log(`  - ${w.type} at (${w.bounds.x}, ${w.bounds.y})`);
        });

        // 4. Test coordinate-based widget finding
        if (editors.length > 0) {
            console.log('\n=== Testing Coordinate-based Finding ===');
            const center = {
                x: editors[0].bounds.x + editors[0].bounds.w / 2,
                y: editors[0].bounds.y + editors[0].bounds.h / 2
            };
            const widgetAt = await client.findWidgetAt(center.x, center.y);
            console.log(`Widget at editor center: ${widgetAt ? widgetAt.type : 'none'}`);
        }

        console.log('\n✅ Widget Inspector test complete!');

    } catch (error) {
        console.error('Error:', error);
    } finally {
        client.disconnect();
    }
}

main();
