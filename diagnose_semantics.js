const { FapClient } = require('./fap_client/dist/client.js');

async function diagnoseSemanticsIssue() {
  const client = new FapClient({
    url: 'ws://127.0.0.1:9001',
    secretToken: 'dev-test-token'
  });

  console.log('🔬 Comprehensive Semantics Diagnostics\n');
  console.log('='.repeat(70));

  try {
    // Test 1: Initial connection with varying wait times
    console.log('\n📋 Test 1: Connection with Progressive Wait Times');
    console.log('-'.repeat(70));

    await client.connect();
    console.log('✅ Connected to FAP\n');

    const waitTimes = [0, 1000, 2000, 5000, 10000];

    for (const waitMs of waitTimes) {
      if (waitMs > 0) {
        console.log(`⏱️  Waiting ${waitMs}ms...`);
        await new Promise(resolve => setTimeout(resolve, waitMs));
      }

      const tree = await client.getTree();
      console.log(`   📊 After ${waitMs}ms: ${tree.length} elements`);

      if (tree.length > 0) {
        console.log(`   ✅ SUCCESS! Semantics populated after ${waitMs}ms`);
        console.log(`\n   Sample elements:`);
        tree.slice(0, 3).forEach((el, i) => {
          console.log(`   ${i + 1}. ID:${el.id} Label:"${el.label || '(none)'}"`);
        });
        break;
      }
    }

    await client.disconnect();
    console.log('\n⏸️  Disconnected\n');

    // Test 2: Multiple reconnection cycles
    console.log('📋 Test 2: Multiple Reconnection Cycles');
    console.log('-'.repeat(70));

    for (let cycle = 1; cycle <= 3; cycle++) {
      console.log(`\n🔄 Cycle ${cycle}:`);

      await client.connect();
      console.log('  ✅ Connected');

      await new Promise(resolve => setTimeout(resolve, 3000));

      const tree = await client.getTree();
      console.log(`  📊 Elements: ${tree.length}`);

      if (tree.length > 0) {
        console.log(`  ✅ Semantics working on cycle ${cycle}!`);
        break;
      }

      await client.disconnect();
      console.log('  ⏸️  Disconnected');

      if (cycle < 3) {
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    }

    console.log('\n' + '='.repeat(70));
    console.log('📝 Diagnostic Summary');
    console.log('='.repeat(70));
    console.log('\nIf all tests show 0 elements:');
    console.log('  → Semantics tree is not populating after ensureSemantics()');
    console.log('  → Likely needs frame rebuild trigger');
    console.log('  → OR app UI has no semantic nodes');
    console.log('\nNext steps:');
    console.log('  1. Check Flutter app console for "Semantics enabled" message');
    console.log('  2. Verify app has visible UI elements');
    console.log('  3. Add SchedulerBinding.instance.scheduleFrame() after ensureSemantics()');

  } catch (err) {
    console.error('\n❌ Error:', err.message);
    console.error(err.stack);
  }
}

diagnoseSemanticsIssue();
