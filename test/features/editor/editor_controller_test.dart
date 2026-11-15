import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pio_photo_layout/core/model/layout_doc.dart';
import 'package:pio_photo_layout/core/render/layout_prep.dart';
import 'package:pio_photo_layout/features/editor/editor_controller.dart';
import 'package:pio_photo_layout/features/editor/editor_geometry.dart';

EditorController make({List<String>? saves, Duration saveDelay = const Duration(milliseconds: 500)}) =>
    EditorController(
      doc: LayoutDoc.blank('Test'),
      prep: LayoutPrep(),
      onSave: (d) async => saves?.add(d.name),
      saveDelay: saveDelay,
    );

ShapePreset shape(String label) => kShapePresets.firstWhere((p) => p.label == label);
TextPreset text(String label) => kTextPresets.firstWhere((p) => p.label == label);

void drag(EditorController c, Offset from, Offset to) {
  c.beginDrag(from);
  c.updateDrag(Offset.lerp(from, to, 0.5)!);
  c.updateDrag(to);
  c.endDrag();
}

void main() {
  test('a text moved down by 500 re-pins to the bottom; undo and redo', () {
    final c = make();
    expect(c.frameH, 800);
    final el = c.addText(text('Body text'));
    expect(c.sel, [el.id]);
    expect(el.pin, Pin.center);
    final b0 = c.boxOfEl(el);
    drag(c, b0.center, b0.center + const Offset(30, 500));
    final b1 = c.boxOfEl(el);
    expect(b1.left, closeTo(b0.left + 30, 0.01));
    expect(b1.top, closeTo(b0.top + 500, 0.01));
    expect(el.pin, Pin.bottom);

    c.undo();
    final back = c.byId(el.id)!;
    expect(c.boxOfEl(back).left, closeTo(b0.left, 0.01));
    expect(c.boxOfEl(back).top, closeTo(b0.top, 0.01));
    expect(back.pin, Pin.center);
    c.redo();
    final again = c.byId(el.id)!;
    expect(c.boxOfEl(again).top, closeTo(b1.top, 0.01));
    expect(again.pin, Pin.bottom);
  });

  test('resizing a text from a corner keeps its proportions and scales the type', () {
    final c = make();
    final el = c.addText(text('Heading'));
    final b0 = c.boxOfEl(el);
    final size0 = el.size;
    final corner = c.handles().firstWhere((h) => h.kind == HandleKind.resize && h.hx == 1 && h.hy == 1);
    drag(c, corner.at, corner.at + const Offset(120, 10));
    final b1 = c.boxOfEl(el);
    expect(b1.width, greaterThan(b0.width));
    expect(b1.width / b1.height, closeTo(b0.width / b0.height, b0.width / b0.height * 0.03));
    expect(el.size, greaterThan(size0));
    expect(b1.left, closeTo(b0.left, 0.5), reason: 'the opposite corner stays put');
  });

  test('rotating by 47 degrees snaps to 45; 40 stays 40', () {
    for (final (turn, want) in [(47.0, 45.0), (40.0, 40.0)]) {
      final c = make();
      final el = c.addShape(shape('Rectangle'));
      final rot = c.handles().firstWhere((h) => h.kind == HandleKind.rotate);
      final centre = c.boxOfEl(el).center;
      final v = rot.at - centre;
      final a = turn * math.pi / 180;
      final to = centre + Offset(v.dx * math.cos(a) - v.dy * math.sin(a), v.dx * math.sin(a) + v.dy * math.cos(a));
      drag(c, rot.at, to);
      expect(el.rotation, closeTo(want, 0.05), reason: 'turned $turn');
    }
  });

  test('grouping two pieces, then dragging one moves both', () {
    final c = make();
    final a = c.addShape(shape('Rectangle'));
    final b = c.addShape(shape('Circle'));
    c.select([a.id, b.id]);
    c.groupSelected();
    expect(a.group, isNotNull);
    expect(b.group, a.group);
    c.select([]);
    final ba = c.boxOfEl(a), bb = c.boxOfEl(b);
    final onlyA = ba.topLeft + const Offset(5, 5);
    expect(c.elementAt(onlyA), same(a));
    drag(c, onlyA, onlyA + const Offset(40, 0));
    expect(c.sel.toSet(), {a.id, b.id});
    expect(c.boxOfEl(a).left, closeTo(ba.left + 40, 0.01));
    expect(c.boxOfEl(b).left, closeTo(bb.left + 40, 0.01));
  });

  test('duplicate offsets the copy and selects it', () {
    final c = make();
    final a = c.addShape(shape('Rectangle'));
    c.duplicateSelected();
    final copy = c.single!;
    expect(copy.id, isNot(a.id));
    expect(copy.name, 'Rectangle copy');
    expect(c.doc.elements.last, same(copy));
    expect(c.boxOfEl(copy).left, closeTo(c.boxOfEl(a).left + 20, 0.01));
    expect(c.boxOfEl(copy).top, closeTo(c.boxOfEl(a).top + 20, 0.01));
  });

  test('delete, then undo brings the piece back in the same layer', () {
    final c = make();
    final a = c.addShape(shape('Rectangle'));
    final b = c.addShape(shape('Circle'));
    final t = c.addText(text('Body text'));
    c.select([b.id]);
    c.removeSelected();
    expect(c.doc.elements.map((e) => e.id), [a.id, t.id]);
    c.undo();
    expect(c.doc.elements.map((e) => e.id), [a.id, b.id, t.id]);
  });

  test('hit testing picks the top piece and skips locked and hidden ones', () {
    final c = make();
    final a = c.addShape(shape('Rectangle'));
    final b = c.addShape(shape('Circle'));
    final p = c.boxOfEl(b).center;
    expect(c.elementAt(p), same(b));
    c.change(() => b.locked = true);
    expect(c.elementAt(p), same(a));
    c.change(() => a.visible = false);
    expect(c.elementAt(p), isNull);
  });

  test('history stops growing past its limit', () {
    final c = make();
    final a = c.addShape(shape('Rectangle'));
    for (var i = 0; i < 140; i++) {
      c.change(() => a.x += 1, 'step $i');
    }
    expect(c.historyLength, EditorController.historyLimit);
  });

  test('a slider drag (one key) is one undo step', () {
    final c = make();
    final a = c.addShape(shape('Rectangle'));
    final before = c.historyLength;
    for (var i = 0; i < 50; i++) {
      c.change(() => a.opacity = 1 - i / 100, '${a.id}:opacity');
    }
    expect(c.historyLength, before + 1);
    c.undo();
    expect(c.byId(a.id)!.opacity, 1);
  });

  test('autosave calls the store once after a burst of changes', () async {
    final saves = <String>[];
    final c = make(saves: saves, saveDelay: const Duration(milliseconds: 40));
    final a = c.addShape(shape('Rectangle'));
    for (var i = 0; i < 6; i++) {
      c.change(() => a.x += 5);
    }
    expect(saves, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(saves, ['Test']);
    await c.close();
    expect(saves.length, 2, reason: 'closing writes the layout once more');
  });
}
