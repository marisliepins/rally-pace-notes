import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rally_pace_notes/grading.dart';
import 'package:rally_pace_notes/sprint/bike.dart';
import 'package:rally_pace_notes/sprint/geo.dart';
import 'package:rally_pace_notes/sprint/models.dart';
import 'package:rally_pace_notes/sprint/recorder.dart';
import 'package:rally_pace_notes/sprint/stenogram.dart';
import 'package:rally_pace_notes/trip.dart';

const double mPerDeg = 6371008.8 * math.pi / 180;
const cfg = GradeConfig(anchors: [10, 25, 45, 90, 120, 180]);
String label(double m) => m >= 70 ? 'SUPER LONG' : (m >= 50 ? 'LONG' : '');

void main() {
  test('stenogram: corners, length labels, chicane group, text and speech', () {
    final notes = buildNotes(const [
      CornerRec(50, 30, 30), // L2+
      CornerRec(150, 60, -100), // R4+ long
      CornerRec(300, 10, -50), // chicane: R3
      CornerRec(315, 10, 25), //          L2
      CornerRec(330, 10, -92), //         R4
      CornerRec(380, 5, 3), // below the straight zone: ignored
    ], cfg, label);
    expect(notes.map((n) => n.text).toList(), ['L2+', 'R4+ long', 'R3L2R4']);
    expect(notes[2].group, isTrue);
    expect(notes[2].at, 300);
    expect(notes[2].length, 40);
    expect(stenogramText(notes, 400), 'START · 50 · L2+ · 70 · R4+ long · 90 · R3L2R4 · 60 · FINISH');
    expect(speechFor(notes, 0, 400), 'left 2 plus, 70');
    expect(speechFor(notes, 2, 400), 'right 3 left 2 right 4, 60, finish');
    notes[1].custom = 'R4 long caution';
    expect(speechFor(notes, 1, 400), 'right 4 long caution, 90');
  });

  test('stenogram: rounding and interpolation helpers', () {
    expect(roundCall(147), 150);
    expect(roundCall(32), 30);
    expect(roundCall(33), 35);
    expect(timeAtPosition([0, 1000, 2000], [0, 10, 20], 15), 1500);
    expect(timeAtPosition([0, 1000], [0, 10], 50), isNull);
    expect(minSpeedBetween([0, 10, 20, 30], [9, 5, 7, 9], 5, 25), 5);
  });

  test('announcer: speaks lead time before a corner, never later than 25 m', () {
    final notes = [Note(at: 200, length: 20, call: 'L3'), Note(at: 300, length: 20, call: 'R2')];
    final a = Announcer(notes, 400);
    expect(a.update(pos: 100, speed: 20, lead: 4), isNull); // 100 m away, trigger 80 m
    expect(a.update(pos: 125, speed: 20, lead: 4), 'left 3, 80');
    expect(a.update(pos: 126, speed: 20, lead: 4), isNull); // once only
    expect(a.update(pos: 280, speed: 2, lead: 4), 'right 2, 80, finish'); // slow: 25 m rule
  });

  test('finish line: interpolated crossing time', () {
    const lat0 = 56.95, lon0 = 24.10;
    final fin = FinishPoint(lat0 + 100 / mPerDeg, lon0, 0); // 100 m north, heading north
    final d = FinishDetector(fin);
    expect(d.update(lat0 + 90 / mPerDeg, lon0, 9000), isNull);
    final t = d.update(lat0 + 110 / mPerDeg, lon0, 11000);
    expect(t, closeTo(10000, 1));
  });

  test('recorder: run starts on moving off, speaks notes, stops at the finish line', () {
    const lat0 = 56.95, lon0 = 24.10;
    final ref = Session(
      id: 'ref',
      type: SessionType.car,
      name: 'Car recce 1',
      createdAt: 0,
      distance: 205,
      finish: FinishPoint(lat0 + 205 / mPerDeg, lon0, 0),
      notes: [Note(at: 100, length: 20, call: 'L3')],
    );
    final trip = Trip();
    final r = Recorder(type: SessionType.run, reference: ref)..arm();
    final said = <String>[];
    for (var k = 0; k <= 25 && r.state != RecState.finished; k++) {
      final f = Fix(lat0 + 10.0 * k / mPerDeg, lon0, 5, k == 0 ? 0 : 10, 1000.0 * k);
      trip.addFix(f);
      r.onFix(f, trip.odometer);
      final say = r.tick(
        nowMs: 1000.0 * k,
        odometer: trip.odometer,
        speed: k == 0 ? 0 : 10,
        angle: 0,
        deadZone: 5,
        endBelow: 10,
        dt: 0.5,
        lead: 4,
      );
      if (say != null) said.add(say);
    }
    expect(r.state, RecState.finished);
    expect(r.autoFinished, isTrue);
    expect(r.elapsedMs(0), closeTo(20500, 5)); // left at 0 s, crossed at 20.5 s
    expect(said, ['left 3, 85, finish']);
    final s = r.toSession(id: 'x', name: 'Run 1', createdAt: 0, cfg: cfg, lengthLabel: label);
    expect(s.refId, 'ref');
    expect(s.notes.length, 1);
    expect(s.samples.length, greaterThan(10));
    final again = Session.fromJson(s.toJson());
    expect(again.durationMs, s.durationMs);
    expect(again.samples.length, s.samples.length);
  });

  test('recorder: recce builds notes from corners and sets the finish', () {
    const lat0 = 56.95, lon0 = 24.10;
    final trip = Trip();
    final r = Recorder(type: SessionType.car)..arm();
    // 0..30 s at 10 m/s; a left corner (40°) between 100 m and 140 m
    for (var k = 0; k <= 30; k++) {
      final f = Fix(lat0 + 10.0 * k / mPerDeg, lon0, 5, k == 0 ? 0 : 10, 1000.0 * k);
      trip.addFix(f);
      r.onFix(f, trip.odometer);
      final pos = 10.0 * k;
      for (var j = 0; j < 10; j++) {
        r.tick(
          nowMs: 1000.0 * k + 100 * j,
          odometer: trip.odometer,
          speed: 10,
          angle: (pos >= 100 && pos < 140) ? 40 : 0,
          deadZone: 5,
          endBelow: 10,
          dt: 0.1,
        );
      }
    }
    r.stop(30000);
    final s = r.toSession(id: 'c', name: 'Car recce 1', createdAt: 0, cfg: cfg, lengthLabel: label);
    expect(s.notes.length, 1);
    expect(s.notes.first.text, 'L3-');
    expect(s.notes.first.at, closeTo(100, 11));
    expect(s.finish, isNotNull);
    expect(s.finish!.bearing, closeTo(0, 1)); // drove north
    expect(s.distance, closeTo(300, 1));
  });

  test('bike: corner radius to equivalent steering angle, left/right learned', () {
    final b = BikeCornerAngle();
    // phone flat-ish: gravity along z; yaw 10°/s about it
    for (var i = 0; i < 200; i++) {
      b.updateMotion(gx: 0, gy: 0, gz: 9.81, gyroDelta: const [0.2, 0, 0], dt: 0.02);
    }
    expect(b.yawRate, closeTo(10, 0.1));
    // 5 m/s and 10°/s: radius ≈ 28.5 m → about 75° on a 15:1 car with 2.5 m wheelbase
    expect(b.rawAngle(5), closeTo(75, 2));
    expect(b.rawAngle(1), 0); // too slow to judge
    // drive a left-hand arc: course turns anticlockwise while yaw is positive
    var lat = 56.95, lon = 24.10, course = 0.0;
    b.updateFix(lat, lon, 5);
    for (var k = 0; k < 6; k++) {
      for (var i = 0; i < 50; i++) {
        b.updateMotion(gx: 0, gy: 0, gz: 9.81, gyroDelta: const [0.2, 0, 0], dt: 0.02);
      }
      course -= 10; // left
      final cr = course * math.pi / 180;
      lat += 5 * math.cos(cr) / mPerDeg;
      lon += 5 * math.sin(cr) / (mPerDeg * math.cos(lat * math.pi / 180));
      b.updateFix(lat, lon, 5);
    }
    expect(b.signLearned, isTrue);
    expect(b.sign, 1);
    expect(b.angle(5), greaterThan(0)); // left
  });
}
