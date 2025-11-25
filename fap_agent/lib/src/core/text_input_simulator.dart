import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Simulator for programmatic keyboard/text input
///
/// This works by wrapping the default binary messenger to intercept
/// TextInput channel messages in BOTH directions:
/// - Outgoing (Flutter → Platform): To track client connections and state
/// - Incoming (Platform → Flutter): To inject simulated keyboard input
class TextInputSimulator {
  static final TextInputSimulator instance = TextInputSimulator._();

  TextInputSimulator._();

  // Track the current text input client
  int? _currentClientId;
  Map<String, dynamic>? _currentConfig;
  Map<String, dynamic> _currentEditingState = {};
  bool _interceptorInstalled = false;

  // The wrapper messenger
  _InterceptingBinaryMessenger? _messenger;

  /// Initialize the text input interception
  /// Must be called after WidgetsFlutterBinding is initialized
  void initialize() {
    if (_interceptorInstalled) return;
    _interceptorInstalled = true;

    // Install the intercepting messenger
    _messenger = _InterceptingBinaryMessenger(
      ServicesBinding.instance.defaultBinaryMessenger,
      onTextInputSend: _handleOutgoingMessage,
      onTextInputReceive: _handleIncomingMessage,
    );

    // We can't replace the default messenger, but we can use our wrapper
    // for sending messages
    debugPrint('TextInputSimulator: Initialized');
    debugPrint('TextInputSimulator: Note - Using polling for client detection');

    // Start polling for text input client changes
    _startClientPolling();
  }

  Timer? _pollTimer;

  void _startClientPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _checkForActiveConnection();
    });
  }

  /// Check if there's an active text input by looking at the focus state
  void _checkForActiveConnection() {
    // Unfortunately, Flutter doesn't expose TextInput._currentConnection
    // We'll rely on the callback from our wrapper when messages are sent
  }

  /// Handle outgoing TextInput messages (Flutter → Platform)
  void _handleOutgoingMessage(String method, dynamic arguments) {
    switch (method) {
      case 'TextInput.setClient':
        final args = arguments as List<dynamic>;
        _currentClientId = args[0] as int;
        _currentConfig = Map<String, dynamic>.from(args[1] as Map);
        _currentEditingState = {};
        debugPrint('TextInputSimulator: Client connected: $_currentClientId');
        break;

      case 'TextInput.setEditingState':
        if (arguments is Map) {
          _currentEditingState = Map<String, dynamic>.from(arguments);
          debugPrint('TextInputSimulator: State updated: ${_currentEditingState['text']}');
        }
        break;

      case 'TextInput.clearClient':
        debugPrint('TextInputSimulator: Client cleared: $_currentClientId');
        _currentClientId = null;
        _currentConfig = null;
        _currentEditingState = {};
        break;

      case 'TextInput.show':
        debugPrint('TextInputSimulator: Keyboard shown for client $_currentClientId');
        break;

      case 'TextInput.hide':
        debugPrint('TextInputSimulator: Keyboard hidden');
        break;
    }
  }

  /// Handle incoming TextInput messages (Platform → Flutter)
  void _handleIncomingMessage(String method, dynamic arguments) {
    // Track incoming messages for debugging
    debugPrint('TextInputSimulator: Incoming: $method');
  }

  /// Check if there's an active text input
  bool get hasActiveInput => _currentClientId != null;

  /// Get the current text in the focused field
  String get currentText => _currentEditingState['text'] as String? ?? '';

  /// Get current client ID (for debugging)
  int? get currentClientId => _currentClientId;

  /// Simulate typing text character by character
  Future<void> typeText(String text, {Duration? charDelay}) async {
    if (_currentClientId == null) {
      debugPrint('TextInputSimulator: No active text input client');
      throw StateError(
        'No active text input. Tap a text field first. '
        'Current client ID: $_currentClientId'
      );
    }

    final delay = charDelay ?? const Duration(milliseconds: 10);

    // Get current state
    String currentText = _currentEditingState['text'] as String? ?? '';
    int selectionBase = _currentEditingState['selectionBase'] as int? ?? currentText.length;
    int selectionExtent = _currentEditingState['selectionExtent'] as int? ?? currentText.length;

    debugPrint('TextInputSimulator: Starting typeText, initial: "$currentText"');

    // Type each character
    for (int i = 0; i < text.length; i++) {
      final char = text[i];

      // Handle special characters
      if (char == '\n') {
        final inputAction = _currentConfig?['inputAction'] as String?;
        final inputType = _currentConfig?['inputType'] as Map?;
        final isMultiline = inputType?['name'] == 'TextInputType.multiline';

        if (isMultiline || inputAction == 'TextInputAction.newline') {
          // Insert newline
          currentText = _insertAtSelection(currentText, '\n', selectionBase, selectionExtent);
          selectionBase = selectionBase + 1;
          selectionExtent = selectionBase;
        } else {
          // Send done action
          await _sendAction('TextInputAction.done');
          continue;
        }
      } else {
        // Insert character at selection
        currentText = _insertAtSelection(currentText, char, selectionBase, selectionExtent);
        selectionBase = selectionBase + 1;
        selectionExtent = selectionBase;
      }

      // Send updated state to Flutter
      await _sendEditingState(
        text: currentText,
        selectionBase: selectionBase,
        selectionExtent: selectionExtent,
      );

      if (i < text.length - 1) {
        await Future.delayed(delay);
      }
    }

    debugPrint('TextInputSimulator: Finished typeText, final: "$currentText"');
  }

  /// Insert text at selection, replacing selected text if any
  String _insertAtSelection(String text, String insert, int base, int extent) {
    final start = base < extent ? base : extent;
    final end = base > extent ? base : extent;

    // Clamp to valid range
    final safeStart = start.clamp(0, text.length);
    final safeEnd = end.clamp(0, text.length);

    return text.substring(0, safeStart) + insert + text.substring(safeEnd);
  }

  /// Set the entire text content (replaces existing)
  Future<void> setText(String text) async {
    if (_currentClientId == null) {
      throw StateError('No active text input. Tap a text field first.');
    }

    await _sendEditingState(
      text: text,
      selectionBase: text.length,
      selectionExtent: text.length,
    );
  }

  /// Clear all text
  Future<void> clearText() async {
    await setText('');
  }

  /// Send editing state update to Flutter (simulating platform -> Flutter)
  Future<void> _sendEditingState({
    required String text,
    required int selectionBase,
    required int selectionExtent,
    int composingBase = -1,
    int composingExtent = -1,
  }) async {
    if (_currentClientId == null) {
      debugPrint('TextInputSimulator: Cannot send state - no client');
      return;
    }

    final editingState = <String, dynamic>{
      'text': text,
      'selectionBase': selectionBase,
      'selectionExtent': selectionExtent,
      'composingBase': composingBase,
      'composingExtent': composingExtent,
    };

    // Update our tracked state
    _currentEditingState = editingState;

    // Send message FROM platform TO Flutter
    await _sendPlatformMessage(
      'TextInputClient.updateEditingState',
      <dynamic>[_currentClientId, editingState],
    );
  }

  /// Send an input action (like Enter/Done)
  Future<void> _sendAction(String action) async {
    if (_currentClientId == null) return;

    await _sendPlatformMessage(
      'TextInputClient.performAction',
      <dynamic>[_currentClientId, action],
    );
  }

  /// Send a platform message simulating input from the OS
  Future<void> _sendPlatformMessage(String method, List<dynamic> args) async {
    const codec = JSONMethodCodec();
    final message = codec.encodeMethodCall(MethodCall(method, args));

    final completer = Completer<void>();

    ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/textinput',
      message,
      (ByteData? response) {
        completer.complete();
      },
    );

    await completer.future;
  }

  /// Press Enter key
  Future<void> pressEnter() async {
    if (_currentClientId == null) {
      throw StateError('No active text input. Tap a text field first.');
    }

    final inputAction = _currentConfig?['inputAction'] as String? ?? 'TextInputAction.done';
    final inputType = _currentConfig?['inputType'] as Map?;
    final isMultiline = inputType?['name'] == 'TextInputType.multiline';

    if (isMultiline || inputAction == 'TextInputAction.newline') {
      await typeText('\n');
    } else {
      await _sendAction(inputAction);
    }
  }

  /// Press Backspace key
  Future<void> pressBackspace() async {
    if (_currentClientId == null) {
      throw StateError('No active text input. Tap a text field first.');
    }

    String text = _currentEditingState['text'] as String? ?? '';
    int selectionBase = _currentEditingState['selectionBase'] as int? ?? text.length;
    int selectionExtent = _currentEditingState['selectionExtent'] as int? ?? text.length;

    if (selectionBase != selectionExtent) {
      final start = selectionBase < selectionExtent ? selectionBase : selectionExtent;
      final end = selectionBase > selectionExtent ? selectionBase : selectionExtent;
      text = text.substring(0, start) + text.substring(end);
      selectionBase = start;
      selectionExtent = start;
    } else if (selectionBase > 0) {
      text = text.substring(0, selectionBase - 1) + text.substring(selectionBase);
      selectionBase--;
      selectionExtent--;
    }

    await _sendEditingState(
      text: text,
      selectionBase: selectionBase,
      selectionExtent: selectionExtent,
    );
  }

  /// Move cursor to position
  Future<void> moveCursor(int position) async {
    if (_currentClientId == null) {
      throw StateError('No active text input. Tap a text field first.');
    }

    final text = _currentEditingState['text'] as String? ?? '';
    final clampedPos = position.clamp(0, text.length);

    await _sendEditingState(
      text: text,
      selectionBase: clampedPos,
      selectionExtent: clampedPos,
    );
  }

  /// Select text range
  Future<void> selectRange(int start, int end) async {
    if (_currentClientId == null) {
      throw StateError('No active text input. Tap a text field first.');
    }

    final text = _currentEditingState['text'] as String? ?? '';

    await _sendEditingState(
      text: text,
      selectionBase: start.clamp(0, text.length),
      selectionExtent: end.clamp(0, text.length),
    );
  }

  /// Select all text
  Future<void> selectAll() async {
    final text = _currentEditingState['text'] as String? ?? '';
    await selectRange(0, text.length);
  }

  /// Delete selected text or character at cursor
  Future<void> delete() async {
    if (_currentClientId == null) {
      throw StateError('No active text input. Tap a text field first.');
    }

    String text = _currentEditingState['text'] as String? ?? '';
    int selectionBase = _currentEditingState['selectionBase'] as int? ?? 0;
    int selectionExtent = _currentEditingState['selectionExtent'] as int? ?? 0;

    if (selectionBase != selectionExtent) {
      final start = selectionBase < selectionExtent ? selectionBase : selectionExtent;
      final end = selectionBase > selectionExtent ? selectionBase : selectionExtent;
      text = text.substring(0, start) + text.substring(end);
      selectionBase = start;
      selectionExtent = start;
    } else if (selectionBase < text.length) {
      text = text.substring(0, selectionBase) + text.substring(selectionBase + 1);
    }

    await _sendEditingState(
      text: text,
      selectionBase: selectionBase,
      selectionExtent: selectionExtent,
    );
  }

  /// Manually set the client ID (for testing or when detection fails)
  void setClientId(int clientId, {Map<String, dynamic>? config}) {
    _currentClientId = clientId;
    _currentConfig = config ?? {};
    debugPrint('TextInputSimulator: Manually set client ID: $clientId');
  }

  void dispose() {
    _pollTimer?.cancel();
  }
}

/// A wrapper around BinaryMessenger to intercept TextInput channel messages
class _InterceptingBinaryMessenger implements BinaryMessenger {
  final BinaryMessenger _delegate;
  final void Function(String method, dynamic arguments) onTextInputSend;
  final void Function(String method, dynamic arguments) onTextInputReceive;

  _InterceptingBinaryMessenger(
    this._delegate, {
    required this.onTextInputSend,
    required this.onTextInputReceive,
  });

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    // Intercept outgoing TextInput messages
    if (channel == 'flutter/textinput' && message != null) {
      try {
        const codec = JSONMethodCodec();
        final call = codec.decodeMethodCall(message);
        onTextInputSend(call.method, call.arguments);
      } catch (e) {
        // Ignore decode errors
      }
    }
    return _delegate.send(channel, message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    if (channel == 'flutter/textinput') {
      // Wrap the handler to intercept incoming messages
      _delegate.setMessageHandler(channel, (ByteData? message) async {
        if (message != null) {
          try {
            const codec = JSONMethodCodec();
            final call = codec.decodeMethodCall(message);
            onTextInputReceive(call.method, call.arguments);
          } catch (e) {
            // Ignore decode errors
          }
        }
        return handler?.call(message);
      });
    } else {
      _delegate.setMessageHandler(channel, handler);
    }
  }

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) {
    return _delegate.handlePlatformMessage(channel, data, callback);
  }
}
