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

  @override
  Widget build(BuildContext context) {
    final store = c.sprint;
    final prefs = store.prefs;
    final ref = store.index.where((s) => s.id == prefs.refId).firstOrNull;
    final best = store.bestRun(prefs.refId);
    return Scaffold(
      appBar: AppBar(title: const Text('Sprint')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _section('Record'),
          Row(children: [
            Expanded(child: _bigButton('BIKE\nRECCE', Icons.pedal_bike, () => _record(SessionType.bike))),
            const SizedBox(width: 10),
            Expanded(child: _bigButton('CAR\nRECCE', Icons.directions_car, () => _record(SessionType.car))),
            const SizedBox(width: 10),
            Expanded(
              child: _bigButton('RUN', Icons.timer, ref == null ? null : () => _record(SessionType.run),
                  accent: true),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            ref == null
                ? 'Record a bike or car recce first. Its notes are spoken during runs.'
                : 'Runs use the notes from: ${ref.name} (${fmtKm(ref.distance)})'
                    '${best == null ? '' : '  ·  best run ${fmtRaceTime(best.durationMs)}'}',
            style: const TextStyle(color: kDim),
          ),
          _section('Sessions'),
          if (store.index.isEmpty)
            const Text('No sessions yet.', style: TextStyle(color: kDim))
          else
            for (final s in store.index) _sessionTile(s, s.id == prefs.refId, best?.id == s.id),
          _section('Spoken notes'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Speak notes during runs'),
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
          _section('Bike recce grading'),
          const Text(
            'On the bike, corners are graded from their radius as the steering angle your car '
            'would need. Set your car here.',
            style: TextStyle(color: kDim),
          ),
          _numberRow('Steering ratio', prefs.steeringRatio, ':1', (v) {
            prefs.steeringRatio = v;
            _savePrefs();
          }),
          _numberRow('Wheelbase', prefs.wheelbase, 'm', (v) {
            prefs.wheelbase = v;
            _savePrefs();
          }),
        ],
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
    };
    return Card(
      color: kPanel,
      child: ListTile(
        leading: Icon(icon, color: isRef ? kAccent : kDim),
        title: Text(
          '${s.name}${isRef ? '  · NOTES' : ''}${isBest ? '  · BEST' : ''}',
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

  Widget _bigButton(String text, IconData icon, VoidCallback? onTap, {bool accent = false}) {
    return SizedBox(
      height: 96,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: accent ? kAccent : kPanel,
          foregroundColor: accent ? Colors.black : kText,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 28),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _numberRow(String label, double value, String suffix, ValueChanged<double> onDone) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(label)),
        SizedBox(
          width: 130,
          child: TextFormField(
            initialValue: value.toString(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            decoration: InputDecoration(suffixText: suffix, isDense: true, border: const OutlineInputBorder()),
            onChanged: (t) {
              final v = double.tryParse(t.replaceAll(',', '.').trim());
              if (v != null && v > 0) onDone(v);
            },
          ),
        ),
      ]),
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
