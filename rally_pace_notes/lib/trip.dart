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

/// GPS trip meter.
///
/// * [segment]  - distance since the last short tap (reset by the driver).
/// * [total]    - distance since the last long press.
/// * [odometer] - never reset; used to measure corner length.
class Trip {
  Trip({this.maxAccuracy = 25});

  /// Fixes worse than this (metres) are ignored for distance.
  final double maxAccuracy;

  double total = 0;
  double segment = 0;
  double odometer = 0;
  double? lastSegment;
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
      odometer += d;
      _anchor = f;
    }
  }

  /// Odometer estimated for [now]: GPS updates about once a second, so the
  /// distance since the last fix is filled in from the current speed.
  double odometerAt(DateTime now) {
    final at = lastFixAt;
    final v = speed;
    if (at == null || v == null || v < 0.8) return odometer;
    final secs = now.difference(at).inMilliseconds / 1000;
    if (secs <= 0) return odometer;
    return odometer + v * math.min(secs, 1.5);
  }

  /// Short tap: remember and clear the distance since the last tap.
  void resetSegment() {
    lastSegment = segment;
    segment = 0;
  }

  /// Long press: clear total and short distance.
  void resetAll() {
    total = 0;
    segment = 0;
    lastSegment = null;
    final l = _last;
    if (l != null && l.accuracy <= maxAccuracy) _anchor = l;
  }
}
