import 'grading.dart';

class Settings {
  Settings({
    List<double>? anchors,
    this.mode = GradeMode.oneToSix,
    this.zonePercent = 15,
    this.deadZone = 5,
    this.longCorner = 50,
    this.superLongCorner = 70,
    this.peakHold = true,
    this.imperial = false,
    this.showSpeed = true,
    this.invertDirection = false,
    this.useGyro = true,
    this.smoothing = 0.8,
    this.rotation = 1,
  }) : anchors = anchors ?? List.of(defaultAnchors);

  static const List<double> defaultAnchors = [10, 25, 45, 90, 120, 180];

  /// Angles for grades, gentlest -> sharpest (1..6 in 1->6 mode).
  List<double> anchors;
  GradeMode mode;
  double zonePercent;
  double deadZone;
  double longCorner; // metres
  double superLongCorner; // metres
  /// true = show the largest angle of the current corner until the wheel is
  /// back to straight; false = show the live angle.
  bool peakHold;
  bool imperial;
  bool showSpeed;
  bool invertDirection;
  bool useGyro;
  double smoothing; // seconds
  /// Screen rotation when the iPhone is portrait-locked:
  /// 0 = none, 1 = quarter turn clockwise, 3 = quarter turn counter-clockwise.
  int rotation;

  GradeConfig get gradeConfig => GradeConfig(
        anchors: anchors,
        mode: mode,
        zoneFraction: zonePercent / 100,
        deadZone: deadZone,
      );

  String lengthLabel(double metres) {
    if (metres >= superLongCorner) return 'SUPER LONG';
    if (metres >= longCorner) return 'LONG';
    return '';
  }

  Map<String, dynamic> toJson() => {
        'v': 2,
        'peakHold': peakHold,
        'anchors': anchors,
        'mode': mode.name,
        'zonePercent': zonePercent,
        'deadZone': deadZone,
        'longCorner': longCorner,
        'superLongCorner': superLongCorner,
        'imperial': imperial,
        'showSpeed': showSpeed,
        'invertDirection': invertDirection,
        'useGyro': useGyro,
        'smoothing': smoothing,
        'rotation': rotation,
      };

  factory Settings.fromJson(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    bool b(String k, bool def) => (j[k] as bool?) ?? def;
    final rawAnchors = (j['anchors'] as List?)
        ?.map((e) => (e as num).toDouble())
        .toList();
    final rot = (j['rotation'] as num?)?.toInt() ?? 1;
    // Settings saved by version 0.1/0.2 still hold the old 40/60 m defaults.
    final oldDefaults =
        j['v'] == null && d('longCorner', 40) == 40 && d('superLongCorner', 60) == 60;
    return Settings(
      anchors: (rawAnchors != null && rawAnchors.length == 6) ? rawAnchors : null,
      mode: j['mode'] == GradeMode.sixToOne.name
          ? GradeMode.sixToOne
          : GradeMode.oneToSix,
      zonePercent: d('zonePercent', 15),
      deadZone: d('deadZone', 5),
      longCorner: oldDefaults ? 50 : d('longCorner', 50),
      superLongCorner: oldDefaults ? 70 : d('superLongCorner', 70),
      peakHold: b('peakHold', true),
      imperial: b('imperial', false),
      showSpeed: b('showSpeed', true),
      invertDirection: b('invertDirection', false),
      useGyro: b('useGyro', true),
      smoothing: d('smoothing', 0.8),
      rotation: (rot == 0 || rot == 1 || rot == 3) ? rot : 1,
    );
  }

  Settings copy() => Settings.fromJson(toJson());
}

String fmtShort(double metres, bool imperial) => imperial
    ? '${(metres * 1.0936133).round()} yd'
    : '${metres.round()} m';

String fmtTotal(double metres, bool imperial) => imperial
    ? '${(metres / 1609.344).toStringAsFixed(2)} mi'
    : '${(metres / 1000).toStringAsFixed(2)} km';

String fmtSpeed(double? mps, bool imperial) {
  if (mps == null || mps < 0) return '--';
  return imperial
      ? '${(mps * 2.2369363).round()} mph'
      : '${(mps * 3.6).round()} km/h';
}
