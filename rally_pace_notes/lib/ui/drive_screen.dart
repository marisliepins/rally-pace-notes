import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../settings.dart';
import 'settings_screen.dart';
import 'theme.dart';

class DriveScreen extends StatefulWidget {
  const DriveScreen({super.key, required this.c});
  final AppController c;

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed && _pointer != null && !_fired) {
        _fired = true;
        widget.c.resetAll();
      }
    });

  int? _pointer;
  DateTime _downAt = DateTime.now();
  bool _fired = false;

  AppController get c => widget.c;

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _downAt = DateTime.now();
    _fired = false;
    _hold.forward(from: 0);
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final ms = DateTime.now().difference(_downAt).inMilliseconds;
    _hold.reset();
    if (_fired) return;
    if (ms < 450) {
      c.resetDistance();
    } else {
      c.flash('RESET CANCELLED');
    }
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _hold.reset();
  }

  Future<void> _openSettings() async {
    c.driveActive = false;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsScreen(c: c)),
    );
    c.driveActive = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) => LayoutBuilder(builder: (context, box) {
          final portrait = box.maxHeight > box.maxWidth;
          Widget content = _content();
          if (portrait && c.settings.rotation != 0) {
            content = RotatedBox(quarterTurns: c.settings.rotation, child: content);
          }
          return SafeArea(child: content);
        }),
      ),
    );
  }

  Widget _content() {
    final since = DateTime.now().difference(c.eventAt).inMilliseconds;
    final flashBg = since < 220;
    final showBanner = since < 1800;
    return Column(
      children: [
        _topBar(),
        Expanded(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              color: flashBg ? kAccent.withValues(alpha: 0.22) : Colors.transparent,
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(flex: 5, child: _gradeArea()),
                      Expanded(flex: 3, child: _distanceRow()),
                    ],
                  ),
                  if (showBanner)
                    Positioned(
                      top: 6,
                      left: 0,
                      right: 0,
                      child: Center(child: _banner(c.eventText)),
                    ),
                  AnimatedBuilder(
                    animation: _hold,
                    builder: (context, _) => _hold.value < 0.15
                        ? const SizedBox.shrink()
                        : Center(child: _holdRing(_hold.value)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- top bar
  Widget _topBar() {
    final s = c.settings;
    final geo = (c.status['geo'] ?? 'not started').toString();
    final motion = (c.status['motion'] ?? 'not started').toString();
    final acc = c.trip.accuracy;
    final fixAge = c.trip.lastFixAt == null
        ? 999
        : DateTime.now().difference(c.trip.lastFixAt!).inSeconds;
    Color gpsColor;
    String gpsText;
    if (acc == null || fixAge > 5) {
      gpsColor = geo.startsWith('error') ? kBad : kWarn;
      gpsText = geo.startsWith('error') ? 'GPS error' : 'GPS …';
    } else {
      gpsColor = acc <= 10 ? kGood : (acc <= 25 ? kWarn : kBad);
      gpsText = 'GPS ±${acc.round()} m';
    }
    final sensOk = motion == 'ok';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
      child: Row(
        children: [
          _chip(gpsText, gpsColor),
          const SizedBox(width: 8),
          _chip(sensOk ? 'SENSOR ok' : 'SENSOR $motion', sensOk ? kGood : kBad),
          const Spacer(),
          if (s.showSpeed)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                fmtSpeed(c.trip.speed, s.imperial),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: kText,
                  fontFeatures: tabular,
                ),
              ),
            ),
          OutlinedButton(
            onPressed: c.setZero,
            style: OutlinedButton.styleFrom(
              foregroundColor: kText,
              side: const BorderSide(color: kLine, width: 2),
              minimumSize: const Size(72, 44),
            ),
            child: const Text('ZERO', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            onPressed: _openSettings,
            iconSize: 30,
            color: kDim,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );

  // ------------------------------------------------------------- grade area
  Widget _gradeArea() {
    final angle = c.angle;
    final shown = c.shownAngle;
    final peakMode = c.settings.peakHold;
    final grade = c.gradeConfig.gradeFor(shown);
    final left = (grade == null ? angle : shown) >= 0;
    final dirColor = left ? kLeft : kRight;
    final gradeText = grade == null
        ? const Text('—', style: TextStyle(fontSize: 220, color: kDim, fontWeight: FontWeight.w800, height: 1))
        : RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 220, fontWeight: FontWeight.w800, height: 1),
              children: [
                TextSpan(text: left ? 'L' : 'R', style: TextStyle(color: dirColor)),
                TextSpan(text: grade, style: const TextStyle(color: kText)),
              ],
            ),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: FittedBox(fit: BoxFit.contain, child: gradeText),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Expanded(
                  child: CustomPaint(
                    painter: DialPainter(
                      angle,
                      c.settings.anchors,
                      dirColor,
                      peak: peakMode && c.corner.active ? c.corner.peak : null,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                Text(
                  peakMode && c.corner.active
                      ? '${angle.abs().round()}° · max ${shown.abs().round()}°'
                      : '${angle.abs().round()}°${angle.abs() >= c.settings.deadZone ? (angle >= 0 ? ' L' : ' R') : ''}',
                  style: const TextStyle(
                    fontSize: 28,
                    color: kText,
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- distance row
  Widget _distanceRow() {
    final s = c.settings;
    final t = c.trip;
    final imp = s.imperial;
    final cfg = c.gradeConfig;

    Widget cornerTile;
    if (c.corner.active) {
      final len = c.cornerLength;
      final label = s.lengthLabel(len);
      cornerTile = _tile(
        label: 'CORNER${label.isEmpty ? '' : ' · $label'}',
        labelColor: kAccent,
        value: fmtShort(len, imp),
        border: kAccent,
      );
    } else {
      final last = c.corner.last;
      final label = last == null ? '' : s.lengthLabel(last.length);
      cornerTile = _tile(
        label: 'LAST CORNER${label.isEmpty ? '' : ' · $label'}',
        labelColor: kDim,
        value: last == null ? '—' : '${cfg.callFor(last.peak)}  ${fmtShort(last.length, imp)}',
        border: kLine,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 4,
            child: _tile(
              label: 'DISTANCE',
              labelColor: kDim,
              value: fmtShort(t.segment, imp),
              border: kLine,
              sub: t.lastSegment == null ? null : 'prev ${fmtShort(t.lastSegment!, imp)}',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(flex: 4, child: cornerTile),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: _tile(label: 'TOTAL', labelColor: kDim, value: fmtTotal(t.total, imp), border: kLine),
          ),
        ],
      ),
    );
  }

  BoxDecoration _box(Color border) => BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 2),
      );

  Widget _tile({
    required String label,
    required Color labelColor,
    required String value,
    required Color border,
    String? sub,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: _box(border),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: labelColor, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
            if (sub != null) ...[
              const Spacer(),
              Text(sub, style: const TextStyle(color: kDim, fontSize: 14, fontFeatures: tabular)),
            ],
          ]),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(fontSize: 64, color: kText, fontWeight: FontWeight.w700, fontFeatures: tabular),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w800)),
      );

  Widget _holdRing(double v) => Container(
        width: 170,
        height: 170,
        decoration: const BoxDecoration(color: Color(0xCC000000), shape: BoxShape.circle),
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: 140,
            height: 140,
            child: CircularProgressIndicator(value: v, strokeWidth: 12, color: kBad, backgroundColor: kLine),
          ),
          const Text('HOLD\nTO RESET', textAlign: TextAlign.center, style: TextStyle(color: kText, fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
      );
}

/// Steering-wheel style dial: needle shows the wheel angle, ticks show the
/// grade anchor angles on both sides.
class DialPainter extends CustomPainter {
  DialPainter(this.angle, this.anchors, this.needleColor, {this.peak});
  final double angle;
  final List<double> anchors;
  final Color needleColor;
  final double? peak;

  Offset _at(Offset c, double deg, double r) {
    final t = deg * math.pi / 180;
    // positive (left) = counter-clockwise from top
    return c + Offset(-math.sin(t) * r, -math.cos(t) * r);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 - 6;
    if (r <= 10) return;
    final center = size.center(Offset.zero);
    canvas.drawCircle(center, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = kLine);
    final tick = Paint()
      ..strokeWidth = 3
      ..color = kDim;
    for (final a in anchors) {
      if (a > 180) continue;
      for (final sgn in [1.0, -1.0]) {
        canvas.drawLine(_at(center, a * sgn, r - 10), _at(center, a * sgn, r), tick);
      }
    }
    canvas.drawLine(_at(center, 0, r - 14), _at(center, 0, r), Paint()
      ..strokeWidth = 4
      ..color = kText);
    final p = peak;
    if (p != null) {
      canvas.drawCircle(_at(center, p, r - 5), 7, Paint()..color = needleColor);
    }
    canvas.drawLine(center, _at(center, angle, r * 0.88), Paint()
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = needleColor);
    canvas.drawCircle(center, 7, Paint()..color = needleColor);
  }

  @override
  bool shouldRepaint(covariant DialPainter old) =>
      old.angle != angle ||
      old.anchors != anchors ||
      old.needleColor != needleColor ||
      old.peak != peak;
}
