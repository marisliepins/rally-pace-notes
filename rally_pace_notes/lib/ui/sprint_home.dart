import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../sprint/models.dart';
import 'record_screen.dart';
import 'session_detail.dart';
import 'theme.dart';

/// Sprint mode: start recces and runs, list recorded sessions.
class SprintHomeScreen extends StatefulWidget {
  const SprintHomeScreen({super.key, required this.c});
  final AppController c;

  @override
  State<SprintHomeScreen> createState() => _SprintHomeScreenState();
}

class _SprintHomeScreenState extends State<SprintHomeScreen> {
  AppController get c => widget.c;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    // Notes can change on other screens (edits, marks): refresh now and then.
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Route<void> _route(Widget page) => PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      );

  Future<void> _record(SessionType type) async {
    await Navigator.of(context).push(_route(RecordScreen(c: c, type: type)));
    if (mounted) setState(() {});
  }

  Future<void> _open(SessionSummary s) async {
    await Navigator.of(context).push(_route(SessionDetailScreen(c: c, id: s.id)));
    if (mounted) setState(() {});
  }

  void _savePrefs() {
    c.applySprintPrefs();
    final err = c.sprint.savePrefs();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Not saved: $err'), backgroundColor: kBad),
      );
    }
    setState(() {});
  }

  Future<void> _openNotes() async {
    final id = c.sprint.prefs.refId;
    if (id == null) return;
    await Navigator.of(context).push(_route(SessionDetailScreen(c: c, id: id)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = c.sprint;
    final prefs = store.prefs;
    final ref = store.index.where((s) => s.id == prefs.refId).firstOrNull;
    final best = store.bestRun(prefs.refId);
    final marked = ref == null ? 0 : (store.reference?.notes.where((n) => n.flagged).length ?? 0);
    final recces = store.index.where((s) => s.type.isRecce).toList();
    final runs = store.index.where((s) => s.type == SessionType.run).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Sprint')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _step(
            '1',
            'RECCE',
            'Drive the stage slowly. The app writes the notes; you check and fix them at the end.',
            Icons.directions_car,
            () => _record(SessionType.car),
            extra: ref == null
                ? null
                : OutlinedButton.icon(
                    onPressed: _openNotes,
                    icon: const Icon(Icons.edit_note),
                    label: Text('Notes: ${ref.name}${marked > 0 ? ' · $marked marked' : ''}'),
                  ),
          ),
          _step(
            '2',
            'CHECK',
            ref == null
                ? 'Record a recce first.'
                : 'Drive again with the notes spoken. Tap the screen (or the remote button) when a note is wrong.',
            Icons.hearing,
            ref == null ? null : () => _record(SessionType.check),
          ),
          _step(
            '3',
            'RACE',
            ref == null
                ? 'Record a recce first.'
                : 'Timed runs with the notes spoken; stops at the finish line.'
                    '${best == null ? '' : ' Best: ${fmtRaceTime(best.durationMs)}'}',
            Icons.timer,
            ref == null ? null : () => _record(SessionType.run),
            accent: true,
          ),
          if (runs.isNotEmpty) ...[
            _section('Race runs'),
            for (final s in runs) _sessionTile(s, false, best?.id == s.id),
          ],
          if (recces.isNotEmpty) ...[
            _section('Recces'),
            for (final s in recces) _sessionTile(s, s.id == prefs.refId, false),
          ],
          _section('Spoken notes'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Speak notes (check and race)'),
            subtitle: const Text('Through headphones if connected'),
            value: prefs.speak,
            onChanged: (v) {
              prefs.speak = v;
              _savePrefs();
            },
          ),
          Text('Speak ${prefs.lead.toStringAsFixed(1)} s before the corner'),
          Slider(
            min: 2,
            max: 7,
            divisions: 10,
            value: prefs.lead.clamp(2, 7).toDouble(),
            label: '${prefs.lead.toStringAsFixed(1)} s',
            onChanged: (v) => setState(() => prefs.lead = v),
            onChangeEnd: (_) => _savePrefs(),
          ),
          Text('Speech speed ${prefs.rate.toStringAsFixed(2)}'),
          Slider(
            min: 0.8,
            max: 1.6,
            divisions: 16,
            value: prefs.rate.clamp(0.8, 1.6).toDouble(),
            onChanged: (v) => setState(() => prefs.rate = v),
            onChangeEnd: (_) => _savePrefs(),
          ),
          OutlinedButton.icon(
            onPressed: () => c.speakTest(),
            icon: const Icon(Icons.headphones),
            label: const Text('Test: "left 3 minus long, 150"'),
          ),
        ],
      ),
    );
  }

  Widget _step(String no, String title, String text, IconData icon, VoidCallback? onTap,
      {Widget? extra, bool accent = false}) {
    return Card(
      color: kPanel,
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: onTap == null ? kLine : (accent ? kAccent : kGood),
              child: Text(no, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1)),
            const Spacer(),
            SizedBox(
              height: 52,
              width: 130,
              child: FilledButton.icon(
                onPressed: onTap,
                icon: Icon(icon),
                label: const Text('START', style: TextStyle(fontWeight: FontWeight.w900)),
                style: FilledButton.styleFrom(
                  backgroundColor: accent ? kAccent : kGood,
                  foregroundColor: Colors.black,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: kDim)),
          if (extra != null) ...[const SizedBox(height: 8), Align(alignment: Alignment.centerLeft, child: extra)],
        ]),
      ),
    );
  }

  Widget _sessionTile(SessionSummary s, bool isRef, bool isBest) {
    final d = DateTime.fromMillisecondsSinceEpoch(s.createdAt);
    String p(int n) => n.toString().padLeft(2, '0');
    final when = '${p(d.day)}.${p(d.month)} ${p(d.hour)}:${p(d.minute)}';
    final icon = switch (s.type) {
      SessionType.bike => Icons.pedal_bike,
      SessionType.car => Icons.directions_car,
      SessionType.run => Icons.timer,
      SessionType.check => Icons.hearing,
    };
    return Card(
      color: kPanel,
      child: ListTile(
        leading: Icon(icon, color: isRef ? kAccent : kDim),
        title: Text(
          '${s.name}${isRef ? '  · IN USE' : ''}${isBest ? '  · BEST' : ''}',
          style: TextStyle(fontWeight: FontWeight.w700, color: isBest ? kGood : kText),
        ),
        subtitle: Text('$when · ${fmtKm(s.distance)}${s.type == SessionType.run && !s.autoFinish ? ' · stopped by hand' : ''}'),
        trailing: Text(
          fmtRaceTime(s.durationMs),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFeatures: tabular),
        ),
        onTap: () => _open(s),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(title.toUpperCase(),
            style: const TextStyle(color: kAccent, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      );
}

String fmtKm(double metres) =>
    metres >= 1000 ? '${(metres / 1000).toStringAsFixed(2)} km' : '${metres.round()} m';
