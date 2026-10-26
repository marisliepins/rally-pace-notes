import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'bridge.dart';
import 'corner.dart';
import 'grading.dart';
import 'settings.dart';
import 'sprint/bike.dart';
import 'sprint/models.dart';
import 'sprint/recorder.dart';
import 'sprint/stenogram.dart';
import 'sprint/store.dart';
import 'steering.dart';
import 'trip.dart';

import 'dart:math' as math;

const String appVersion = '0.7';

/// Colour of the message banner on the drive screen.
enum FlashKind { info, ok, bad }

/// Polls the sensors ~50 times a second and owns all live state.
class AppController extends ChangeNotifier {
  Settings settings = Settings();
  final SteeringEstimator steering = SteeringEstimator();
  final Trip trip = Trip();
  final CornerTracker corner = CornerTracker();

  // Sprint mode
  final SprintStore sprint = SprintStore();
  final BikeCornerAngle bike = BikeCornerAngle();
  Recorder? recorder;

  /// Result of the last finished recording (for the record screen).
  Session? lastSession;
  String? lastSaveError;

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
    sprint.load();
    applySprintPrefs();
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
      bike.updateMotion(gx: m.gx, gy: m.gy, gz: m.gz, gyroDelta: gyroDelta, dt: dt);
    }
    for (final f in Bridge.drainFixes()) {
      trip.addFix(f);
      bike.updateFix(f.lat, f.lon, f.speed);
      recorder?.onFix(f, trip.odometer);
    }
    _tickRecorder(now, tickDt);
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
    final rec = recorder;
    if (rec != null && rec.type == SessionType.check) {
      // Check drive: the remote's main button marks a wrong note.
      if (keys.any(_shortResetKeys.contains)) flagCurrentNote();
    } else if (driveActive) {
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

  // ------------------------------------------------------------ sprint

  void applySprintPrefs() {
    bike.steeringRatio = sprint.prefs.steeringRatio;
    bike.wheelbase = sprint.prefs.wheelbase;
  }

  double get speedNow => trip.speed ?? 0;

  /// Angle used for corners while recording: steering (car) or the bike's
  /// equivalent angle (raw sign; corrected when the session is saved).
  double _recordAngle(Recorder r) =>
      r.type == SessionType.bike ? bike.rawAngle(speedNow) : angle;

  /// Live angle to show on the record screen (positive = left).
  double get recordDisplayAngle {
    final r = recorder;
    if (r != null && r.type == SessionType.bike) return bike.angle(speedNow);
    return angle;
  }

  void _tickRecorder(DateTime now, double tickDt) {
    final r = recorder;
    if (r == null) return;
    final say = r.tick(
      nowMs: now.millisecondsSinceEpoch.toDouble(),
      odometer: trip.odometerAt(now),
      speed: speedNow,
      angle: _recordAngle(r),
      // Bike: start corners only from grade 1, so handlebar shake on a
      // straight doesn't count as a corner.
      deadZone: r.type == SessionType.bike
          ? math.max(settings.deadZone, settings.anchors.first)
          : settings.deadZone,
      endBelow: math.max(settings.deadZone, settings.anchors.first),
      dt: tickDt.clamp(0.0, 0.5).toDouble(),
      lead: sprint.prefs.lead,
    );
    if (say != null && sprint.prefs.speak) Bridge.speak(say, rate: sprint.prefs.rate);
    if (r.state == RecState.finished && !r.saved) {
      if (r.type == SessionType.check) {
        _finishCheck(r);
      } else {
        _saveRecording(r);
      }
    }
  }

  /// Check drive: mark the note just driven as wrong (tap or remote button).
  void flagCurrentNote() {
    final r = recorder;
    final ref = sprint.reference;
    if (r == null || ref == null) return;
    final i = r.flagCurrent();
    if (i == null) return;
    final err = sprint.save(ref);
    flash(
      err == null ? 'MARKED ${i + 1}: ${r.notes[i].text}' : 'MARK NOT SAVED: $err',
      kind: err == null ? FlashKind.info : FlashKind.bad,
      ms: 2500,
    );
    Bridge.speak('marked', rate: 1.4);
    notifyListeners();
  }

  void _finishCheck(Recorder r) {
    r.saved = true;
    final ref = sprint.reference;
    if (ref != null) lastSaveError = sprint.save(ref);
    lastSession = null;
    if (sprint.prefs.speak) {
      final n = r.flaggedCount;
      Bridge.speak('Check finished. $n ${n == 1 ? 'note' : 'notes'} marked', rate: sprint.prefs.rate);
    }
  }

  /// START on the record screen: arm a new recording. The clock starts when
  /// the vehicle moves off.
  void startRecording(SessionType type) {
    final ref = (type == SessionType.run || type == SessionType.check) ? sprint.reference : null;
    final r = Recorder(type: type, reference: ref)..arm();
    recorder = r;
    lastSession = null;
    lastSaveError = null;
    // The first speech must come from a tap on iPhone; this also confirms
    // that the headphones work.
    if (sprint.prefs.speak) {
      Bridge.speak(type == SessionType.car ? 'Recording ready' : 'Ready', rate: sprint.prefs.rate);
    }
    notifyListeners();
  }

  /// STOP: armed = cancel, running = finish now.
  void stopRecording() {
    final r = recorder;
    if (r == null) return;
    final wasArmed = r.state == RecState.armed;
    r.stop(DateTime.now().millisecondsSinceEpoch.toDouble());
    if (wasArmed) recorder = null;
    notifyListeners();
  }

  void speakTest() =>
      Bridge.speak('${spokenCall('L3- long')}, 150', rate: sprint.prefs.rate);

  void closeRecorder() {
    final r = recorder;
    if (r != null && r.state == RecState.running) return;
    recorder = null;
    Bridge.speakStop();
  }

  void _saveRecording(Recorder r) {
    r.saved = true;
    final created = r.startEpochMs ?? DateTime.now().millisecondsSinceEpoch;
    final s = r.toSession(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      name: sprint.nextName(r.type),
      createdAt: created,
      cfg: gradeConfig,
      lengthLabel: settings.lengthLabel,
      signFix: r.type == SessionType.bike ? bike.sign : 1,
    );
    final err = sprint.save(s);
    lastSession = s;
    lastSaveError = err;
    if (err == null && s.type.isRecce) {
      // The newest recce becomes the reference for the runs.
      sprint.prefs.refId = s.id;
      sprint.savePrefs();
    }
    if (sprint.prefs.speak) {
      Bridge.speak('Finish. ${spokenTime(s.durationMs)}', rate: sprint.prefs.rate);
    }
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
