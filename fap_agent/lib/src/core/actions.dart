import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';

class ActionExecutor {
  static int _pointerId = 0;

  // Helper to get next pointer ID
  int _nextPointerId() => ++_pointerId;

  Future<Map<String, dynamic>> tap(Rect globalRect, {SemanticsNode? semanticsNode}) async {
    final center = globalRect.center;
    final pointer = _nextPointerId();

    print('ActionExecutor.tap: $center');

    // Hover
    _dispatchPointerEvent(PointerHoverEvent(
      position: center,
      kind: PointerDeviceKind.mouse,
    ));
    await Future.delayed(const Duration(milliseconds: 50));

    // Down
    _dispatchPointerEvent(PointerDownEvent(
      position: center,
      pointer: pointer,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    ));
    await Future.delayed(const Duration(milliseconds: 100));

    // Up
    _dispatchPointerEvent(PointerUpEvent(
      position: center,
      pointer: pointer,
      kind: PointerDeviceKind.mouse,
      buttons: 0,
    ));

    // Fallback: Perform semantic action
    if (semanticsNode != null && semanticsNode.owner != null) {
      print('  Performing SemanticsAction.tap fallback');
      semanticsNode.owner!.performAction(semanticsNode.id, SemanticsAction.tap);
    }

    return {'status': 'tapped', 'center': {'x': center.dx, 'y': center.dy}};
  }

  Future<Map<String, dynamic>> doubleTap(Rect globalRect) async {
    final center = globalRect.center;
    print('ActionExecutor.doubleTap: $center');

    // First tap
    await tap(globalRect);
    
    // Delay between taps
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Second tap
    await tap(globalRect);

    return {'status': 'double_tapped'};
  }

  Future<Map<String, dynamic>> longPress(Rect globalRect, {Duration duration = const Duration(milliseconds: 800)}) async {
    final center = globalRect.center;
    final pointer = _nextPointerId();
    print('ActionExecutor.longPress: $center duration=${duration.inMilliseconds}ms');

    // Down
    _dispatchPointerEvent(PointerDownEvent(
      position: center,
      pointer: pointer,
      kind: PointerDeviceKind.touch, // Touch is often better for long press
    ));

    // Wait
    await Future.delayed(duration);

    // Up
    _dispatchPointerEvent(PointerUpEvent(
      position: center,
      pointer: pointer,
      kind: PointerDeviceKind.touch,
    ));

    return {'status': 'long_pressed'};
  }

  Future<Map<String, dynamic>> scroll(Rect globalRect, double dx, double dy, {Duration duration = const Duration(milliseconds: 300)}) async {
    final start = globalRect.center;
    final end = start.translate(-dx, -dy); // Scroll moves content, so drag is opposite? 
    // Actually, "scroll down" usually means drag finger UP.
    // If user says "scroll(dx: 0, dy: 100)", they likely mean "scroll content by 100 pixels".
    // To scroll content down (move viewport up), we drag finger UP.
    // Let's assume dx/dy are "scroll deltas".
    // Drag vector = -scroll delta.
    
    return drag(start, end, duration: duration);
  }

  Future<Map<String, dynamic>> drag(Offset start, Offset end, {Duration duration = const Duration(milliseconds: 300)}) async {
    final pointer = _nextPointerId();
    print('ActionExecutor.drag: $start -> $end');

    // Down
    _dispatchPointerEvent(PointerDownEvent(
      position: start,
      pointer: pointer,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    ));

    // Move
    final steps = 20;
    final stepDuration = duration ~/ steps;
    final delta = (end - start) / steps.toDouble();
    
    var current = start;
    for (var i = 0; i < steps; i++) {
      await Future.delayed(stepDuration);
      current += delta;
      _dispatchPointerEvent(PointerMoveEvent(
        position: current,
        pointer: pointer,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
        delta: delta,
      ));
    }

    // Up
    _dispatchPointerEvent(PointerUpEvent(
      position: end,
      pointer: pointer,
      kind: PointerDeviceKind.mouse,
      buttons: 0,
    ));

    return {'status': 'dragged', 'start': {'x': start.dx, 'y': start.dy}, 'end': {'x': end.dx, 'y': end.dy}};
  }

  Future<void> enterText(SemanticsNode node, String text) async {
    print('ActionExecutor: enterText "$text" on node ${node.id}');
    if (node.owner != null) {
      node.owner!.performAction(node.id, SemanticsAction.setText, text);
    }
  }

  Future<void> setSelection(SemanticsNode node, int base, int extent) async {
    print('ActionExecutor: setSelection ($base, $extent) on node ${node.id}');
    if (node.owner != null) {
      node.owner!.performAction(node.id, SemanticsAction.setSelection, TextSelection(baseOffset: base, extentOffset: extent));
    }
  }

  void _dispatchPointerEvent(PointerEvent event) {
    GestureBinding.instance.handlePointerEvent(event);
  }
}
