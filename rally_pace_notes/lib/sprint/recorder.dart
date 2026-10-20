import 'dart:math' as math;

import '../corner.dart';
import '../grading.dart';
import '../trip.dart';
import 'geo.dart';
import 'models.dart';
import 'stenogram.dart';

enum RecState { idle, armed, running, finished }

/// Decides when to speak each pace note: [lead] seconds before the corner at
/// the current speed, but never later than 25 m before it.
class Announcer {
  Announcer(this.notes, this.total);

  final List<Note> notes;
  final double total;
  int next = 0;

  /// Returns the text to speak now, or null.
  String? update({required double pos, required double speed, required double lead}) {
    while (next < notes.length && notes[next].at < pos - 5) {
      next++; // already passed without being called (e.g. stopped)
    }
    if (next >= notes.length) return null;
    final dist = notes[next].at - pos;
    final trigger = math.max(lead * speed, 25.0);
    if (dist <= trigger) {
      final i = next;
      next++;
      return speechFor(notes, i, total);
    }
    return null;
  }
}

/// Records one sprint session: a bike or car recce (builds the stenogram) or
/// a timed run (speaks the reference stenogram, stops at the finish line).
///
/// Time: START arms it; the clock starts when the vehicle moves off (from
/// GPS, back-dated to the moment it left the armed position).
class Recorder {
  Recorder({required this.type, this.reference});

  final SessionType type;

  /// For runs: the recce with the stenogram and finish line.
  final Session? reference;

  RecState state = RecState.idle;
  bool autoFinished = false;

  double? _startMs;
  double? _endMs;
  double _odoStart = 0;
  double? _armLat, _armLon;
  double? lastLat, lastLon;

  double rawPos = 0;
  double _offset = 0;

  /// Position along the track, m (runs: lined up with the stenogram).
  double get trackPos => rawPos + _offset;

  final CornerTracker _tracker = CornerTracker();
  final List<CornerRec> corners = [];
  int _lastSynced = -1;

  final Samples samples = Samples();
  double _lastSampleMs = -1e12;
  final List<List<double>> _recent = []; // [lat, lon, trackPos]

  FinishDetector? _finishDet;
  Announcer? announcer;

  bool get isRun => type == SessionType.run;
  List<Note> get notes => reference?.notes ?? const [];
  double get refDistance => reference?.distance ?? 0;

  /// Corner being driven right now (for the live display).
  bool get inCorner => _tracker.active;
  double get cornerPeak => _tracker.peak;

  /// When the clock started (epoch ms), once moving.
  int? get startEpochMs => _startMs?.round();

  /// Set by the app once the finished session has been stored.
  bool saved = false;

  int elapsedMs(double nowMs) {
    final s = _startMs;
    if (s == null) return 0;
    final e = state == RecState.finished ? (_endMs ?? nowMs) : nowMs;
    final v = (e - s).round();
    return v < 0 ? 0 : v;
  }

  /// The note being driven or coming next, and the distance to its start.
  (Note, double)? noteAhead() {
    for (final n in notes) {
      if (n.end > trackPos) return (n, n.at - trackPos);
    }
    return null;
  }

  void arm() {
    if (state != RecState.idle) return;
    state = RecState.armed;
    final f = reference?.finish;
    _finishDet = (isRun && f != null) ? FinishDetector(f) : null;
    announcer = (isRun && notes.isNotEmpty) ? Announcer(notes, refDistance) : null;
  }

  /// Each GPS fix. [odometer]: trip odometer after this fix was added.
  void onFix(Fix f, double odometer) {
    if (f.accuracy > 25) return;
    lastLat = f.lat;
    lastLon = f.lon;
    switch (state) {
      case RecState.armed:
        final al = _armLat, ao = _armLon;
        if (al == null || ao == null) {
          _armLat = f.lat;
          _armLon = f.lon;
          return;
        }
        final moved = distanceMeters(al, ao, f.lat, f.lon);
        final v = f.speed;
        if (moved >= 3 && (v == null || v >= 1.0)) {
          final speed = math.max(v ?? 1.5, 1.0);
          _startMs = f.timeMs - moved / speed * 1000;
          _odoStart = odometer - moved;
          state = RecState.running;
          _finishDet?.update(f.lat, f.lon, f.timeMs);
          _recent.add([f.lat, f.lon, moved]);
        }
      case RecState.running:
        rawPos = math.max(0.0, odometer - _odoStart);
        _recent.add([f.lat, f.lon, trackPos]);
        if (_recent.length > 120) _recent.removeAt(0);
        final crossed = _finishDet?.update(f.lat, f.lon, f.timeMs);
        if (crossed != null && trackPos > 0.5 * refDistance) {
          _finish(crossed, auto: true);
        }
      case RecState.idle:
      case RecState.finished:
        break;
    }
  }

  /// Each app tick (~50 per second). [angle]: steering angle (car) or the
  /// bike's equivalent angle. Returns text to speak, if any.
  String? tick({
    required double nowMs,
    required double odometer,
    required double speed,
    required double angle,
    required double deadZone,
    required double endBelow,
    required double dt,
    double lead = 4,
  }) {
    if (state != RecState.running) return null;
    rawPos = math.max(0.0, odometer - _odoStart);

    final wasActive = _tracker.active;
    final wasPeak = _tracker.peak;
    final done = _tracker.update(
      angle: angle,
      deadZone: deadZone,
      endBelow: endBelow,
      odometer: rawPos,
      dt: dt,
    );
    if (done != null) {
      corners.add(CornerRec(rawPos - done.length, done.length, done.peak));
    }
    final started = _tracker.active &&
        (!wasActive || (done != null) || ((_tracker.peak > 0) != (wasPeak > 0)));
    if (started && isRun) _sync();

    final s = _startMs ?? nowMs;
    if (nowMs - _lastSampleMs >= 200) {
      samples.add((nowMs - s).round(), trackPos, speed, angle, lastLat ?? 0, lastLon ?? 0);
      _lastSampleMs = nowMs;
    }
    return announcer?.update(pos: trackPos, speed: speed, lead: lead);
  }

  /// A corner just started in a run: line the position up with the matching
  /// stenogram corner, so distance errors don't build up.
  void _sync() {
    var best = -1;
    var bestErr = 20.0;
    for (var j = _lastSynced + 1; j < notes.length; j++) {
      final err = (notes[j].at - trackPos).abs();
      if (err <= bestErr) {
        best = j;
        bestErr = err;
      }
      if (notes[j].at > trackPos + 20) break;
    }
    if (best >= 0) {
      _offset += notes[best].at - trackPos;
      _lastSynced = best;
    }
  }

  /// STOP button. Armed: cancel. Running: finish now.
  void stop(double nowMs) {
    if (state == RecState.armed) {
      state = RecState.idle;
      _armLat = null;
      _armLon = null;
      return;
    }
    if (state == RecState.running) _finish(nowMs, auto: false);
  }

  void _finish(double endMs, {required bool auto}) {
    _endMs = endMs;
    autoFinished = auto;
    if (_tracker.active) {
      final len = _tracker.lengthAt(rawPos);
      corners.add(CornerRec(rawPos - len, len, _tracker.peak));
      _tracker.clear();
    }
    final s = _startMs ?? endMs;
    samples.add((endMs - s).round(), trackPos, 0, 0, lastLat ?? 0, lastLon ?? 0);
    state = RecState.finished;
  }

  /// Finish line for a recce: where it stopped, facing the way it arrived.
  FinishPoint? _finishPoint() {
    if (_recent.isEmpty) return null;
    final last = _recent.last;
    var from = _recent.first;
    for (var i = _recent.length - 1; i >= 0; i--) {
      if (last[2] - _recent[i][2] >= 15) {
        from = _recent[i];
        break;
      }
    }
    if (identical(from, last)) return FinishPoint(last[0], last[1], 0);
    return FinishPoint(last[0], last[1], bearingDeg(from[0], from[1], last[0], last[1]));
  }

  /// The finished session. [signFix]: multiply corner angles by this
  /// (bike: the learned left/right sign).
  Session toSession({
    required String id,
    required String name,
    required int createdAt,
    required GradeConfig cfg,
    required String Function(double) lengthLabel,
    int signFix = 1,
  }) {
    final cs = [for (final c in corners) CornerRec(c.start, c.length, c.peak * signFix)];
    final dist = trackPos;
    if (isRun) {
      return Session(
        id: id,
        type: type,
        name: name,
        createdAt: createdAt,
        durationMs: elapsedMs(_endMs ?? 0),
        distance: dist,
        autoFinish: autoFinished,
        refId: reference?.id,
        finish: reference?.finish,
        corners: cs,
        notes: [for (final n in notes) n.copy()],
        samples: samples,
      );
    }
    return Session(
      id: id,
      type: type,
      name: name,
      createdAt: createdAt,
      durationMs: elapsedMs(_endMs ?? 0),
      distance: dist,
      finish: _finishPoint(),
      corners: cs,
      notes: buildNotes(cs, cfg, lengthLabel),
      samples: samples,
    );
  }
}
