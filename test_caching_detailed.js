const { FapClient } = require('./fap_client/dist/client.js');

async function testCachingDetailed() {
  const client = new FapClient({
    url: 'ws://127.0.0.1:9001',
    secretToken: 'dev-test-token'
  });

  console.log('🔍 Detailed Caching Test\n');
  console.log('='.repeat(60));

  try {
    // Test 1: Initial connection
    console.log('\n📡 Test 1: Initial Connection');
    await client.connect();
    console.log('  ✅ Connected');

    // Wait for UI to stabilize
    await new Promise(resolve => setTimeout(resolve, 3000));

    const tree1 = await client.getTree();
    console.log(`  📊 Result: ${tree1.length} elements`);
    console.log('  💡 This should be fresh data (not cached)\n');

    // Test 2: Quick Reconnect (should hit cache)
    console.log('📡 Test 2: Quick Reconnect (< 5s)');
    await client.disconnect();
    console.log('  ⏸️  Disconnected');

    await new Promise(resolve => setTimeout(resolve, 1000));

    await client.connect();
    console.log('  📡 Reconnected after 1 second');

    // Don't wait - request immediately to test cache
    await new Promise(resolve => setTimeout(resolve, 500));

    const tree2 = await client.getTree();
    console.log(`  📊 Result: ${tree2.length} elements`);
    console.log('  💡 This SHOULD be from cache (age ~1.5s)\n');

    // Test 3: Cache Expiry
    console.log('📡 Test 3: Cache Expiry (> 5s)');
    await client.disconnect();
    console.log('  ⏸️  Disconnected');

    await new Promise(resolve => setTimeout(resolve, 6000));

    await client.connect();
    console.log('  📡 Reconnected after 6 seconds');

    await new Promise(resolve => setTimeout(resolve, 2000));

    const tree3 = await client.getTree();
    console.log(`  📊 Result: ${tree3.length} elements`);
    console.log('  💡 Cache should be expired (or fresh data rebuilt)\n');

    await client.disconnect();

    console.log('='.repeat(60));
    console.log('✅ Detailed caching test complete!\n');

  } catch (err) {
    console.error('❌ Error:', err.message);
    console.error(err.stack);
  }
}

testCachingDetailed();
