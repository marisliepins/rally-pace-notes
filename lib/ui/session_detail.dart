import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../bridge.dart';
import '../sprint/export.dart';
import '../sprint/models.dart';
import '../sprint/stenogram.dart';
import 'sprint_home.dart' show fmtKm;
import 'theme.dart';

/// One session: the stenogram (recce) or the corner-by-corner comparison
/// with the best run (run). Export, delete, choose as notes.
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    s = c.sprint.get(widget.id);
    final x = s;
    if (x != null && x.type == SessionType.run) {
      final b = c.sprint.bestRun(x.refId);
      best = (b == null || b.id == x.id) ? x : c.sprint.get(b.id);
    }
  }

  void _msg(String text, {bool bad = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black)),
        backgroundColor: bad ? kBad : kGood,
      ),
    );
  }

  void _save() {
    final x = s;
    if (x == null) return;
    final err = c.sprint.save(x);
    if (err == null) {
      _msg('✓ Saved');
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
    if (err == null) {
      _msg('✓ Runs will use these notes');
    } else {
      _msg('NOT SAVED: $err', bad: true);
    }
    setState(() {});
  }

  void _swapLR() {
    final x = s;
    if (x == null) return;
    x.corners = [for (final k in x.corners) CornerRec(k.start, k.length, -k.peak)];
    x.notes = buildNotes(x.corners, c.gradeConfig, c.settings.lengthLabel);
    _save();
  }

  /// Rebuild the notes with the current grade table and lengths.
  void _regrade() {
    final x = s;
    if (x == null) return;
    x.notes = buildNotes(x.corners, c.gradeConfig, c.settings.lengthLabel);
    _save();
  }

  Future<void> _editNote(Note n) async {
    final ctl = TextEditingController(text: n.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Note at ${roundCall(n.at)} m'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Measured: ${n.call}', style: const TextStyle(color: kDim)),
          const SizedBox(height: 8),
          TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'e.g. L4- long, ROTER R3L2R4'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Use measured')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Save')),
        ],
      ),
    );
    if (result == null) return;
    n.custom = result.trim().isEmpty || result.trim() == n.call ? null : result.trim();
    _save();
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
      appBar: AppBar(title: Text(x.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Text(fmtRaceTime(x.durationMs),
              style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, fontFeatures: tabular)),
          Text('$when · ${fmtKm(x.distance)}'
              '${x.type == SessionType.run ? (x.autoFinish ? ' · finish line' : ' · stopped by hand') : ''}',
              style: const TextStyle(color: kDim)),
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

  List<Widget> _recce(Session x, bool isRef) => [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(10)),
          child: SelectableText(stenogramText(x.notes, x.distance),
              style: const TextStyle(fontSize: 18, height: 1.5, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          if (isRef)
            const Chip(label: Text('Runs use these notes'), avatar: Icon(Icons.check, color: kGood))
          else
            FilledButton(onPressed: _useAsNotes, child: const Text('Use these notes for runs')),
          OutlinedButton(onPressed: _swapLR, child: const Text('Swap L / R')),
          OutlinedButton(onPressed: _regrade, child: const Text('Re-grade with current table')),
        ]),
        const SizedBox(height: 8),
        const Text('Tap a note to change its text. Swap and re-grade replace your edited texts.',
            style: TextStyle(color: kDim)),
        const SizedBox(height: 8),
        for (var i = 0; i < x.notes.length; i++)
          Card(
            color: kPanel,
            child: ListTile(
              leading: Text('${roundCall(straightBefore(x.notes, i))}',
                  style: const TextStyle(color: kDim, fontSize: 18, fontFeatures: tabular)),
              title: Text(x.notes[i].text,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: x.notes[i].custom != null ? kAccent : kText)),
              subtitle: Text('at ${x.notes[i].at.round()} m · ${x.notes[i].length.round()} m long'
                  '${x.notes[i].group ? ' · group' : ''}'),
              trailing: const Icon(Icons.edit, color: kDim),
              onTap: () => _editNote(x.notes[i]),
            ),
          ),
      ];

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
