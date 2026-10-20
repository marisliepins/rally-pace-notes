import 'dart:math' as math;

import 'models.dart';

const double _mPerDeg = 6371008.8 * math.pi / 180;

/// Bearing from point 1 to point 2, degrees clockwise from north (0..360).
double bearingDeg(double lat1, double lon1, double lat2, double lon2) {
  final dx = (lon2 - lon1) * math.cos(lat1 * math.pi / 180) * _mPerDeg;
  final dy = (lat2 - lat1) * _mPerDeg;
  final b = math.atan2(dx, dy) * 180 / math.pi;
  return b < 0 ? b + 360 : b;
}

/// -180..180
double wrapDeg(double x) {
  var v = x;
  while (v > 180) {
    v -= 360;
  }
  while (v < -180) {
    v += 360;
  }
  return v;
}

extension FinishGeometry on FinishPoint {
  /// Local east/north offset of a point from the finish, metres.
  List<double> _offset(double la, double lo) => [
        (lo - lon) * math.cos(lat * math.pi / 180) * _mPerDeg,
        (la - lat) * _mPerDeg,
      ];

  /// Signed distance along the direction of travel: negative before the
  /// finish line, positive after it.
  double along(double la, double lo) {
    final o = _offset(la, lo);
    final b = bearing * math.pi / 180;
    return o[0] * math.sin(b) + o[1] * math.cos(b);
  }

  double distanceTo(double la, double lo) {
    final o = _offset(la, lo);
    return math.sqrt(o[0] * o[0] + o[1] * o[1]);
  }
}

/// Finds when a run crossed the finish line between two GPS fixes.
class FinishDetector {
  FinishDetector(this.finish, {this.radius = 40});

  final FinishPoint finish;

  /// Only crossings this close to the finish point count (m).
  final double radius;

  double? _lastAlong;
  double? _lastMs;

  /// Feed each GPS fix (epoch ms). Returns the interpolated crossing time
  /// (epoch ms) when the line is crossed forwards, else null.
  double? update(double lat, double lon, double timeMs) {
    final a = finish.along(lat, lon);
    final near = finish.distanceTo(lat, lon) <= radius;
    final la = _lastAlong, lm = _lastMs;
    _lastAlong = a;
    _lastMs = timeMs;
    if (la == null || lm == null || !near) return null;
    if (la < 0 && a >= 0) {
      final f = -la / (a - la);
      return lm + f * (timeMs - lm);
    }
    return null;
  }
}
