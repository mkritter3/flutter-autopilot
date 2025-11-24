import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'semantics_index.dart';
import 'selector_generator.dart';

class Recorder {
  final SemanticsIndexer indexer;
  final StreamController<Map<String, dynamic>> _eventController = StreamController.broadcast();
  bool _isRecording = false;

  Recorder(this.indexer);

  Stream<Map<String, dynamic>> get events => _eventController.stream;
  bool get isRecording => _isRecording;

  void start() {
    if (_isRecording) return;
    _isRecording = true;
    RendererBinding.instance.pointerRouter.addGlobalRoute(_handlePointerEvent);
    debugPrint('Recorder: Started');
  }

  void stop() {
    if (!_isRecording) return;
    _isRecording = false;
    RendererBinding.instance.pointerRouter.removeGlobalRoute(_handlePointerEvent);
    debugPrint('Recorder: Stopped');
  }

  void _handlePointerEvent(PointerEvent event) {
    if (!_isRecording) return;

    // We only care about "up" events (taps) for now.
    // TODO: Handle scrolls/drags?
    if (event is PointerUpEvent) {
      // Reindex to ensure we have latest positions
      indexer.reindex();
      
      final element = indexer.hitTest(event.position);
      if (element != null) {
        final selector = SelectorGenerator.generate(element, indexer);
        final eventData = {
          'action': 'tap',
          'selector': selector,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'x': event.position.dx,
          'y': event.position.dy,
        };
        _eventController.add(eventData);
        debugPrint('Recorder: Captured tap on $selector');
      }
    }
  }
}
