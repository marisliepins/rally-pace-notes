import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rally_pace_notes/grading.dart';
import 'package:rally_pace_notes/sprint/edit.dart';
import 'package:rally_pace_notes/sprint/models.dart';
import 'package:rally_pace_notes/sprint/recorder.dart';
import 'package:rally_pace_notes/trip.dart';

const cfg = GradeConfig(anchors: [10, 25, 45, 90, 120, 180]);
String label(double m) => m >= 70 ? 'SUPER LONG' : (m >= 50 ? 'LONG' : '');
const double mPerDeg = 6371008.8 * math.pi / 180;

List<Note> two() => [
      Note(at: 100, length: 20, call: 'L5'),
      Note(at: 200, length: 30, call: 'R4'),
    ];

void main() {
  test('parse and compose a call', () {
    final p = parseCall('L4+ long caution')!;
    expect([p.dir, p.grade, p.mod, p.extra], ['L', '4', '+', 'caution']);
    p.grade = '5';
    p.mod = '-';
    expect(composeCall(p, 30, label), 'L5- caution'); // 30 m: no length word
    expect(composeCall(p, 75, label), 'L5- super long caution');
    expect(parseCall('ROTER'), isNull);
  });

  test('straight before and length move the following notes', () {
    final n = two();
    var total = setStraightBefore(n, 1, 100, 300); // was 80
    expect(n[1].at, 220);
    expect(total, 320);
    total = setLength(n, 0, 40, total); // +20
    expect(n[0].length, 40);
    expect(n[1].at, 240);
    expect(total, 340);
    expect(setStraightBefore(n, 0, -50, total), 240); // never below 0
    expect(n[0].at, 0);
  });

  test('merge, split, insert, delete', () {
    final n = [Note(at: 100, length: 10, call: 'R3'), Note(at: 115, length: 60, call: 'L2 long')];
    expect(mergeWithNext(n, 0), isTrue);
    expect(n.length, 1);
    expect(n[0].text, 'R3L2');
    expect(n[0].group, isTrue);
    expect(n[0].length, 75);
    final corners = const [CornerRec(100, 10, -50), CornerRec(115, 60, 25)];
    expect(splitNote(n, 0, corners, cfg, label), isTrue);
    expect(n.map((x) => x.text).toList(), ['R3', 'L2 long']);
    final m = [Note(at: 0, length: 10, call: 'L1'), Note(at: 100, length: 10, call: 'R1')];
    final i = insertAfter(m, 0, 200);
    expect(i, 1);
    expect(m[1].at, 50); // middle of the 10..100 straight
    expect(m.length, 3);
  });

  test('which note a tap marks', () {
    final n = two();
    expect(noteIndexAt(n, 50), 0); // before the first: the first
    expect(noteIndexAt(n, 150), 0); // after note 1: the one just driven
    expect(noteIndexAt(n, 195), 1); // entering note 2
  });

  test('check drive: speaks notes, a tap marks the note just driven', () {
    const lat0 = 56.95, lon0 = 24.10;
    final ref = Session(
      id: 'ref',
      type: SessionType.car,
      name: 'Car recce 1',
      createdAt: 0,
      distance: 305,
      finish: FinishPoint(lat0 + 305 / mPerDeg, lon0, 0),
      notes: two(),
    );
    final trip = Trip();
    final r = Recorder(type: SessionType.check, reference: ref)..arm();
    final said = <String>[];
    int? marked;
    for (var k = 0; k <= 35 && r.state != RecState.finished; k++) {
      final f = Fix(lat0 + 10.0 * k / mPerDeg, lon0, 5, k == 0 ? 0 : 10, 1000.0 * k);
      trip.addFix(f);
      r.onFix(f, trip.odometer);
      final say = r.tick(
          nowMs: 1000.0 * k, odometer: trip.odometer, speed: 10, angle: 0, deadZone: 5, endBelow: 10, dt: 0.5);
      if (say != null) said.add(say);
      if (k == 14) marked = r.flagCurrent(); // at 140 m, just after the first corner
    }
    expect(said.length, 2);
    expect(marked, 0);
    expect(ref.notes[0].flagged, isTrue);
    expect(ref.notes[1].flagged, isFalse);
    expect(r.flaggedCount, 1);
    expect(r.state, RecState.finished);
    expect(r.autoFinished, isTrue);
  });
}
