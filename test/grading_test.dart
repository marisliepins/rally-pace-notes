import 'package:flutter_test/flutter_test.dart';
import 'package:rally_pace_notes/grading.dart';

void main() {
  const anchors = <double>[10, 25, 45, 90, 120, 180];

  test('1->6 default table', () {
    const c = GradeConfig(anchors: anchors);
    final cases = <double, String?>{
      3: null, 8: '1', 15: '1+', 20: '2-', 25: '2', 30: '2+', 40: '3-',
      45: '3', 60: '3+', 75: '4-', 90: '4', 100: '4+', 110: '5-',
      120: '5', 140: '5+', 160: '6-', 200: '6', 400: '6',
    };
    cases.forEach((a, g) => expect(c.gradeFor(a), g, reason: '$a°'));
  });

  test('6->1 mode flips numbers and suffixes', () {
    const c = GradeConfig(anchors: anchors, mode: GradeMode.sixToOne);
    expect(c.gradeFor(8), '6');
    expect(c.gradeFor(30), '5-');
    expect(c.gradeFor(60), '4-');
    expect(c.gradeFor(75), '3+');
    expect(c.gradeFor(200), '1');
  });

  test('direction letter and both sides symmetric', () {
    const c = GradeConfig(anchors: anchors);
    expect(c.callFor(30), 'L2+');
    expect(c.callFor(-30), 'R2+');
    expect(c.callFor(2), '—');
  });

  test('validation', () {
    expect(validateAnchors(anchors, 5), isNull);
    expect(validateAnchors([10, 25, 20, 90, 120, 180], 5), isNotNull);
    expect(validateAnchors([4, 25, 45, 90, 120, 180], 5), isNotNull);
  });
}
