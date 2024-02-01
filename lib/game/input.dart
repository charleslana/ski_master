import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/services.dart';

class Input extends Component with KeyboardHandler, HasGameReference {
  Input({Map<LogicalKeyboardKey, VoidCallback>? keyCallbacks})
      : _keyCallbacks = keyCallbacks ?? <LogicalKeyboardKey, VoidCallback>{};

  double hAxis = 0;
  bool active = false;

  bool _leftPressed = false;
  bool _rightPressed = false;
  double _leftInput = 0;
  double _rightInput = 0;
  final Map<LogicalKeyboardKey, VoidCallback> _keyCallbacks;

  static const _sensitivity = 2.0;

  @override
  void update(double dt) {
    _leftInput = lerpDouble(
      _leftInput,
      (_leftPressed && active) ? 1.5 : 0,
      _sensitivity * dt,
    )!;
    _rightInput = lerpDouble(
      _rightInput,
      (_rightPressed && active) ? 1.5 : 0,
      _sensitivity * dt,
    )!;
    hAxis = _rightInput - _leftInput;
  }

  @override
  bool onKeyEvent(RawKeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (game.paused == false) {
      _leftPressed = keysPressed.contains(LogicalKeyboardKey.keyA) ||
          keysPressed.contains(LogicalKeyboardKey.arrowLeft);
      _rightPressed = keysPressed.contains(LogicalKeyboardKey.keyD) ||
          keysPressed.contains(LogicalKeyboardKey.arrowRight);
      if (active && event is RawKeyDownEvent && event.repeat == false) {
        for (final entry in _keyCallbacks.entries) {
          if (entry.key == event.logicalKey) {
            entry.value.call();
          }
        }
      }
    }
    return super.onKeyEvent(event, keysPressed);
  }
}
