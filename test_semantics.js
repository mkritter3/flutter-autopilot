const { FapClient } = require('./fap_client/dist/client.js');

async function testSemantics() {
  const client = new FapClient({
    url: 'ws://127.0.0.1:9001',
    secretToken: 'dev-test-token'
  });

  console.log('🔍 Testing Semantics Activation\n');

  try {
    console.log('1️⃣  Connecting to FAP...');
    await client.connect();
    console.log('   ✅ Connected\n');

    console.log('2️⃣  Waiting 5 seconds for Semantics to activate...');
    await new Promise(resolve => setTimeout(resolve, 5000));

    console.log('3️⃣  Requesting UI tree...');
    const tree = await client.getTree();
    console.log(`   📊 Got ${tree.length} elements\n`);

    if (tree.length > 0) {
      console.log('✅ Semantics is working!');
      console.log('\nFirst 5 elements:');
      tree.slice(0, 5).forEach((el, i) => {
        console.log(`  ${i + 1}. ${el.label || el.value || el.hint || '(no text)'}`);
      });
    } else {
      console.log('⚠️  Got 0 elements - Semantics may not be populating');
      console.log('\nPossible reasons:');
      console.log('  1. App has no visible UI');
      console.log('  2. Semantics tree has not rebuilt yet');
      console.log('  3. Issue with lazy Semantics activation');
    }

    await client.disconnect();
    console.log('\n✅ Test complete');

  } catch (err) {
    console.error('❌ Error:', err.message);
  }
}

testSemantics();
