const { FapClient } = require('./fap_client/dist/client.js');

const client = new FapClient({
  url: 'ws://127.0.0.1:9001',
  secretToken: 'dev-test-token'
});

(async () => {
  try {
    await client.connect();
    await new Promise(resolve => setTimeout(resolve, 3000));

    console.log('✅ Connected to Neural Novelist\n');

    const initialTree = await client.getTree();
    console.log('📱 Dashboard has', initialTree.length, 'elements\n');

    console.log('📚 Projects found:');
    initialTree.filter(el => el.label && (
      el.label.includes('Quantum') ||
      el.label.includes('Shadow') ||
      el.label.includes('Digital')
    )).forEach(el => {
      console.log('  -', el.label.split('\n')[0]);
    });

    console.log('\n🎯 Attempting to open \"Quantum Heist\" project...\n');

    await client.tap('label*="Quantum Heist"');
    console.log('✅ Tap sent! Waiting for navigation...\n');

    await new Promise(resolve => setTimeout(resolve, 3000));

    const newTree = await client.getTree();
    console.log('📱 After tap: screen has', newTree.length, 'elements');
    console.log('📊 Element count: ', initialTree.length, '->', newTree.length);

    console.log('\n📝 Top labels on new screen:');
    newTree.filter(el => el.label).slice(0, 10).forEach((el, i) => {
      console.log(`  ${i+1}. ${el.label.split('\n')[0]}`);
    });

    if (newTree.length !== initialTree.length) {
      console.log('\n✅ SUCCESS! Navigation worked - screen changed!');
    } else {
      console.log('\n⚠️  Screen unchanged - tap may not have worked');
    }

    await client.disconnect();
    console.log('\n✅ Test complete');

  } catch (err) {
    console.error('❌ Error:', err.message);
    console.error(err.stack);
  }
})();
