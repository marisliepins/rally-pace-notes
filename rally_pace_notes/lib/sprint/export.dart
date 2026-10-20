import 'dart:convert';

import 'models.dart';
import 'stenogram.dart';

String _stamp(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}${p(d.month)}${p(d.day)}-${p(d.hour)}${p(d.minute)}';
}

String exportBaseName(Session s) =>
    '${s.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}-${_stamp(s.createdAt)}';

/// Full session as JSON (can be read back later).
String sessionJson(Session s) => const JsonEncoder.withIndent(' ').convert(s.toJson());

/// GPX track with time and speed, for video overlay tools.
String sessionGpx(Session s) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<gpx version="1.1" creator="Rally Pace Notes" '
        'xmlns="http://www.topografix.com/GPX/1/1">')
    ..writeln('<trk><name>${_esc(s.name)}</name><trkseg>');
  final sm = s.samples;
  final start = s.createdAt;
  for (var i = 0; i < sm.length; i++) {
    if (sm.lat[i] == 0 && sm.lon[i] == 0) continue;
    final t = DateTime.fromMillisecondsSinceEpoch(start + sm.t[i], isUtc: true).toIso8601String();
    b.writeln('<trkpt lat="${sm.lat[i]}" lon="${sm.lon[i]}"><time>$t</time>'
        '<extensions><speed>${sm.v[i].toStringAsFixed(1)}</speed></extensions></trkpt>');
  }
  b
    ..writeln('</trkseg></trk>')
    ..writeln('<!-- ${_esc(stenogramText(s.notes, s.distance))} -->')
    ..writeln('</gpx>');
  return b.toString();
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('--', '- -');
