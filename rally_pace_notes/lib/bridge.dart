// Interop with web/rally.js, which owns the browser sensor APIs
// (motion permission, GPS watch, wake lock, keyboard/BLE-remote keys).
import 'dart:convert';
import 'dart:js_interop';

import 'trip.dart';

@JS('rallyGetMotion')
external JSArray<JSNumber>? _getMotion();

@JS('rallyDrainFixes')
external JSArray<JSNumber>? _drainFixes();

@JS('rallyDrainKeys')
external JSArray<JSString>? _drainKeys();

@JS('rallyStatus')
external JSString? _status();

@JS('rallyLoad')
external JSString? _load();

@JS('rallySave')
external void _save(JSString value);

class MotionSample {
  const MotionSample(this.gx, this.gy, this.gyro, this.hasGyro, this.count);
  final double gx;
  final double gy;
  final List<double> gyro; // accumulated degrees per axis (alpha, beta, gamma)
  final bool hasGyro;
  final int count;
}

class Bridge {
  static MotionSample? motion() {
    try {
      final a = _getMotion();
      if (a == null) return null;
      final l = a.toDart.map((e) => e.toDartDouble).toList();
      if (l.length < 7) return null;
      return MotionSample(l[0], l[1], [l[2], l[3], l[4]], l[5] > 0.5, l[6].toInt());
    } catch (_) {
      return null;
    }
  }

  static List<Fix> drainFixes() {
    try {
      final a = _drainFixes();
      if (a == null) return const [];
      final l = a.toDart.map((e) => e.toDartDouble).toList();
      final out = <Fix>[];
      for (var i = 0; i + 4 < l.length; i += 5) {
        final speed = l[i + 3];
        out.add(Fix(l[i], l[i + 1], l[i + 2], speed >= 0 ? speed : null, l[i + 4]));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static List<String> drainKeys() {
    try {
      final a = _drainKeys();
      if (a == null) return const [];
      return a.toDart.map((e) => e.toDart).toList();
    } catch (_) {
      return const [];
    }
  }

  static Map<String, dynamic> status() {
    try {
      final s = _status();
      if (s == null) return const {};
      return jsonDecode(s.toDart) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  static String? load() {
    try {
      return _load()?.toDart;
    } catch (_) {
      return null;
    }
  }

  static void save(String value) {
    try {
      _save(value.toJS);
    } catch (_) {}
  }
}
