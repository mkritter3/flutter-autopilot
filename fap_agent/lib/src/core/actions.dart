import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';

class ActionExecutor {
  Future<Map<String, dynamic>> tap(Rect rect) async {
    // Get DPR
    // We assume the first view is the main one for now.
    final view = RendererBinding.instance.renderViews.first.flutterView;
    final dpr = view.devicePixelRatio;
    
    // Convert physical coordinates (from Semantics) to logical coordinates (for HitTest)
    final centerPhysical = rect.center;
    final centerLogical = centerPhysical / dpr;
    
    final hitTestResult = HitTestResult();
    // ignore: deprecated_member_use
    GestureBinding.instance.hitTest(hitTestResult, centerLogical);
    
    final down = PointerDownEvent(
      position: centerLogical,
      kind: PointerDeviceKind.touch,
    );
    
    GestureBinding.instance.handlePointerEvent(down);
    
    await Future.delayed(const Duration(milliseconds: 50));
    
    final up = PointerUpEvent(
      position: centerLogical,
      kind: PointerDeviceKind.touch,
    );
    
    GestureBinding.instance.handlePointerEvent(up);
    
    return {
      'hitTestPath': hitTestResult.path.toString(),
      'center': {'x': centerLogical.dx, 'y': centerLogical.dy},
      'dpr': dpr,
    };
  }

  Future<void> enterText(SemanticsNode node, String text) async {
    print('ActionExecutor: enterText "$text" on node ${node.id}');
    
    // Check if node supports setText
    // We can just try to perform the action.
    if (node.owner != null) {
      node.owner!.performAction(node.id, SemanticsAction.setText, text);
      // Also perform didGainAccessibilityFocus if needed?
      // Usually setText is enough.
    } else {
      print('ActionExecutor: Node ${node.id} has no owner!');
    }
  }
}
