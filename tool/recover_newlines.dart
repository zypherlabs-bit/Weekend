// One-off recovery tool: restores line structure to Dart sources that were
// flattened to a single line, where `//` line comments swallow all following
// code on that line.
//
// Strategy: Dart is newline-insensitive, so the only damage from flattening
// comes from line comments. This tool re-inserts a newline before each `//`
// line comment (found outside string literals) and another newline where the
// comment's text ends — detected as the first run of >= 2 spaces after the
// marker (comment line's trailing spaces + the preserved indentation of the
// code line that followed) or at a `}` token.
import 'dart:io';

void main(List<String> args) {
  for (final path in args) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('MISSING: $path');
      continue;
    }
    final text = file.readAsStringSync();
    final markers = _findCommentMarkers(text);
    if (markers.isEmpty) {
      stdout.writeln('SKIP (no comments): $path');
      continue;
    }
    file.writeAsStringSync(_recover(text, markers));
    stdout.writeln('RECOVERED ${markers.length} comments: $path');
  }
}

String _recover(String t, List<int> markers) {
  final out = StringBuffer();
  var pos = 0;
  for (var m = 0; m < markers.length; m++) {
    final p = markers[m];
    final next = m + 1 < markers.length ? markers[m + 1] : t.length;
    out.write(t.substring(pos, p)); // code before this comment
    final end = _commentEnd(t, p, next);
    out
      ..write('\n')
      ..write(t.substring(p, end)) // the comment itself
      ..write('\n');
    pos = end;
  }
  out.write(t.substring(pos));
  return out.toString();
}

class _Frame {
  final bool isString;
  final String quote;
  final bool raw;
  final bool triple;
  int braceDepth = 0;
  _Frame(this.isString, {this.quote = '', this.raw = false, this.triple = false});
}

/// Finds every `//` that starts a line comment in code context, correctly
/// skipping strings (single, double, raw, triple-quoted) and `${...}`
/// interpolation.
List<int> _findCommentMarkers(String t) {
  final markers = <int>[];
  final frames = <_Frame>[_Frame(false)];
  var i = 0;
  while (i < t.length) {
    final f = frames.last;
    final c = t[i];
    if (!f.isString) {
      if (c == '/' && i + 1 < t.length) {
        final n = t[i + 1];
        if (n == '/') {
          markers.add(i);
          // Skip the comment text entirely: prose may contain quotes that
          // must not affect string-state tracking.
          i = _commentEnd(t, i, t.length);
          continue;
        }
        if (n == '*') {
          final close = t.indexOf('*/', i + 2);
          i = close == -1 ? t.length : close + 2;
          continue;
        }
      }
      if (frames.length > 1) {
        // inside interpolation: track braces so the closing } pops us
        if (c == '{') {
          f.braceDepth++;
        } else if (c == '}') {
          if (f.braceDepth == 0) {
            frames.removeLast();
            i++;
            continue;
          }
          f.braceDepth--;
        }
      }
      if (c == '\'' || c == '"') {
        // A real string literal never follows an identifier character
        // directly; prose apostrophes (don't, user's) do. Raw strings
        // (r'...') are the exception.
        final isRaw =
            i > 1 && t[i - 1] == 'r' && !_isIdentChar(t[i - 2]);
        final prevIsIdent = i > 0 && _isIdentChar(t[i - 1]);
        if (isRaw || !prevIsIdent) {
          final isTriple = i + 2 < t.length && t[i + 1] == c && t[i + 2] == c;
          frames.add(_Frame(true, quote: c, raw: isRaw, triple: isTriple));
          i += isTriple ? 3 : 1;
          continue;
        }
      }
      i++;
      continue;
    }
    // inside a string literal
    if (!f.raw && c == r'\') {
      i += 2;
      continue;
    }
    if (f.triple) {
      if (c == f.quote && i + 2 < t.length && t[i + 1] == f.quote && t[i + 2] == f.quote) {
        frames.removeLast();
        i += 3;
        continue;
      }
      if (!f.raw && c == r'$' && i + 1 < t.length && t[i + 1] == '{') {
        frames.add(_Frame(false));
        i += 2;
        continue;
      }
      i++;
      continue;
    }
    if (c == f.quote) {
      frames.removeLast();
      i++;
      continue;
    }
    if (!f.raw && c == r'$' && i + 1 < t.length) {
      if (t[i + 1] == '{') {
        frames.add(_Frame(false));
        i += 2;
        continue;
      }
      var j = i + 1;
      while (j < t.length && _isIdentChar(t[j])) {
        j++;
      }
      if (j > i + 1) {
        i = j;
        continue;
      }
    }
    i++;
  }
  return markers;
}

/// End of a flattened line comment: the first run of >= 2 spaces after the
/// `//` (the comment line's trailing spaces plus the preserved indentation
/// of the code line that followed), or a `}` token, whichever comes first.
/// [limit] is the position of the next marker (or end of file).
int _commentEnd(String t, int start, int limit) {
  for (var j = start + 2; j < limit - 1; j++) {
    final c = t[j];
    if (c == '}') {
      return j;
    }
    if (c == ' ' && t[j + 1] == ' ') {
      return j;
    }
  }
  return limit;
}

bool _isIdentChar(String c) {
  final code = c.codeUnitAt(0);
  return (code >= 0x61 && code <= 0x7A) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x30 && code <= 0x39) ||
      code == 0x5F ||
      code == 0x24 ||
      code > 127;
}
