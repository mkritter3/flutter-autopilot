import { FapClient } from '../src/client';

async function main() {
    const client = new FapClient({ secretToken: 'my-secret-token' });

    try {
        console.log('Connecting...');
        await client.connect();
        console.log('Connected.');

        // 1. Initial Fetch (Full Tree via Diff)
        console.log('Fetching initial tree...');
        const initialTree = await client.getTree();
        console.log(`Initial tree size: ${initialTree.length}`);

        if (initialTree.length === 0) {
            throw new Error('Initial tree is empty');
        }

        // 2. Perform Action to Change State
        // Tap the counter button to increment count
        console.log('Tapping counter button...');
        // We need to find the FAB. In main.dart it doesn't have a key, but it has a tooltip 'Increment'.
        // Wait, the FAB in main.dart:
        /*
        floatingActionButton: FloatingActionButton(
            onPressed: _incrementCounter,
            tooltip: 'Increment',
            child: const Icon(Icons.add),
        ),
        */
        // But wait, I don't see FAB in HomeScreen in main.dart I viewed earlier.
        // Let's check main.dart again.
        // Ah, HomeScreen in main.dart (lines 38-94) does NOT have a FAB.
        // It has a Text widget 'Count: 0' (line 87).
        // But where is the button to increment it?
        // It seems I missed the FAB in the previous view or it's not there.
        // Let's look at HomeScreen again.

        // Wait, I can use the "Go to Form" button to navigate.
        // That will definitely change the tree.

        console.log('Navigating to Form Screen...');
        await client.tap('key="form_button"');

        // Wait a bit for navigation
        await new Promise(resolve => setTimeout(resolve, 1000));

        // 3. Fetch Diff
        console.log('Fetching diff...');
        // We access the private method request to get the raw diff for verification
        const diff = await (client as any).request('getTreeDiff');

        console.log(`Diff: Added=${diff.added.length}, Removed=${diff.removed.length}, Updated=${diff.updated.length}`);

        if (diff.added.length === 0 && diff.removed.length === 0 && diff.updated.length === 0) {
            console.warn('Warning: Diff is empty. Maybe navigation didn\'t happen or tree didn\'t change?');
        } else {
            console.log('✅ Diff received!');
        }

        // 4. Verify Client State
        const currentTree = await client.getTree(); // This uses applyDiff internally
        console.log(`Current tree size: ${currentTree.length}`);

        // Check if we are on Form Screen
        const formTitle = currentTree.find(e => e.label === 'Form');
        if (formTitle) {
            console.log('✅ Found "Form" title in updated tree');
        } else {
            console.error('❌ "Form" title not found in updated tree');
            process.exit(1);
        }

        console.log('TEST PASSED');
        process.exit(0);

    } catch (e) {
        console.error('Error:', e);
        process.exit(1);
    } finally {
        await client.disconnect();
    }
}

main();
