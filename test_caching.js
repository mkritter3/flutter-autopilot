const { FapClient } = require('./fap_client/dist/client.js');

async function testCaching() {
  const client = new FapClient({
    url: 'ws://127.0.0.1:9001',
    secretToken: 'dev-test-token'
  });

  console.log('🧪 Testing Server-Side UI State Caching\n');
  console.log('='.repeat(60));

  try {
    // Test 1: Connect and get fresh tree
    console.log('\n📡 Test 1: Initial connection (should get fresh data)');
    await client.connect();
    await new Promise(resolve => setTimeout(resolve, 3000));

    const tree1 = await client.getTree();
    console.log(`  ✅ Elements: ${tree1.length}`);

    // Test 2: Disconnect and reconnect (should get cached data)
    console.log('\n📡 Test 2: Disconnect and reconnect quickly');
    await client.disconnect();
    console.log('  ⏸️  Disconnected');

    await new Promise(resolve => setTimeout(resolve, 1000));

    await client.connect();
    console.log('  📡 Reconnected');
    await new Promise(resolve => setTimeout(resolve, 500));

    const tree2 = await client.getTree();
    console.log(`  ✅ Elements: ${tree2.length} (should be from cache)`);

    // Test 3: Wait for cache expiry (>5s)
    console.log('\n📡 Test 3: Wait for cache to expire (6 seconds)');
    await client.disconnect();
    console.log('  ⏸️  Disconnected');

    await new Promise(resolve => setTimeout(resolve, 6000));

    await client.connect();
    console.log('  📡 Reconnected after cache expiry');
    await new Promise(resolve => setTimeout(resolve, 2000));

    const tree3 = await client.getTree();
    console.log(`  ✅ Elements: ${tree3.length} (cache should be expired)`);

    // Test 4: Test navigation with cached data
    console.log('\n📡 Test 4: Try navigation with caching');
    await client.disconnect();
    await new Promise(resolve => setTimeout(resolve, 500));
    await client.connect();
    await new Promise(resolve => setTimeout(resolve, 2000));

    const navTree = await client.getTree();
    console.log(`  ✅ Elements: ${navTree.length}`);

    if (navTree.length > 0) {
      // Look for a project to click
      const projects = navTree.filter(el =>
        el.label && (el.label.includes('Quantum') || el.label.includes('Project'))
      );

      if (projects.length > 0) {
        console.log(`  🎯 Found ${projects.length} clickable elements`);
        console.log(`  📝 First: "${projects[0].label.split('\\n')[0]}"`);

        try {
          await client.tap(`label*="${projects[0].label.split('\\n')[0]}"`);
          console.log('  ✅ Tap successful!');

          await new Promise(resolve => setTimeout(resolve, 2000));
          const afterTap = await client.getTree();
          console.log(`  📱 After tap: ${afterTap.length} elements`);
        } catch (tapErr) {
          console.log(`  ⚠️  Tap failed: ${tapErr.message}`);
        }
      }
    }

    await client.disconnect();

    console.log('\n' + '='.repeat(60));
    console.log('✅ Caching test complete!\n');

  } catch (err) {
    console.error('❌ Error:', err.message);
    console.error(err.stack);
  }
}

testCaching();
