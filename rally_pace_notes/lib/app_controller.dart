import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'bridge.dart';
import 'grading.dart';
import 'settings.dart';
import 'steering.dart';
import 'trip.dart';

/// Polls the sensors ~50 times a second and owns all live state.
class AppController extends ChangeNotifier {
  Settings settings = Settings();
  final SteeringEstimator steering = SteeringEstimator();
  final Trip trip = Trip();

  /// Keyboard / BLE-remote keys only act while the drive screen is shown.
  bool driveActive = true;
  Map<String, dynamic> status = const {};
  String eventText = '';
  DateTime eventAt = DateTime.fromMillisecondsSinceEpoch(0);

  Timer? _timer;
  int _lastCount = -1;
  List<double>? _lastGyro;
  DateTime _lastSampleAt = DateTime.now();
  int _ticks = 0;

  static const _nextKeys = {
    ' ', 'Enter', 'ArrowDown', 'ArrowRight', 'PageDown',
    'MediaTrackNext', 'MediaPlayPause', 'AudioVolumeUp',
  };
  static const _resetKeys = {
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

  void _tick() {
    final m = Bridge.motion();
    if (m != null && m.count != _lastCount) {
      final now = DateTime.now();
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
    final keys = Bridge.drainKeys();
    if (driveActive) {
      for (final k in keys) {
        if (_nextKeys.contains(k)) {
          nextSegment();
        } else if (_resetKeys.contains(k)) {
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

  void nextSegment() {
    final wasCorner = trip.inCorner;
    final d = trip.segment;
    trip.next();
    final imp = settings.imperial;
    if (wasCorner) {
      final label = settings.lengthLabel(d);
      flash('CORNER END · ${fmtShort(d, imp)}${label.isEmpty ? '' : ' $label'}');
    } else {
      flash('CORNER START · straight ${fmtShort(d, imp)}');
    }
    notifyListeners();
  }

  void resetAll() {
    trip.resetAll();
    flash('RESET · total and corner distance');
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
