import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../bridge.dart';
import '../sprint/export.dart';
import '../sprint/models.dart';
import '../sprint/stenogram.dart';
import 'note_editor.dart';
import 'sprint_home.dart' show fmtKm;
import 'theme.dart';
import 'track_map.dart';

/// One session. Recce: its notes with the track drawing, ready to edit.
/// Run: the corner-by-corner comparison with the best run.
class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({super.key, required this.c, required this.id});
  final AppController c;
  final String id;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  AppController get c => widget.c;
  Session? s;
  Session? best;
  int? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    // The notes in use are cached: edit that copy so runs see the changes.
    final ref = c.sprint.reference;
    s = (ref != null && ref.id == widget.id) ? ref : c.sprint.get(widget.id);
    final x = s;
    if (x != null && x.type == SessionType.run) {
      final b = c.sprint.bestRun(x.refId);
      best = (b == null || b.id == x.id) ? x : c.sprint.get(b.id);
    }
  }

  void _msg(String text, {bool bad = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black)),
        backgroundColor: bad ? kBad : kGood,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _save({String ok = '✓ Saved'}) {
    final x = s;
    if (x == null) return;
    final err = c.sprint.save(x);
    if (err == null) {
      _msg(ok);
    } else {
      _msg('NOT SAVED: $err', bad: true);
    }
    setState(() {});
  }

  void _export(bool gpx) {
    final x = s;
    if (x == null) return;
    final name = exportBaseName(x);
    final err = gpx
        ? Bridge.download('$name.gpx', 'application/gpx+xml', sessionGpx(x))
        : Bridge.download('$name.json', 'application/json', sessionJson(x));
    if (err != null) _msg(err, bad: true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${s?.name}?'),
        content: const Text('This cannot be undone. Export it first if you want to keep it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kBad),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      c.sprint.delete(widget.id);
      Navigator.of(context).pop();
    }
  }

  void _useAsNotes() {
    c.sprint.prefs.refId = widget.id;
    final err = c.sprint.savePrefs();
    _load();
    if (err == null) {
      _msg('✓ Check drives and runs will use these notes');
    } else {
      _msg('NOT SAVED: $err', bad: true);
    }
    setState(() {});
  }

  Future<bool> _confirm(String title, String text) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _swapLR() async {
    final x = s;
    if (x == null) return;
    if (!await _confirm('Swap left and right?', 'All notes are rebuilt from the recording. Your edits are lost.')) {
      return;
    }
    x.corners = [for (final k in x.corners) CornerRec(k.start, k.length, -k.peak)];
    x.notes = buildNotes(x.corners, c.gradeConfig, c.settings.lengthLabel);
    _save();
  }

  /// Rebuild the notes with the current grade table and lengths.
  Future<void> _regrade() async {
    final x = s;
    if (x == null) return;
    if (!await _confirm('Re-grade all notes?',
        'Notes are rebuilt from the recording with your current grade table. Your edits are lost.')) {
      return;
    }
    x.notes = buildNotes(x.corners, c.gradeConfig, c.settings.lengthLabel);
    _save();
  }

  void _clearMarks() {
    final x = s;
    if (x == null) return;
    for (final n in x.notes) {
      n.flagged = false;
    }
    _save(ok: '✓ Marks cleared');
  }

  Future<void> _edit(int i) async {
    final x = s;
    if (x == null || i < 0 || i >= x.notes.length) return;
    setState(() => _selected = i);
    final r = await showNoteEditor(context, c: c, session: x, index: i);
    if (r == null || !mounted) return;
    x.notes = r.notes;
    x.distance = r.total;
    _save(ok: '✓ Note saved');
  }

  Future<void> _insertFirst() async {
    final x = s;
    if (x == null) return;
    final n = Note(at: x.notes.isEmpty ? 50 : x.notes.first.at / 2, length: 10, call: 'L1');
    x.notes.insert(0, n);
    _save();
    await _edit(0);
  }

  @override
  Widget build(BuildContext context) {
    final x = s;
    if (x == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Session')),
        body: const Center(child: Text('Session not found on this phone.')),
      );
    }
    final d = DateTime.fromMillisecondsSinceEpoch(x.createdAt);
    String p(int n) => n.toString().padLeft(2, '0');
    final when = '${p(d.day)}.${p(d.month)}.${d.year} ${p(d.hour)}:${p(d.minute)}';
    final isRef = c.sprint.prefs.refId == x.id;
    return Scaffold(
      appBar: AppBar(title: Text(x.type.isRecce ? '${x.name} · notes' : x.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmtRaceTime(x.durationMs),
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, fontFeatures: tabular)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$when · ${fmtKm(x.distance)}'
                '${x.type == SessionType.run ? (x.autoFinish ? ' · finish line' : ' · stopped by hand') : ''}',
                style: const TextStyle(color: kDim),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (x.type.isRecce) ..._recce(x, isRef) else ..._run(x),
          const SizedBox(height: 24),
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(
                onPressed: () => _export(false), icon: const Icon(Icons.download), label: const Text('Export JSON')),
            OutlinedButton.icon(
                onPressed: () => _export(true), icon: const Icon(Icons.route), label: const Text('Export GPX')),
            OutlinedButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete, color: kBad),
              label: const Text('Delete', style: TextStyle(color: kBad)),
            ),
          ]),
        ],
      ),
    );
  }

  List<Widget> _recce(Session x, bool isRef) {
    final marked = x.notes.where((n) => n.flagged).length;
    return [
      SizedBox(
        height: 230,
        child: TrackMap(samples: x.samples, notes: x.notes, selected: _selected, onTapNote: _edit),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(10)),
        child: SelectableText(stenogramText(x.notes, x.distance),
            style: const TextStyle(fontSize: 17, height: 1.5, fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (isRef)
          const Chip(label: Text('Check & race use these notes'), avatar: Icon(Icons.check, color: kGood))
        else
          FilledButton(onPressed: _useAsNotes, child: const Text('Use these notes')),
        if (marked > 0)
          OutlinedButton(onPressed: _clearMarks, child: Text('Clear $marked marks')),
      ]),
      if (marked > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('$marked ${marked == 1 ? 'note was' : 'notes were'} marked in the check drive (red).',
              style: const TextStyle(color: kBad, fontWeight: FontWeight.w700)),
        ),
      const SizedBox(height: 8),
      const Text('Tap a note (or its number on the drawing) to change it.', style: TextStyle(color: kDim)),
      const SizedBox(height: 6),
      _startRow(x),
      for (var i = 0; i < x.notes.length; i++) _noteRow(x, i),
      _finishRow(x),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        OutlinedButton(onPressed: _swapLR, child: const Text('Swap L / R')),
        OutlinedButton(onPressed: _regrade, child: const Text('Re-grade with current table')),
      ]),
    ];
  }

  Widget _startRow(Session x) => Card(
        color: kPanel,
        child: ListTile(
          dense: true,
          title: const Text('START', style: TextStyle(fontWeight: FontWeight.w800, color: kGood)),
          trailing: TextButton(onPressed: _insertFirst, child: const Text('+ note')),
        ),
      );

  Widget _finishRow(Session x) => Card(
        color: kPanel,
        child: ListTile(
          dense: true,
          leading: Text(
            x.notes.isEmpty ? '${roundCall(x.distance)}' : '${roundCall(straightAfter(x.notes, x.notes.length - 1, x.distance))}',
            style: const TextStyle(color: kDim, fontSize: 18, fontFeatures: tabular),
          ),
          title: const Text('FINISH', style: TextStyle(fontWeight: FontWeight.w800, color: kBad)),
          subtitle: Text('total ${x.distance.round()} m'),
        ),
      );

  Widget _noteRow(Session x, int i) {
    final n = x.notes[i];
    final edited = n.custom != null;
    return Card(
      color: n.flagged ? kBad.withValues(alpha: 0.25) : kPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: n.flagged ? kBad : (i == _selected ? kText : Colors.transparent), width: 2),
      ),
      child: ListTile(
        leading: SizedBox(
          width: 64,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${roundCall(straightBefore(x.notes, i))}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFeatures: tabular)),
            Text('#${i + 1}', style: const TextStyle(color: kDim, fontSize: 12)),
          ]),
        ),
        title: Text(n.text,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: edited ? kAccent : kText)),
        subtitle: Text('${n.length.round()} m long · at ${n.at.round()} m'
            '${edited ? ' · measured ${n.call}' : ''}${n.flagged ? ' · MARKED' : ''}'),
        trailing: const Icon(Icons.edit, color: kDim),
        onTap: () => _edit(i),
      ),
    );
  }

  List<Widget> _run(Session x) {
    final b = best;
    final sm = x.samples;
    final bs = b?.samples;
    final isBest = b == null || b.id == x.id;
    final rows = <TableRow>[
      _row(['', 'Note', 'Time', isBest ? '' : 'Δ best', 'In', 'Min'], header: true),
    ];
    for (var i = 0; i < x.notes.length; i++) {
      final n = x.notes[i];
      final t = timeAtPosition(sm.t, sm.p, n.at);
      final bt = bs == null ? null : timeAtPosition(bs.t, bs.p, n.at);
      final vin = speedAtPosition(sm.p, sm.v, n.at);
      final vmin = minSpeedBetween(sm.p, sm.v, n.at, n.end);
      String kmh(double? v) => v == null ? '—' : '${(v * 3.6).round()}';
      rows.add(_row([
        '${i + 1}',
        n.text,
        t == null ? '—' : fmtRaceTime(t.round()),
        (isBest || t == null || bt == null) ? '' : fmtDelta((t - bt).round()),
        kmh(vin),
        kmh(vmin),
      ], deltaMs: (isBest || t == null || bt == null) ? null : (t - bt).round()));
    }
    final total = (b == null || b.id == x.id) ? null : x.durationMs - b.durationMs;
    return [
      if (total != null)
        Text('${fmtDelta(total)} to best run (${b!.name})',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: total <= 0 ? kGood : kBad))
      else
        const Text('Best run with these notes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kGood)),
      const SizedBox(height: 12),
      const Text('Time and speed (km/h) where each note starts. Δ: + slower, − faster than the best run.',
          style: TextStyle(color: kDim)),
      const SizedBox(height: 8),
      Table(
        columnWidths: const {
          0: FixedColumnWidth(28),
          1: FlexColumnWidth(3),
          2: FlexColumnWidth(2.2),
          3: FlexColumnWidth(2),
          4: FlexColumnWidth(1.2),
          5: FlexColumnWidth(1.2),
        },
        children: rows,
      ),
    ];
  }

  TableRow _row(List<String> cells, {bool header = false, int? deltaMs}) {
    return TableRow(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kLine))),
      children: [
        for (var i = 0; i < cells.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Text(
              cells[i],
              style: TextStyle(
                fontSize: header ? 13 : 16,
                color: header
                    ? kDim
                    : (i == 3 && deltaMs != null ? (deltaMs <= 0 ? kGood : kBad) : kText),
                fontWeight: header || i == 1 ? FontWeight.w700 : FontWeight.w500,
                fontFeatures: tabular,
              ),
            ),
          ),
      ],
    );
  }
}
