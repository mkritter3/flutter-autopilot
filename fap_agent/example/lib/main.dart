import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fap_agent/fap_agent.dart';

void main() {
  FapAgent.init(const FapConfig(
    port: 9001,
    enabled: true,
  ));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    SemanticsBinding.instance.ensureSemantics();
    return MaterialApp(
      title: 'FAP Example',
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/details': (context) => const DetailsScreen(),
        '/list': (context) => const ListScreen(),
        '/form': (context) => const FormScreen(),
        '/gestures': (context) => const GesturesScreen(),
      },
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FAP Home')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              key: const Key('details_button'),
              onPressed: () => Navigator.pushNamed(context, '/details'),
              child: const Text('Go to Details'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              key: const Key('list_button'),
              onPressed: () => Navigator.pushNamed(context, '/list'),
              child: const Text('Go to List'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              key: const Key('form_button'),
              onPressed: () => Navigator.pushNamed(context, '/form'),
              child: const Text('Go to Form'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              key: const Key('gestures_button'),
              onPressed: () => Navigator.pushNamed(context, '/gestures'),
              child: const Text('Go to Gestures'),
            ),
            const SizedBox(height: 20),
            Semantics(
              label: 'Counter Value',
              child: const Text('Count: 0'),
            ),
          ],
        ),
      ),
    );
  }
}

class DetailsScreen extends StatelessWidget {
  const DetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Details')),
      body: Center(
        child: Column(
          children: [
            const Text('This is the details screen'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

class ListScreen extends StatelessWidget {
  const ListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('List View')),
      body: ListView.builder(
        itemCount: 50,
        itemBuilder: (context, index) {
          return ListTile(
            title: Text('Item $index'),
            subtitle: Text('Subtitle for $index'),
            onTap: () {
              print('Tapped item $index');
            },
          );
        },
      ),
    );
  }
}

class FormScreen extends StatefulWidget {
  const FormScreen({super.key});

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  final _controller = TextEditingController();
  String _submittedText = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Form')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Enter Text',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _submittedText = _controller.text;
                });
              },
              child: const Text('Submit'),
            ),
            const SizedBox(height: 20),
            const SizedBox(height: 20),
            Text('Submitted: $_submittedText'),
            const SizedBox(height: 20),
            ElevatedButton(
              key: const Key('back_home_button'),
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}

class GesturesScreen extends StatefulWidget {
  const GesturesScreen({super.key});

  @override
  State<GesturesScreen> createState() => _GesturesScreenState();
}

class _GesturesScreenState extends State<GesturesScreen> {
  String _status = 'Idle';
  double _dragX = 0;
  double _dragY = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestures')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text('Status: $_status', key: const Key('gesture_status')),
            const SizedBox(height: 20),
            
            // Long Press
            GestureDetector(
              key: const Key('long_press_box'),
              onLongPress: () {
                setState(() => _status = 'Long Pressed');
              },
              child: Container(
                width: 100,
                height: 100,
                color: Colors.blue,
                alignment: Alignment.center,
                child: const Text('Long Press Me'),
              ),
            ),
            const SizedBox(height: 20),

            // Double Tap
            GestureDetector(
              key: const Key('double_tap_box'),
              onDoubleTap: () {
                setState(() => _status = 'Double Tapped');
              },
              child: Container(
                width: 100,
                height: 100,
                color: Colors.green,
                alignment: Alignment.center,
                child: const Text('Double Tap Me'),
              ),
            ),
            const SizedBox(height: 20),

            // Drag
            GestureDetector(
              key: const Key('drag_box'),
              onPanUpdate: (details) {
                setState(() {
                  _dragX += details.delta.dx;
                  _dragY += details.delta.dy;
                  _status = 'Dragging: ${_dragX.toStringAsFixed(1)}, ${_dragY.toStringAsFixed(1)}';
                });
              },
              child: Container(
                width: 100,
                height: 100,
                color: Colors.orange,
                alignment: Alignment.center,
                child: const Text('Drag Me'),
              ),
            ),
            const SizedBox(height: 20),
            
            // Scroll Target
            Semantics(
              key: const Key('scroll_container'),
              explicitChildNodes: true,
              label: 'Scroll Area',
              child: Container(
                height: 300,
                color: Colors.grey[200],
                child: ListView.builder(
                  key: const Key('scroll_list'),
                  itemCount: 50,
                  itemBuilder: (context, index) => ListTile(
                    title: Text('Item $index'),
                    key: Key('item_$index'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
