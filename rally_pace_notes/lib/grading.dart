/// Steering angle -> corner grade mapping (pure Dart, unit-tested).
///
/// Anchors are the angles (degrees) for the six grades, ordered from the
/// gentlest corner to the sharpest. Between two anchors the range is split:
///
///   [anchor_i, anchor_i + z)        -> plain grade i
///   [anchor_i + z, middle)          -> grade i with suffix toward grade i+1
///   [middle, anchor_i+1 - z)        -> grade i+1 with suffix toward grade i
///   [anchor_i+1 - z, ...)           -> plain grade i+1
///
/// where z = zoneFraction * (anchor_i+1 - anchor_i).
/// The suffix always points numerically toward the neighbouring grade:
/// 1->6 mode: 2+ then 3-.   6->1 mode: 4- then 3+.
library;

enum GradeMode { oneToSix, sixToOne }

class GradeConfig {
  const GradeConfig({
    required this.anchors,
    this.mode = GradeMode.oneToSix,
    this.zoneFraction = 0.15,
    this.deadZone = 5,
  });

  final List<double> anchors;
  final GradeMode mode;
  final double zoneFraction;
  final double deadZone;

  /// Grade number shown for anchor index [i] (0 = gentlest).
  String numberAt(int i) =>
      (mode == GradeMode.oneToSix ? i + 1 : anchors.length - i).toString();

  String get _towardNext => mode == GradeMode.oneToSix ? '+' : '-';
  String get _fromPrevious => mode == GradeMode.oneToSix ? '-' : '+';

  /// Grade for an angle (sign ignored), without direction letter.
  /// Returns null when the wheel is inside the straight-ahead dead zone.
  String? gradeFor(double angle) {
    final a = angle.abs();
    if (a < deadZone) return null;
    final n = anchors.length;
    if (n == 0) return null;
    if (n == 1) return numberAt(0);
    for (var i = 0; i < n - 1; i++) {
      final lo = anchors[i];
      final hi = anchors[i + 1];
      final z = (hi - lo) * zoneFraction;
      if (a < lo + z) return numberAt(i);
      final mid = (lo + hi) / 2;
      if (a < mid) return '${numberAt(i)}$_towardNext';
      if (a < hi - z) return '${numberAt(i + 1)}$_fromPrevious';
    }
    return numberAt(n - 1);
  }

  /// Full call such as "L3-" or "R4+". Positive angle = left. "—" = straight.
  String callFor(double angle) {
    final g = gradeFor(angle);
    if (g == null) return '—';
    return '${angle >= 0 ? 'L' : 'R'}$g';
  }
}

/// Returns an error message, or null when the table is usable.
String? validateAnchors(List<double> anchors, double deadZone) {
  if (anchors.length != 6) return 'Six grade angles are needed.';
  if (anchors.first <= deadZone) {
    return 'Grade angles must be larger than the straight zone ($deadZone°).';
  }
  for (var i = 1; i < anchors.length; i++) {
    if (anchors[i] <= anchors[i - 1]) {
      return 'Angles must increase from the gentlest to the sharpest grade.';
    }
  }
  return null;
}
