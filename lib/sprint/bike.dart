import 'dart:math' as math;

import 'geo.dart';

/// Corner sharpness for a phone on a bicycle handlebar.
///
/// A bike steers by leaning, so the handlebar angle says little. Instead
/// the phone's turning rate about the vertical (yaw, from the gyroscope
/// projected onto gravity) and the GPS speed give the corner radius:
///   radius = speed / yaw rate.
/// That radius is turned into the steering-wheel angle a car would need
/// for the same corner:
///   angle = steering ratio × atan(wheelbase / radius),
/// so the same grade table works for the bike and the car.
///
/// Left/right: the yaw sign is learned by comparing with GPS course changes.
class BikeCornerAngle {
  double steeringRatio = 15;
  double wheelbase = 2.5;

  double _yaw = 0; // smoothed yaw rate, deg/s, raw sign
  double _yawSinceFix = 0; // raw yaw turned since the last course
  double _score = 0;
  double? _lastLat, _lastLon, _lastCourse;

  /// +1 or -1: multiply raw yaw by this to get "left = positive".
  int get sign => _score >= 0 ? 1 : -1;
  bool get signLearned => _score.abs() >= 200;
  double get yawRate => _yaw;

  /// [gyroDelta]: rotation since last sample, degrees, (alpha, beta, gamma)
  /// = about the phone's (z, x, y) axes. g*: gravity, any units.
  void updateMotion({
    required double gx,
    required double gy,
    required double gz,
    required List<double>? gyroDelta,
    required double dt,
  }) {
    final g = math.sqrt(gx * gx + gy * gy + gz * gz);
    final d = dt.clamp(0.001, 0.5).toDouble();
    if (gyroDelta == null || g < 3) return;
    final yawDelta = (gyroDelta[1] * gx + gyroDelta[2] * gy + gyroDelta[0] * gz) / g;
    _yawSinceFix += yawDelta;
    final rate = yawDelta / d;
    _yaw += (rate - _yaw) * (d / (0.6 + d)); // handlebar shake: smooth 0.6 s
  }

  /// Each GPS fix: learns which yaw sign means "left".
  void updateFix(double lat, double lon, double? speed) {
    final pl = _lastLat, po = _lastLon;
    if (pl == null || po == null) {
      _lastLat = lat;
      _lastLon = lon;
      _yawSinceFix = 0;
      return;
    }
    final dx = (lon - po) * math.cos(lat * math.pi / 180) * 111195;
    final dy = (lat - pl) * 111195;
    if (math.sqrt(dx * dx + dy * dy) < 3 || (speed != null && speed < 2)) return;
    final course = bearingDeg(pl, po, lat, lon);
    final lc = _lastCourse;
    if (lc != null) {
      final dCourse = wrapDeg(course - lc); // + = turned right
      if (dCourse.abs() > 4 && _yawSinceFix.abs() > 4) {
        _score = (_score + _yawSinceFix * -dCourse).clamp(-100000.0, 100000.0).toDouble();
      }
    }
    _lastCourse = course;
    _lastLat = lat;
    _lastLon = lon;
    _yawSinceFix = 0;
  }

  /// Equivalent car steering angle with the raw (unlearned) sign.
  double rawAngle(double speed) {
    if (speed < 2) return 0;
    var w = _yaw * math.pi / 180; // rad/s
    // Leaning into the corner tilts the measured "down" by the lean angle,
    // so the gyro sees yaw × cos(lean); tan(lean) = speed × yaw / g.
    w = w * math.sqrt(1 + math.pow(speed * w / 9.81, 2));
    return steeringRatio * math.atan(wheelbase * w / speed) * 180 / math.pi;
  }

  /// Equivalent car steering angle, positive = left.
  double angle(double speed) => sign * rawAngle(speed);
}
