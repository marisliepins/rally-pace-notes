/// Editing the stenogram: grade, distances, length, delete, merge, split,
/// insert. Pure functions on the note list, so they can be tested.
library;

import '../grading.dart';
import 'models.dart';
import 'stenogram.dart';

/// A single-corner call split into parts: "L4+ long caution" ->
/// dir L, grade 4, mod +, extra "caution" (the length word comes from the
/// corner length, so it is not kept here).
class CallParts {
  CallParts(this.dir, this.grade, this.mod, this.extra);
  String dir; // 'L' or 'R'
  String grade; // '1'..'6'
  String mod; // '', '+', '-'
  String extra;

  String get base => '$dir$grade$mod';
}

final RegExp _head = RegExp(r'^\s*([LR])(\d)([+-]?)(.*)$');

CallParts? parseCall(String text) {
  final m = _head.firstMatch(text);
  if (m == null) return null;
  var rest = (m[4] ?? '').trim();
  rest = rest.replaceFirst(RegExp(r'^super\s+long\b', caseSensitive: false), '').trim();
  rest = rest.replaceFirst(RegExp(r'^long\b', caseSensitive: false), '').trim();
  return CallParts(m[1]!, m[2]!, m[3] ?? '', rest);
}

/// "L4+" + length word for [length] + extra text.
String composeCall(CallParts p, double length, String Function(double) lengthLabel) {
  final label = lengthLabel(length).toLowerCase();
  return [p.base, if (label.isNotEmpty) label, if (p.extra.trim().isNotEmpty) p.extra.trim()]
      .join(' ');
}

/// The corner part of a note without the length word, for merging:
/// "L3- long" -> "L3-", groups stay as they are.
String baseOf(Note n) {
  if (n.group) return n.text.replaceAll(' ', '');
  return parseCall(n.text)?.base ?? n.text;
}

/// Moves notes [from].. by [delta] metres.
void shiftFrom(List<Note> notes, int from, double delta) {
  for (var j = from; j < notes.length; j++) {
    notes[j].at += delta;
  }
}

/// Sets the straight before note [i]. Later notes move with it, so their
/// own straights stay the same. Returns the new total (finish) distance.
double setStraightBefore(List<Note> notes, int i, double metres, double total) {
  final v = metres < 0 ? 0.0 : metres;
  final delta = v - straightBefore(notes, i);
  shiftFrom(notes, i, delta);
  return total + delta;
}

/// Sets the length of note [i]; later notes move with its end.
/// Returns the new total distance.
double setLength(List<Note> notes, int i, double metres, double total) {
  final v = metres < 1 ? 1.0 : metres;
  final delta = v - notes[i].length;
  notes[i].length = v;
  shiftFrom(notes, i + 1, delta);
  return total + delta;
}

/// Joins note [i] with the next one into a group ("R3" + "L2" -> "R3L2").
bool mergeWithNext(List<Note> notes, int i) {
  if (i < 0 || i + 1 >= notes.length) return false;
  final a = notes[i], b = notes[i + 1];
  notes[i] = Note(
    at: a.at,
    length: b.end - a.at,
    call: '${baseOf(a)}${baseOf(b)}',
    group: true,
  );
  notes.removeAt(i + 1);
  return true;
}

/// Splits group [i] back into its single corners, using the recorded
/// corners inside it. Returns false if there is nothing to split.
bool splitNote(
  List<Note> notes,
  int i,
  List<CornerRec> corners,
  GradeConfig cfg,
  String Function(double) lengthLabel,
) {
  final n = notes[i];
  final inside = corners.where((c) => c.start >= n.at - 2 && c.start <= n.end + 2).toList();
  final parts = buildNotes(inside, cfg, lengthLabel, groupGap: -1);
  if (parts.length < 2) return false;
  notes.removeAt(i);
  notes.insertAll(i, parts);
  return true;
}

/// Adds a new corner after note [i] (or at the start when [i] is -1), in
/// the middle of the straight. Returns its index.
int insertAfter(List<Note> notes, int i, double total) {
  final start = i < 0 ? 0.0 : notes[i].end;
  final next = i + 1 < notes.length ? notes[i + 1].at : total;
  final gap = next - start;
  const len = 10.0;
  final at = gap > len + 10 ? start + (gap - len) / 2 : start + 5;
  final n = Note(at: at, length: len, call: 'L1');
  notes.insert(i + 1, n);
  return i + 1;
}

/// The note the driver has just driven or is driving at [pos] (for marking
/// a wrong note during a check drive): the last note that starts before
/// [pos] + 10 m.
int noteIndexAt(List<Note> notes, double pos) {
  var idx = 0;
  for (var j = 0; j < notes.length; j++) {
    if (notes[j].at <= pos + 10) idx = j;
  }
  return idx;
}
