import { FapClient } from './client';
import * as fs from 'fs';
import * as path from 'path';

async function main() {
    const client = new FapClient({ url: 'ws://localhost:9001' });

    console.log('Connecting...');
    await client.connect();

    console.log('Capturing screenshot...');
    const screenshot = await client.captureScreenshot();
    const screenshotBase64 = screenshot.toString('base64');

    console.log('Fetching UI tree...');
    const tree = await client.getTree();

    await client.disconnect();

    console.log('Generating visualization...');

    // Generate HTML
    const html = `
<!DOCTYPE html>
<html>
<head>
    <style>
        body { margin: 0; padding: 20px; font-family: sans-serif; background: #333; }
        .container { position: relative; display: inline-block; }
        img { border: 2px solid #555; }
        .rect {
            position: absolute;
            border: 2px solid rgba(255, 0, 0, 0.7);
            background: rgba(255, 0, 0, 0.1);
            color: white;
            font-size: 10px;
            overflow: hidden;
            pointer-events: none;
            box-sizing: border-box;
        }
        .rect:hover {
            background: rgba(255, 0, 0, 0.3);
            border-color: yellow;
            z-index: 10;
        }
        .label {
            background: rgba(0,0,0,0.7);
            padding: 2px;
            position: absolute;
            top: 0;
            left: 0;
            white-space: nowrap;
        }
    </style>
</head>
<body>
    <h1>FAP Layout Visualization</h1>
    <div class="container">
        <img src="data:image/png;base64,${screenshotBase64}" width="800" />
        ${tree.map(el => {
        // Adjust coordinates for the displayed image width (assuming 800px display width)
        // The screenshot is likely high-DPI (e.g. 1600px wide).
        // We need to know the actual image width to scale correctly.
        // For now, let's use percentage based on the assumed logical size or just raw pixels if we display raw.
        // Let's display raw pixels but scale with CSS if needed.
        // Actually, the rects are in physical pixels (from our previous debugging).
        // And the screenshot is in physical pixels.
        // So they should match 1:1 if we display the image at its natural size.
        // But to fit in browser, we might scale.
        // Let's use a scale factor. Assuming screenshot width is roughly 1600 (from logs).
        const scale = 0.5; // Display at half size
        return `
            <div class="rect" style="
                left: ${el.rect.x * scale}px;
                top: ${el.rect.y * scale}px;
                width: ${el.rect.w * scale}px;
                height: ${el.rect.h * scale}px;
            ">
                <div class="label">${el.id}</div>
            </div>`;
    }).join('')}
    </div>
    <p>Found ${tree.length} elements.</p>
</body>
</html>
    `;

    const htmlPath = path.resolve('layout_visualization.html');
    fs.writeFileSync(htmlPath, html);
    console.log(`Visualization saved to: ${htmlPath}`);
}

main().catch(console.error);
