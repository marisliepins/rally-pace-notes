/// Builds the stenogram (pace notes) from recorded corners, and turns notes
/// into text and speech.
library;

import '../grading.dart';
import 'models.dart';

/// Corners closer together than this (m, end of one to start of the next)
/// are one item, e.g. an artificial chicane "R3L2R4".
const double kGroupGap = 15;

/// [lengthLabel] gives "LONG", "SUPER LONG" or "" for a corner length.
List<Note> buildNotes(
  List<CornerRec> corners,
  GradeConfig cfg,
  String Function(double metres) lengthLabel, {
  double groupGap = kGroupGap,
  double minLength = 5,
}) {
  final sorted = [...corners]..sort((a, b) => a.start.compareTo(b.start));
  final notes = <Note>[];
  var group = <CornerRec>[];

  void flush() {
    if (group.isEmpty) return;
    final start = group.first.start;
    final end = group.map((c) => c.end).reduce((a, b) => a > b ? a : b);
    if (group.length == 1) {
      final c = group.first;
      final label = lengthLabel(c.length).toLowerCase();
      notes.add(Note(
        at: start,
        length: end - start,
        call: '${cfg.callFor(c.peak)}${label.isEmpty ? '' : ' $label'}',
      ));
    } else {
      notes.add(Note(
        at: start,
        length: end - start,
        call: group.map((c) => cfg.callFor(c.peak)).join(),
        group: true,
      ));
    }
    group = [];
  }

  for (final c in sorted) {
    if (cfg.gradeFor(c.peak) == null) continue; // never reached a grade
    if (c.length < minLength) continue; // a twitch, not a corner
    if (group.isNotEmpty && c.start - group.last.end > groupGap) flush();
    group.add(c);
  }
  flush();
  return notes;
}

/// Pace-note style distance: nearest 5 m below 100 m, else nearest 10 m.
int roundCall(double metres) {
  if (metres <= 0) return 0;
  if (metres < 100) return ((metres / 5).round() * 5);
  return ((metres / 10).round() * 10);
}

/// Straight distance before note [i] (from the start, or from the end of the
/// previous note).
double straightBefore(List<Note> notes, int i) {
  final prevEnd = i == 0 ? 0.0 : notes[i - 1].end;
  final d = notes[i].at - prevEnd;
  return d > 0 ? d : 0;
}

/// Straight distance after note [i] (to the next note, or to the finish).
double straightAfter(List<Note> notes, int i, double total) {
  final nextAt = i + 1 < notes.length ? notes[i + 1].at : total;
  final d = nextAt - notes[i].end;
  return d > 0 ? d : 0;
}

/// "START · 100 · L3 long · 150 · R5 long · 30 · L2 · 80 · FINISH"
String stenogramText(List<Note> notes, double total) {
  final parts = <String>['START'];
  for (var i = 0; i < notes.length; i++) {
    parts.add('${roundCall(straightBefore(notes, i))}');
    parts.add(notes[i].text);
  }
  if (notes.isNotEmpty) {
    parts.add('${roundCall(straightAfter(notes, notes.length - 1, total))}');
  } else if (total > 0) {
    parts.add('${roundCall(total)}');
  }
  parts.add('FINISH');
  return parts.join(' · ');
}

final RegExp _cornerToken = RegExp(r'([LR])(\d)([+-]?)');

/// Text for speech: "L3- long" -> "left 3 minus long".
String spokenCall(String text) {
  final s = text.replaceAllMapped(_cornerToken, (m) {
    final dir = m[1] == 'L' ? 'left' : 'right';
    final mod = switch (m[3]) { '+' => ' plus', '-' => ' minus', _ => '' };
    return ' $dir ${m[2]}$mod ';
  });
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// What is spoken for note [i]: the corner, then the straight after it.
/// "left 3 minus long, 150" / "right 3 left 2 right 4, 100" / "... finish".
String speechFor(List<Note> notes, int i, double total) {
  final call = spokenCall(notes[i].text);
  final isLast = i == notes.length - 1;
  final after = roundCall(straightAfter(notes, i, total));
  if (isLast) return '$call, $after, finish';
  return '$call, $after';
}

/// Linear interpolation: time (ms) when position [pos] was reached, or null.
double? timeAtPosition(List<int> t, List<double> p, double pos) {
  if (t.isEmpty || p.isEmpty) return null;
  if (pos <= p.first) return t.first.toDouble();
  for (var i = 1; i < p.length && i < t.length; i++) {
    if (p[i] >= pos) {
      final p0 = p[i - 1], p1 = p[i];
      if (p1 == p0) return t[i].toDouble();
      final f = (pos - p0) / (p1 - p0);
      return t[i - 1] + f * (t[i] - t[i - 1]);
    }
  }
  return null; // never reached
}

/// Speed (m/s) at position [pos], interpolated, or null.
double? speedAtPosition(List<double> p, List<double> v, double pos) {
  if (p.isEmpty || v.isEmpty) return null;
  for (var i = 1; i < p.length && i < v.length; i++) {
    if (p[i] >= pos) {
      final p0 = p[i - 1], p1 = p[i];
      if (p1 == p0) return v[i];
      final f = ((pos - p0) / (p1 - p0)).clamp(0.0, 1.0);
      return v[i - 1] + f * (v[i] - v[i - 1]);
    }
  }
  return null;
}

/// Lowest speed (m/s) between two track positions, or null if not driven.
double? minSpeedBetween(List<double> p, List<double> v, double from, double to) {
  double? best;
  for (var i = 0; i < p.length && i < v.length; i++) {
    if (p[i] >= from && p[i] <= to) {
      if (best == null || v[i] < best) best = v[i];
    }
  }
  return best;
}
