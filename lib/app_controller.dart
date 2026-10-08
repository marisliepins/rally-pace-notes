import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'bridge.dart';
import 'corner.dart';
import 'grading.dart';
import 'settings.dart';
import 'steering.dart';
import 'trip.dart';

const String appVersion = '0.3';

/// Polls the sensors ~50 times a second and owns all live state.
class AppController extends ChangeNotifier {
  Settings settings = Settings();
  final SteeringEstimator steering = SteeringEstimator();
  final Trip trip = Trip();
  final CornerTracker corner = CornerTracker();

  /// Keyboard / BLE-remote keys only act while the drive screen is shown.
  bool driveActive = true;
  Map<String, dynamic> status = const {};
  String eventText = '';
  DateTime eventAt = DateTime.fromMillisecondsSinceEpoch(0);

  Timer? _timer;
  int _lastCount = -1;
  List<double>? _lastGyro;
  DateTime _lastSampleAt = DateTime.now();
  DateTime _lastTickAt = DateTime.now();
  int _ticks = 0;

  static const _shortResetKeys = {
    ' ', 'Enter', 'ArrowDown', 'ArrowRight', 'PageDown',
    'MediaTrackNext', 'MediaPlayPause', 'AudioVolumeUp',
  };
  static const _resetAllKeys = {
    'ArrowUp', 'ArrowLeft', 'PageUp', 'Backspace', 'Escape',
    'MediaTrackPrevious', 'AudioVolumeDown',
  };

  void init() {
    final raw = Bridge.load();
    if (raw != null && raw.isNotEmpty) {
      try {
        settings = Settings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) => _tick());
  }

  double get angle => steering.angle(invert: settings.invertDirection);
  GradeConfig get gradeConfig => settings.gradeConfig;

  /// Angle shown as the big grade: live, or the corner peak in max-hold mode.
  double get shownAngle {
    if (!settings.peakHold) return angle;
    return corner.active ? corner.peak : 0;
  }

  double get cornerLength => corner.lengthAt(trip.odometerAt(DateTime.now()));

  void _tick() {
    final now = DateTime.now();
    final tickDt = now.difference(_lastTickAt).inMicroseconds / 1e6;
    _lastTickAt = now;

    final m = Bridge.motion();
    if (m != null && m.count != _lastCount) {
      final dt = now.difference(_lastSampleAt).inMicroseconds / 1e6;
      _lastSampleAt = now;
      List<double>? gyroDelta;
      final lastGyro = _lastGyro;
      if (m.hasGyro && lastGyro != null) {
        gyroDelta = [for (var i = 0; i < 3; i++) m.gyro[i] - lastGyro[i]];
      }
      _lastGyro = m.gyro;
      _lastCount = m.count;
      steering.update(
        gx: m.gx,
        gy: m.gy,
        gyroDelta: gyroDelta,
        dt: dt,
        useGyro: settings.useGyro,
        tau: settings.smoothing,
      );
    }
    for (final f in Bridge.drainFixes()) {
      trip.addFix(f);
    }
    if (steering.ready) {
      corner.update(
        angle: angle,
        deadZone: settings.deadZone,
        odometer: trip.odometerAt(now),
        dt: tickDt.clamp(0.0, 0.5).toDouble(),
      );
    }
    final keys = Bridge.drainKeys();
    if (driveActive) {
      for (final k in keys) {
        if (_shortResetKeys.contains(k)) {
          resetDistance();
        } else if (_resetAllKeys.contains(k)) {
          resetAll();
        }
      }
    }
    if (++_ticks % 25 == 0) status = Bridge.status();
    notifyListeners();
  }

  void flash(String text) {
    eventText = text;
    eventAt = DateTime.now();
  }

  /// Short tap: clear the distance since the last tap.
  void resetDistance() {
    final d = trip.segment;
    trip.resetSegment();
    flash('${fmtShort(d, settings.imperial)} · DISTANCE RESET');
    notifyListeners();
  }

  /// Long press: clear total, short distance and last corner.
  void resetAll() {
    trip.resetAll();
    corner.clear();
    flash('RESET · total and distance');
    notifyListeners();
  }

  void setZero() {
    steering.setZero();
    flash('ZERO SET');
    notifyListeners();
  }

  void saveSettings(Settings s) {
    settings = s;
    Bridge.save(jsonEncode(s.toJson()));
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
