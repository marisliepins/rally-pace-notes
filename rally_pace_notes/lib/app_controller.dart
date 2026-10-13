import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'bridge.dart';
import 'corner.dart';
import 'grading.dart';
import 'settings.dart';
import 'steering.dart';
import 'trip.dart';

import 'dart:math' as math;

const String appVersion = '0.5';

/// Colour of the message banner on the drive screen.
enum FlashKind { info, ok, bad }

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
  FlashKind eventKind = FlashKind.info;
  int eventMs = 1800;

  /// Whether saved settings were found on the phone at start.
  bool loadedFromPhone = false;
  bool _announced = false;

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
        loadedFromPhone = true;
      } catch (_) {}
    }
    steering.trim = settings.zeroTrim;
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
        stationary: parked,
      );
    }
    for (final f in Bridge.drainFixes()) {
      trip.addFix(f);
    }
    if (steering.locked) {
      corner.update(
        angle: angle,
        deadZone: settings.deadZone,
        endBelow: math.max(settings.deadZone, settings.anchors.first),
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
    if (!_announced && status['started'] == true) {
      _announced = true;
      _announceStart();
    }
    notifyListeners();
  }

  /// GPS positively says the car is (nearly) standing still.
  bool get parked {
    final v = trip.speed;
    final at = trip.lastFixAt;
    if (v == null || at == null) return false;
    return v < 1.5 && DateTime.now().difference(at).inSeconds < 5;
  }

  String get anglesText => settings.anchors.map((a) => a.round()).join(' / ');

  /// Shown once after TAP TO START, so every session shows whether the
  /// saved settings were kept.
  void _announceStart() {
    final home = status['homeScreen'] == true;
    final at = (status['savedAt'] ?? '').toString();
    if (loadedFromPhone) {
      flash('YOUR SETTINGS LOADED${at.isEmpty ? '' : ' (saved $at)'} · $anglesText°',
          kind: FlashKind.ok, ms: 5000);
    } else {
      flash(
          'NO SAVED SETTINGS · using defaults'
          '${home ? '' : ' · open the app from the Home Screen icon to keep settings'}',
          kind: FlashKind.bad,
          ms: 6000);
    }
  }

  void flash(String text, {FlashKind kind = FlashKind.info, int ms = 1800}) {
    eventText = text;
    eventAt = DateTime.now();
    eventKind = kind;
    eventMs = ms;
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

  /// ZERO: fine-tune straight ahead. Saved, so the next start begins from it.
  void setZero() {
    steering.setZero();
    final t = steering.trimFromLandscape;
    if (t.abs() <= 30) {
      settings.zeroTrim = t;
      final err = Bridge.save(jsonEncode(settings.toJson()));
      if (err == null) {
        flash('✓ ZERO SET AND SAVED', kind: FlashKind.ok, ms: 2500);
      } else {
        flash('ZERO SET · NOT SAVED ($err)', kind: FlashKind.bad, ms: 5000);
      }
    } else {
      flash('ZERO SET for now · not saved (more than 30° from landscape)',
          kind: FlashKind.bad, ms: 4000);
    }
    notifyListeners();
  }

  /// Applies and stores settings; the drive screen shows the result.
  void saveSettings(Settings s) {
    settings = s;
    final err = Bridge.save(jsonEncode(s.toJson()));
    final home = status['homeScreen'] == true;
    if (err == null) {
      flash(
          '✓ SETTINGS SAVED · $anglesText°'
          '${home ? '' : ' · Safari tab: may be lost if Private'}',
          kind: home ? FlashKind.ok : FlashKind.info,
          ms: 4000);
    } else {
      flash('SETTINGS NOT SAVED ($err) · used until the app closes',
          kind: FlashKind.bad, ms: 6000);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
