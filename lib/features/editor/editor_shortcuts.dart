import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'editor_controller.dart';

/// Keyboard shortcuts for the editor on a computer (ports `onKey` of the web
/// app's editor.js). They never fire while a text field has focus.
class EditorShortcuts extends StatelessWidget {
  const EditorShortcuts({
    super.key,
    required this.controller,
    required this.child,
  });

  final EditorController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      debugLabel: 'editor shortcuts',
      onKeyEvent: (node, event) => handleEditorKey(controller, event)
          ? KeyEventResult.handled
          : KeyEventResult.ignored,
      child: child,
    );
  }
}

bool _typingInATextField() {
  final focus = FocusManager.instance.primaryFocus;
  final ctx = focus?.context;
  if (ctx == null) return false;
  return ctx.widget is EditableText ||
      ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// True when the key was a shortcut and has been used.
bool handleEditorKey(EditorController c, KeyEvent event) {
  if (event is KeyUpEvent) return false;
  if (_typingInATextField()) return false;
  final kb = HardwareKeyboard.instance;
  final mod = kb.isControlPressed || kb.isMetaPressed;
  final shift = kb.isShiftPressed;
  final key = event.logicalKey;
  final isDown = event is KeyDownEvent;
  if (mod) {
    if (key == LogicalKeyboardKey.keyZ) {
      if (shift) {
        c.redo();
      } else {
        c.undo();
      }
      return true;
    }
    if (key == LogicalKeyboardKey.keyY) {
      c.redo();
      return true;
    }
    if (!isDown) return false;
    if (key == LogicalKeyboardKey.keyA) {
      c.selectAll();
      return true;
    }
    if (key == LogicalKeyboardKey.keyG) {
      if (shift) {
        c.ungroupSelected();
      } else {
        c.groupSelected();
      }
      return true;
    }
    if (key == LogicalKeyboardKey.keyD && c.sel.isNotEmpty) {
      c.duplicateSelected();
      return true;
    }
    return false;
  }
  if (c.sel.isEmpty) return false;
  if (isDown &&
      (key == LogicalKeyboardKey.delete ||
          key == LogicalKeyboardKey.backspace)) {
    c.removeSelected();
    return true;
  }
  if (isDown && key == LogicalKeyboardKey.escape) {
    c.escape();
    return true;
  }
  final step = shift ? 10.0 : 1.0;
  if (key == LogicalKeyboardKey.arrowLeft) {
    c.nudge(-step, 0);
    return true;
  }
  if (key == LogicalKeyboardKey.arrowRight) {
    c.nudge(step, 0);
    return true;
  }
  if (key == LogicalKeyboardKey.arrowUp) {
    c.nudge(0, -step);
    return true;
  }
  if (key == LogicalKeyboardKey.arrowDown) {
    c.nudge(0, step);
    return true;
  }
  return false;
}
