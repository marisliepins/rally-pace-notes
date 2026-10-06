import 'dart:math' as math;

class Fix {
  const Fix(this.lat, this.lon, this.accuracy, this.speed, this.timeMs);
  final double lat;
  final double lon;
  final double accuracy; // metres
  final double? speed; // m/s, null when unknown
  final double timeMs;
}

const double _earthRadius = 6371008.8;

double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = math.pi / 180;
  final dLat = (lat2 - lat1) * r;
  final dLon = (lon2 - lon1) * r;
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * r) * math.cos(lat2 * r) * math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthRadius * math.asin(math.min(1.0, math.sqrt(a)));
}

/// GPS trip meter with alternating STRAIGHT / CORNER segments.
///
/// Short tap (next): STRAIGHT -> CORNER stores the straight length,
/// CORNER -> STRAIGHT stores the corner length. Long press resets all.
class Trip {
  Trip({this.maxAccuracy = 25});

  /// Fixes worse than this (metres) are ignored for distance.
  final double maxAccuracy;

  double total = 0;
  double segment = 0;
  bool inCorner = false;
  double? lastStraight;
  double? lastCorner;
  double? speed;
  double? accuracy;
  DateTime? lastFixAt;

  Fix? _anchor;
  Fix? _last;

  void addFix(Fix f) {
    accuracy = f.accuracy;
    lastFixAt = DateTime.now();
    final prev = _last;
    double? computed;
    if (prev != null && f.timeMs > prev.timeMs) {
      computed = distanceMeters(prev.lat, prev.lon, f.lat, f.lon) /
          ((f.timeMs - prev.timeMs) / 1000);
    }
    speed = f.speed ?? computed;
    _last = f;

    if (f.accuracy > maxAccuracy) return;
    final a = _anchor;
    if (a == null) {
      _anchor = f;
      return;
    }
    final d = distanceMeters(a.lat, a.lon, f.lat, f.lon);
    final moving = f.speed == null || f.speed! > 0.8;
    final minStep = math.max(3.0, f.accuracy * 0.5);
    if (moving && d >= minStep) {
      total += d;
      segment += d;
      _anchor = f;
    }
  }

  void next() {
    if (inCorner) {
      lastCorner = segment;
    } else {
      lastStraight = segment;
    }
    inCorner = !inCorner;
    segment = 0;
  }

  void resetAll() {
    total = 0;
    segment = 0;
    inCorner = false;
    lastStraight = null;
    lastCorner = null;
    final l = _last;
    if (l != null && l.accuracy <= maxAccuracy) _anchor = l;
  }
}
