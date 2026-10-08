/// Detects corners from the steering angle: a corner starts when the wheel
/// leaves the straight zone and ends when it has been back in the straight
/// zone for [endDelay] seconds (or when the wheel crosses to the other side).
/// Tracks the peak angle and the distance driven during the corner.
library;

class CornerResult {
  const CornerResult(this.peak, this.length);

  /// Signed angle with the largest magnitude (positive = left).
  final double peak;

  /// Distance driven from corner start to corner end, metres.
  final double length;
}

class CornerTracker {
  CornerTracker({this.endDelay = 0.4});

  final double endDelay;

  bool active = false;
  double peak = 0;
  CornerResult? last;

  double _start = 0;
  double _straightFor = 0;

  /// Live length of the current corner for the given odometer reading.
  double lengthAt(double odometer) {
    if (!active) return 0;
    final l = odometer - _start;
    return l > 0 ? l : 0;
  }

  /// Feed one sample. Returns the finished corner when one ends.
  CornerResult? update({
    required double angle,
    required double deadZone,
    required double odometer,
    required double dt,
  }) {
    final a = angle.abs();
    if (!active) {
      if (a >= deadZone) _begin(angle, odometer);
      return null;
    }
    if (a >= deadZone) {
      _straightFor = 0;
      if ((angle > 0) != (peak > 0)) {
        // Crossed straight to the other side quickly (S-bend): new corner.
        final done = _finish(odometer);
        _begin(angle, odometer);
        return done;
      }
      if (a > peak.abs()) peak = angle;
      return null;
    }
    _straightFor += dt;
    if (_straightFor >= endDelay) return _finish(odometer);
    return null;
  }

  void _begin(double angle, double odometer) {
    active = true;
    peak = angle;
    _start = odometer;
    _straightFor = 0;
  }

  CornerResult _finish(double odometer) {
    final r = CornerResult(peak, lengthAt(odometer));
    active = false;
    peak = 0;
    last = r;
    return r;
  }

  void clear() {
    active = false;
    peak = 0;
    last = null;
    _straightFor = 0;
  }
}
