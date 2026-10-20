/// Data for the sprint mode: recorded sessions, corners and pace notes.
library;

enum SessionType { bike, car, run }

extension SessionTypeText on SessionType {
  String get label => switch (this) {
        SessionType.bike => 'Bike recce',
        SessionType.car => 'Car recce',
        SessionType.run => 'Run',
      };
  bool get isRecce => this != SessionType.run;
}

SessionType sessionTypeFrom(String? s) => SessionType.values
    .firstWhere((t) => t.name == s, orElse: () => SessionType.run);

/// A corner found while recording: where it starts on the track, how long it
/// is and its peak angle (positive = left; for the bike this is the
/// equivalent car steering angle worked out from the corner's radius).
class CornerRec {
  const CornerRec(this.start, this.length, this.peak);
  final double start;
  final double length;
  final double peak;

  double get end => start + length;

  List<double> toJson() => [_r1(start), _r1(length), _r1(peak)];

  static CornerRec fromJson(dynamic j) {
    final l = (j as List).map((e) => (e as num).toDouble()).toList();
    return CornerRec(l[0], l[1], l[2]);
  }
}

/// One stenogram item: a single corner, or a group of corners close together
/// (e.g. an artificial chicane "R3L2R4").
class Note {
  Note({
    required this.at,
    required this.length,
    required this.call,
    this.custom,
    this.group = false,
  });

  /// Track distance (m from start) where the corner or group begins.
  double at;

  /// Length of the corner or group, m.
  double length;

  /// Automatic call, e.g. "L3- long" or "R3L2R4".
  String call;

  /// Driver's own text; replaces [call] when set.
  String? custom;

  /// More than one corner (chicane / "roter" / S-bend).
  bool group;

  String get text => (custom == null || custom!.trim().isEmpty) ? call : custom!.trim();
  double get end => at + length;

  Map<String, dynamic> toJson() => {
        'at': _r1(at),
        'len': _r1(length),
        'call': call,
        if (custom != null && custom!.trim().isNotEmpty) 'custom': custom,
        if (group) 'group': true,
      };

  static Note fromJson(dynamic j) {
    final m = j as Map<String, dynamic>;
    return Note(
      at: (m['at'] as num).toDouble(),
      length: (m['len'] as num).toDouble(),
      call: m['call'] as String,
      custom: m['custom'] as String?,
      group: m['group'] == true,
    );
  }

  Note copy() => Note.fromJson(toJson());
}

/// Recorded samples, about 5 per second, stored column by column.
class Samples {
  final List<int> t = []; // ms since start
  final List<double> p = []; // track position, m
  final List<double> v = []; // speed, m/s
  final List<double> a = []; // angle, degrees (steering, or bike equivalent)
  final List<double> lat = [];
  final List<double> lon = [];

  int get length => t.length;

  void add(int tMs, double pos, double speed, double angle, double la, double lo) {
    t.add(tMs);
    p.add(pos);
    v.add(speed);
    a.add(angle);
    lat.add(la);
    lon.add(lo);
  }

  Map<String, dynamic> toJson() => {
        't': t,
        'p': p.map(_r1).toList(),
        'v': v.map(_r1).toList(),
        'a': a.map(_r1).toList(),
        'lat': lat.map(_r6).toList(),
        'lon': lon.map(_r6).toList(),
      };

  static Samples fromJson(dynamic j) {
    final s = Samples();
    if (j is! Map<String, dynamic>) return s;
    final Map<String, dynamic> m = j;
    List<double> d(String k) =>
        ((m[k] as List?) ?? const []).map((e) => (e as num).toDouble()).toList();
    final t = ((m['t'] as List?) ?? const []).map((e) => (e as num).toInt()).toList();
    final p = d('p'), v = d('v'), a = d('a'), la = d('lat'), lo = d('lon');
    final n = [t.length, p.length, v.length, a.length, la.length, lo.length]
        .reduce((x, y) => x < y ? x : y);
    for (var i = 0; i < n; i++) {
      s.add(t[i], p[i], v[i], a[i], la[i], lo[i]);
    }
    return s;
  }
}

/// A finish line: position and the direction of travel through it.
class FinishPoint {
  const FinishPoint(this.lat, this.lon, this.bearing);
  final double lat;
  final double lon;

  /// Direction of travel at the finish, degrees clockwise from north.
  final double bearing;

  Map<String, dynamic> toJson() => {'lat': _r6(lat), 'lon': _r6(lon), 'bearing': _r1(bearing)};

  static FinishPoint? fromJson(dynamic j) {
    if (j is! Map<String, dynamic>) return null;
    return FinishPoint(
      (j['lat'] as num).toDouble(),
      (j['lon'] as num).toDouble(),
      (j['bearing'] as num).toDouble(),
    );
  }
}

class Session {
  Session({
    required this.id,
    required this.type,
    required this.name,
    required this.createdAt,
    this.durationMs = 0,
    this.distance = 0,
    this.autoFinish = false,
    this.refId,
    this.finish,
    List<CornerRec>? corners,
    List<Note>? notes,
    Samples? samples,
  })  : corners = corners ?? [],
        notes = notes ?? [],
        samples = samples ?? Samples();

  final String id;
  final SessionType type;
  String name;
  final int createdAt; // ms since epoch
  int durationMs;
  double distance;

  /// Run stopped by crossing the finish line (not by hand).
  bool autoFinish;

  /// For runs: the recce whose stenogram was used.
  String? refId;
  FinishPoint? finish;
  List<CornerRec> corners;

  /// Recce: the stenogram. Run: a copy of the reference stenogram.
  List<Note> notes;
  Samples samples;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'name': name,
        'createdAt': createdAt,
        'durationMs': durationMs,
        'distance': _r1(distance),
        if (autoFinish) 'autoFinish': true,
        if (refId != null) 'refId': refId,
        if (finish != null) 'finish': finish!.toJson(),
        'corners': corners.map((c) => c.toJson()).toList(),
        'notes': notes.map((n) => n.toJson()).toList(),
        'samples': samples.toJson(),
      };

  static Session fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as String,
        type: sessionTypeFrom(j['type'] as String?),
        name: (j['name'] as String?) ?? '',
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        distance: (j['distance'] as num?)?.toDouble() ?? 0,
        autoFinish: j['autoFinish'] == true,
        refId: j['refId'] as String?,
        finish: FinishPoint.fromJson(j['finish']),
        corners: ((j['corners'] as List?) ?? const []).map(CornerRec.fromJson).toList(),
        notes: ((j['notes'] as List?) ?? const []).map(Note.fromJson).toList(),
        samples: Samples.fromJson(j['samples']),
      );

  SessionSummary get summary => SessionSummary(
        id: id,
        type: type,
        name: name,
        createdAt: createdAt,
        durationMs: durationMs,
        distance: distance,
        refId: refId,
        autoFinish: autoFinish,
      );
}

/// What the session list needs, without the samples.
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.type,
    required this.name,
    required this.createdAt,
    required this.durationMs,
    required this.distance,
    this.refId,
    this.autoFinish = false,
  });

  final String id;
  final SessionType type;
  final String name;
  final int createdAt;
  final int durationMs;
  final double distance;
  final String? refId;
  final bool autoFinish;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'name': name,
        'createdAt': createdAt,
        'durationMs': durationMs,
        'distance': _r1(distance),
        if (refId != null) 'refId': refId,
        if (autoFinish) 'autoFinish': true,
      };

  static SessionSummary fromJson(dynamic j) {
    final m = j as Map<String, dynamic>;
    return SessionSummary(
      id: m['id'] as String,
      type: sessionTypeFrom(m['type'] as String?),
      name: (m['name'] as String?) ?? '',
      createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
      durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
      distance: (m['distance'] as num?)?.toDouble() ?? 0,
      refId: m['refId'] as String?,
      autoFinish: m['autoFinish'] == true,
    );
  }
}

/// "1:23.456" (or "23.456" under a minute).
String fmtRaceTime(int ms) {
  final neg = ms < 0;
  final a = ms.abs();
  final m = a ~/ 60000;
  final s = (a % 60000) ~/ 1000;
  final milli = a % 1000;
  final ss = s.toString().padLeft(m > 0 ? 2 : 1, '0');
  final body = '${m > 0 ? '$m:' : ''}$ss.${milli.toString().padLeft(3, '0')}';
  return neg ? '-$body' : body;
}

/// "+0.123" / "-1.040" for time differences.
String fmtDelta(int ms) {
  final sign = ms > 0 ? '+' : (ms < 0 ? '-' : '±');
  final a = ms.abs();
  return '$sign${a ~/ 1000}.${(a % 1000).toString().padLeft(3, '0')}';
}

double _r1(double v) => (v * 10).roundToDouble() / 10;
double _r6(double v) => (v * 1e6).roundToDouble() / 1e6;

/// For speech: "1 minute 23.4" / "48.2 seconds".
String spokenTime(int ms) {
  final m = ms ~/ 60000;
  final s = ((ms % 60000) / 1000).toStringAsFixed(1);
  if (m == 0) return '$s seconds';
  return '$m minute${m > 1 ? 's' : ''} $s';
}
