import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rally_pace_notes/steering.dart';
import 'package:rally_pace_notes/trip.dart';

void main() {
  const mPerDeg = 6371008.8 * math.pi / 180;

  test('trip: straight then corner segments', () {
    final t = Trip();
    t.addFix(const Fix(56.95, 24.10, 5, 10, 0));
    t.addFix(const Fix(56.95 + 100 / mPerDeg, 24.10, 5, 10, 10000));
    expect(t.total, closeTo(100, 0.5));
    t.next(); // corner starts
    expect(t.lastStraight, closeTo(100, 0.5));
    expect(t.inCorner, isTrue);
    t.addFix(const Fix(56.95 + 150 / mPerDeg, 24.10, 5, 10, 15000));
    t.next(); // corner ends
    expect(t.lastCorner, closeTo(50, 0.5));
    expect(t.inCorner, isFalse);
    expect(t.total, closeTo(150, 0.5));
    t.resetAll();
    expect(t.total, 0);
    expect(t.lastCorner, isNull);
  });

  test('trip: stationary GPS jitter is ignored, bad accuracy ignored', () {
    final t = Trip();
    t.addFix(const Fix(56.95, 24.10, 5, 0, 0));
    t.addFix(const Fix(56.95 + 8 / mPerDeg, 24.10, 5, 0, 1000));
    t.addFix(const Fix(56.95 + 500 / mPerDeg, 24.10, 80, 10, 2000));
    expect(t.total, 0);
  });

  test('steering: gravity + gyro, axis learned, 90° left', () {
    final s = SteeringEstimator();
    const g = 9.81;
    const steps = 150;
    const dt = 0.02;
    // first sample = straight ahead
    s.update(gx: g, gy: 0, dt: dt, useGyro: true, tau: 0.8);
    for (var i = 1; i <= steps; i++) {
      final th = 90.0 * i / steps * math.pi / 180;
      // phone rotates counter-clockwise; gyro reports it on gamma with a minus sign
      s.update(
        gx: g * math.cos(th),
        gy: -g * math.sin(th),
        gyroDelta: [0, 0, -90.0 / steps],
        dt: dt,
        useGyro: true,
        tau: 0.8,
      );
    }
    for (var i = 0; i < 100; i++) {
      s.update(gx: 0, gy: -g, gyroDelta: [0, 0, 0], dt: dt, useGyro: true, tau: 0.8);
    }
    expect(s.angle(), closeTo(90, 2));
    expect(s.gyroAxis, 2);
    expect(s.angle(invert: true), closeTo(-90, 2));
    s.setZero();
    expect(s.angle(), closeTo(0, 0.01));
  });

  test('steering: keeps counting past 180°', () {
    final s = SteeringEstimator();
    const g = 9.81;
    s.update(gx: g, gy: 0, dt: 0.02, useGyro: false, tau: 0.8);
    for (var deg = 5; deg <= 270; deg += 5) {
      final th = deg * math.pi / 180;
      s.update(gx: g * math.cos(th), gy: -g * math.sin(th), dt: 0.02, useGyro: false, tau: 0.8);
    }
    for (var i = 0; i < 100; i++) {
      s.update(gx: 0, gy: g, dt: 0.02, useGyro: false, tau: 0.8);
    }
    expect(s.angle(), closeTo(270, 1));
  });
}
