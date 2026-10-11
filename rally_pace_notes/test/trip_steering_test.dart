import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rally_pace_notes/corner.dart';
import 'package:rally_pace_notes/steering.dart';
import 'package:rally_pace_notes/trip.dart';

const double mPerDeg = 6371008.8 * math.pi / 180;
const double g = 9.81;

/// Gravity components for a phone rotated [deg] degrees (positive = left).
List<double> grav(double deg) {
  final th = deg * math.pi / 180;
  return [g * math.cos(th), -g * math.sin(th)];
}

void feed(SteeringEstimator s, double deg, List<double>? gyro) {
  final v = grav(deg);
  s.update(gx: v[0], gy: v[1], gyroDelta: gyro, dt: 0.02, useGyro: true, tau: 0.8);
}

void main() {
  test('trip: distance, short reset, total reset, odometer', () {
    final t = Trip();
    t.addFix(const Fix(56.95, 24.10, 5, 10, 0));
    t.addFix(const Fix(56.95 + 100 / mPerDeg, 24.10, 5, 10, 10000));
    expect(t.total, closeTo(100, 0.5));
    expect(t.segment, closeTo(100, 0.5));
    t.resetSegment();
    expect(t.segment, 0);
    expect(t.lastSegment, closeTo(100, 0.5));
    t.addFix(const Fix(56.95 + 150 / mPerDeg, 24.10, 5, 10, 15000));
    expect(t.segment, closeTo(50, 0.5));
    expect(t.total, closeTo(150, 0.5));
    t.resetAll();
    expect(t.total, 0);
    expect(t.segment, 0);
    expect(t.odometer, closeTo(150, 0.5)); // odometer is never reset
  });

  test('trip: stationary GPS jitter is ignored, bad accuracy ignored', () {
    final t = Trip();
    t.addFix(const Fix(56.95, 24.10, 5, 0, 0));
    t.addFix(const Fix(56.95 + 8 / mPerDeg, 24.10, 5, 0, 1000));
    t.addFix(const Fix(56.95 + 500 / mPerDeg, 24.10, 80, 10, 2000));
    expect(t.total, 0);
  });

  test('corner: peak, length, end after straight delay', () {
    final c = CornerTracker();
    var odo = 0.0;
    CornerResult? done;
    final angles = <double>[0, 3, 8, 20, 45, 52, 40, 10, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    for (final a in angles) {
      done = c.update(angle: a, deadZone: 5, odometer: odo, dt: 0.1) ?? done;
      if (c.active) expect(c.peak, greaterThanOrEqualTo(8));
      odo += 5;
    }
    expect(done, isNotNull);
    expect(done!.peak, 52);
    // starts at the 8° sample (odo 10), ends 0.4 s after returning straight
    expect(done.length, greaterThan(30));
    expect(done.length, lessThan(60));
    expect(c.active, isFalse);
    expect(c.last, same(done));
  });

  test('corner: quick switch left to right starts a new corner', () {
    final c = CornerTracker();
    c.update(angle: 30, deadZone: 5, odometer: 0, dt: 0.1);
    c.update(angle: 2, deadZone: 5, odometer: 10, dt: 0.1);
    final first = c.update(angle: -25, deadZone: 5, odometer: 20, dt: 0.1);
    expect(first, isNotNull);
    expect(first!.peak, 30);
    expect(first.length, 20);
    expect(c.active, isTrue);
    expect(c.peak, -25);
  });

  test('steering: gravity + gyro, axis learned, 90° left', () {
    final s = SteeringEstimator();
    const steps = 150;
    feed(s, 0, null);
    for (var i = 1; i <= steps; i++) {
      feed(s, 90.0 * i / steps, [0, 0, -90.0 / steps]);
    }
    for (var i = 0; i < 100; i++) {
      feed(s, 90, [0, 0, 0]);
    }
    expect(s.angle(), closeTo(90, 2));
    expect(s.gyroAxis, 2);
    expect(s.angle(invert: true), closeTo(-90, 2));
    s.setZero();
    expect(s.angle(), closeTo(0, 0.01));
  });

  test('steering: holds the angle in a long corner despite sideways force', () {
    final s = SteeringEstimator();
    feed(s, 0, null);
    // learn the gyro axis: wheel to 90° and back
    for (var i = 1; i <= 30; i++) {
      feed(s, 3.0 * i, [0, 0, -3]);
    }
    for (var i = 1; i <= 30; i++) {
      feed(s, 90 - 3.0 * i, [0, 0, 3]);
    }
    for (var i = 0; i < 50; i++) {
      feed(s, 0, [0, 0, 0]);
    }
    // turn in to 45°
    for (var i = 1; i <= 15; i++) {
      feed(s, 3.0 * i, [0, 0, -3]);
    }
    for (var i = 0; i < 25; i++) {
      feed(s, 45, [0, 0, 0]);
    }
    expect(s.angle(), closeTo(45, 2));
    // 3 s steady corner: gravity reads only 20° because of sideways force,
    // the car rotates 10°/s (seen on another gyro axis)
    for (var i = 0; i < 150; i++) {
      feed(s, 20, [0, 0.2, 0]);
    }
    expect(s.gravityPaused, isTrue);
    // without the pause it would sink to ~21°; with it only a slow 20 s pull
    expect(s.angle(), closeTo(45, 5));
  });

  test('steering: keeps counting past 180°', () {
    final s = SteeringEstimator();
    s.update(gx: g, gy: 0, dt: 0.02, useGyro: false, tau: 0.8);
    for (var deg = 5; deg <= 270; deg += 5) {
      final v = grav(deg.toDouble());
      s.update(gx: v[0], gy: v[1], dt: 0.02, useGyro: false, tau: 0.8);
    }
    for (var i = 0; i < 100; i++) {
      s.update(gx: 0, gy: g, dt: 0.02, useGyro: false, tau: 0.8);
    }
    expect(s.angle(), closeTo(270, 1));
  });
}
