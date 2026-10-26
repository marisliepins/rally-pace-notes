import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../sprint/models.dart';
import 'theme.dart';

/// The stage drawn from GPS (no map behind it), with every note numbered
/// where it starts. Tap a number to open that note.
class TrackMap extends StatelessWidget {
  const TrackMap({
    super.key,
    required this.samples,
    required this.notes,
    this.selected,
    this.onTapNote,
  });

  final Samples samples;
  final List<Note> notes;
  final int? selected;
  final ValueChanged<int>? onTapNote;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final geo = _TrackGeometry.from(samples, notes, Size(box.maxWidth, box.maxHeight));
      if (geo == null) {
        return Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(10)),
          child: const Text('No GPS track recorded', style: TextStyle(color: kDim)),
        );
      }
      return GestureDetector(
        onTapUp: (d) {
          final i = geo.noteAt(d.localPosition);
          if (i != null) onTapNote?.call(i);
        },
        child: Container(
          decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(10)),
          child: CustomPaint(
            painter: _TrackPainter(geo, notes, selected),
            child: const SizedBox.expand(),
          ),
        ),
      );
    });
  }
}

class _TrackGeometry {
  _TrackGeometry(this.path, this.markers);

  final List<Offset> path;
  final List<Offset?> markers; // per note

  int? noteAt(Offset p) {
    int? best;
    var bestD = 28.0;
    for (var i = 0; i < markers.length; i++) {
      final m = markers[i];
      if (m == null) continue;
      final d = (m - p).distance;
      if (d < bestD) {
        best = i;
        bestD = d;
      }
    }
    return best;
  }

  static _TrackGeometry? from(Samples s, List<Note> notes, Size size) {
    final idx = <int>[];
    for (var i = 0; i < s.length; i++) {
      if (s.lat[i] != 0 || s.lon[i] != 0) idx.add(i);
    }
    if (idx.length < 2 || size.width < 40 || size.height < 40) return null;
    final lat0 = s.lat[idx.first];
    final lon0 = s.lon[idx.first];
    final k = 111195.0;
    final c = math.cos(lat0 * math.pi / 180);
    final pts = [
      for (final i in idx) Offset((s.lon[i] - lon0) * c * k, -(s.lat[i] - lat0) * k),
    ];
    var minX = pts.first.dx, maxX = minX, minY = pts.first.dy, maxY = minY;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    const pad = 22.0;
    final w = math.max(maxX - minX, 1.0), h = math.max(maxY - minY, 1.0);
    final scale = math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
    final ox = (size.width - w * scale) / 2, oy = (size.height - h * scale) / 2;
    Offset map(Offset p) => Offset(ox + (p.dx - minX) * scale, oy + (p.dy - minY) * scale);
    final path = pts.map(map).toList();

    final markers = <Offset?>[];
    for (final n in notes) {
      Offset? m;
      for (var j = 0; j < idx.length; j++) {
        if (s.p[idx[j]] >= n.at) {
          m = path[j];
          break;
        }
      }
      markers.add(m);
    }
    return _TrackGeometry(path, markers);
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.geo, this.notes, this.selected);

  final _TrackGeometry geo;
  final List<Note> notes;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = kDim
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(geo.path.first.dx, geo.path.first.dy);
    for (final p in geo.path.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, line);
    canvas.drawCircle(geo.path.first, 6, Paint()..color = kGood);
    canvas.drawCircle(geo.path.last, 6, Paint()..color = kBad);

    for (var i = 0; i < geo.markers.length; i++) {
      final m = geo.markers[i];
      if (m == null) continue;
      final n = notes[i];
      final color = n.flagged
          ? kBad
          : (n.text.startsWith('L') ? kLeft : (n.text.startsWith('R') ? kRight : kAccent));
      final r = i == selected ? 15.0 : 12.0;
      canvas.drawCircle(m, r, Paint()..color = color);
      if (i == selected) {
        canvas.drawCircle(
            m,
            r + 3,
            Paint()
              ..color = kText
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      }
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, m - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _TrackPainter old) => true;
}
