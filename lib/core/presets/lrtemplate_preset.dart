// Reads an `.lrtemplate` file: a Lua-style table
//   s = { id = "...", title = "...", value = { settings = { ... } } }
// with strings, numbers, booleans, nested tables, and flat number lists for
// curves. Anything it cannot read gives null, never an exception.

import 'crs_map.dart';

class _Table {
  final Map<String, Object?> named = {};
  final List<Object?> items = [];
}

class _Lua {
  _Lua(this.s);
  final String s;
  int i = 0;

  Never fail() => throw const FormatException('lrtemplate');

  void skip() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0xFEFF) {
        i++;
      } else if (s.startsWith('--', i)) {
        while (i < s.length && s.codeUnitAt(i) != 0x0A) {
          i++;
        }
      } else {
        break;
      }
    }
  }

  bool eat(String ch) {
    skip();
    if (i < s.length && s[i] == ch) {
      i++;
      return true;
    }
    return false;
  }

  static bool _idStart(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;
  static bool _digit(int c) => c >= 0x30 && c <= 0x39;

  String ident() {
    skip();
    final start = i;
    while (i < s.length &&
        (_idStart(s.codeUnitAt(i)) || _digit(s.codeUnitAt(i)))) {
      i++;
    }
    if (i == start) fail();
    return s.substring(start, i);
  }

  /// Parses `name = { ... }` at the start of the file and returns the table.
  _Table root() {
    skip();
    if (i < s.length && _idStart(s.codeUnitAt(i))) {
      ident();
      if (!eat('=')) fail();
    }
    final v = value(0);
    if (v is! _Table) fail();
    return v;
  }

  Object? value(int depth) {
    if (depth > 40) fail();
    skip();
    if (i >= s.length) fail();
    final c = s.codeUnitAt(i);
    if (c == 0x7B) return table(depth);
    if (c == 0x22 || c == 0x27) return string(c);
    if (c == 0x2D || c == 0x2B || _digit(c) || c == 0x2E) return number();
    if (_idStart(c)) {
      final w = ident();
      if (w == 'true') return true;
      if (w == 'false') return false;
      if (w == 'nil') return null;
      fail();
    }
    fail();
  }

  String string(int quote) {
    i++;
    final b = StringBuffer();
    while (i < s.length) {
      final c = s.codeUnitAt(i++);
      if (c == quote) return b.toString();
      if (c == 0x5C && i < s.length) {
        final n = s[i++];
        b.write(switch (n) {
          'n' => '\n',
          't' => '\t',
          'r' => '\r',
          _ => n,
        });
      } else {
        b.writeCharCode(c);
      }
    }
    fail();
  }

  double number() {
    final start = i;
    if (s[i] == '-' || s[i] == '+') i++;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      final isExp = c == 0x65 || c == 0x45;
      final isSign =
          (c == 0x2D || c == 0x2B) &&
          i > start &&
          (s[i - 1] == 'e' || s[i - 1] == 'E');
      if (_digit(c) || c == 0x2E || isExp || isSign) {
        i++;
      } else {
        break;
      }
    }
    final v = double.tryParse(s.substring(start, i));
    if (v == null) fail();
    return v;
  }

  _Table table(int depth) {
    i++; // {
    final t = _Table();
    while (true) {
      skip();
      if (i >= s.length) fail();
      if (s[i] == '}') {
        i++;
        return t;
      }
      if (s[i] == '[') {
        i++;
        final k = value(depth + 1);
        if (!eat(']') || !eat('=')) fail();
        t.named['$k'] = value(depth + 1);
      } else if (_idStart(s.codeUnitAt(i))) {
        final save = i;
        final name = ident();
        if (eat('=')) {
          t.named[name] = value(depth + 1);
        } else {
          i = save;
          t.items.add(value(depth + 1));
        }
      } else {
        t.items.add(value(depth + 1));
      }
      skip();
      if (i < s.length && (s[i] == ',' || s[i] == ';')) i++;
    }
  }
}

String _num(double v) =>
    v == v.roundToDouble() && v.abs() < 1e15 ? v.toInt().toString() : '$v';

void _put(CrsFields f, String name, Object? v) {
  if (v is String) {
    f.scalars[name] = v;
  } else if (v is double) {
    f.scalars[name] = _num(v);
  } else if (v is bool) {
    f.scalars[name] = v ? 'True' : 'False';
  } else if (v is _Table) {
    final items = v.items;
    if (items.isNotEmpty && items.every((e) => e is double)) {
      final nums = [for (final e in items) _num(e as double)];
      if (name.startsWith('ToneCurve')) {
        f.seqs[name] = [
          for (var k = 0; k + 1 < nums.length; k += 2)
            '${nums[k]}, ${nums[k + 1]}',
        ];
      } else {
        f.seqs[name] = [nums.join(', ')];
      }
    } else {
      f.seqs[name] = [for (final _ in items) '{}'];
    }
  }
}

/// Reads [text]; returns null if it is not a preset template.
ParsedFile? parseLrtemplate(String text) {
  final _Table root;
  try {
    root = _Lua(text).root();
  } catch (_) {
    return null;
  }
  final value = root.named['value'];
  final settings = value is _Table ? value.named['settings'] : null;
  if (settings is! _Table) return null;
  final f = CrsFields();
  settings.named.forEach((k, v) => _put(f, k, v));
  String? str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
  return ParsedFile(
    f,
    id:
        str(root.named['id']) ??
        (value is _Table ? str(value.named['uuid']) : null),
    name: str(root.named['title']) ?? str(root.named['internalName']),
  );
}
