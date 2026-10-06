import 'dart:math' as math;

/// Estimates steering-wheel rotation from a phone fixed to the wheel.
///
/// * Gravity direction in the screen plane gives an absolute, drift-free angle.
/// * The gyroscope (when available) gives fast, smooth short-term motion and
///   reduces the effect of cornering forces. The gyro axis and sign are
///   learned automatically by correlating them with the gravity angle, so the
///   differences between iPhone and Android sensor conventions don't matter.
/// * Angles are unwrapped, so turning past ±180° keeps counting.
///
/// Positive angle = phone rotated counter-clockwise as seen from the driver
/// = wheel turned LEFT (can be inverted in settings).
class SteeringEstimator {
  double _grav = 0;
  double? _lastRaw;
  double _fused = 0;
  double _zero = 0;
  bool ready = false;
  final List<double> _score = [0, 0, 0];

  /// Gyro axis index (0 = alpha, 1 = beta, 2 = gamma) once learned.
  int? get gyroAxis {
    var best = 0;
    for (var k = 1; k < 3; k++) {
      if (_score[k].abs() > _score[best].abs()) best = k;
    }
    return _score[best].abs() >= 50 ? best : null;
  }

  String get gyroInfo {
    final a = gyroAxis;
    if (a == null) return 'learning (turn the wheel a bit)';
    const names = ['alpha', 'beta', 'gamma'];
    return '${names[a]} ${_score[a] >= 0 ? '+' : '-'}';
  }

  /// [gyroDelta]: rotation since last sample in degrees, per axis
  /// (alpha, beta, gamma). [dt] seconds since last sample. [tau] fusion time
  /// constant in seconds (bigger = trust gyro longer, smoother).
  void update({
    required double gx,
    required double gy,
    List<double>? gyroDelta,
    required double dt,
    required bool useGyro,
    required double tau,
  }) {
    final d = dt.clamp(0.001, 0.5).toDouble();
    final gravValid = math.sqrt(gx * gx + gy * gy) > 2.0;
    var gravDelta = 0.0;
    if (gravValid) {
      final raw = -math.atan2(gy, gx) * 180 / math.pi;
      final last = _lastRaw;
      if (last == null) {
        _lastRaw = raw;
        _grav = raw;
        _fused = raw;
        _zero = raw; // first reading = straight ahead until "Zero" is pressed
        ready = true;
        return;
      }
      gravDelta = _wrap(raw - last);
      _lastRaw = raw;
      _grav += gravDelta;
    }
    if (!ready) return;

    if (gyroDelta != null && gravValid && gravDelta.abs() > 0.2) {
      for (var k = 0; k < 3; k++) {
        _score[k] = (_score[k] + gravDelta * gyroDelta[k]).clamp(-5000.0, 5000.0).toDouble();
      }
    }

    final axis = gyroAxis;
    if (useGyro && gyroDelta != null && axis != null) {
      final step = gyroDelta[axis] * (_score[axis] >= 0 ? 1 : -1);
      final predicted = _fused + step;
      if (gravValid) {
        final w = tau / (tau + d);
        _fused = w * predicted + (1 - w) * _grav;
      } else {
        _fused = predicted;
      }
    } else if (gravValid) {
      const lp = 0.08; // light smoothing when gravity only
      _fused += (_grav - _fused) * (d / (lp + d));
    }
  }

  static double _wrap(double x) {
    var v = x;
    while (v > 180) {
      v -= 360;
    }
    while (v < -180) {
      v += 360;
    }
    return v;
  }

  double angle({bool invert = false}) => (_fused - _zero) * (invert ? -1 : 1);

  void setZero() => _zero = _fused;
}
