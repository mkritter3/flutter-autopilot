import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

class ScreenshotUtils {
  Future<Uint8List?> capture() async {
    try {
      final boundary = _findRootRepaintBoundary();
      if (boundary == null) {
        print('No RepaintBoundary found');
        return null;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      print('Screenshot failed: $e');
      return null;
    }
  }

  RenderRepaintBoundary? _findRootRepaintBoundary() {
    // This is a heuristic. In a real app, we might need to wrap the app in a RepaintBoundary
    // and register a GlobalKey.
    // For now, let's try to find one in the tree.
    
    RenderRepaintBoundary? result;
    
    void visitor(RenderObject object) {
      if (object is RenderRepaintBoundary && result == null) {
        // We want the root-most one, usually the one under the View
        result = object;
        return; // Found one, but is it the root? 
        // Actually, we probably want to continue to find the *highest* one?
        // Or just the first one we encounter from root down?
      }
      object.visitChildren(visitor);
    }

    // Use renderViews.first for MVP
    final view = RendererBinding.instance.renderViews.first;
    view.visitChildren(visitor);
    return result;
  }
}
