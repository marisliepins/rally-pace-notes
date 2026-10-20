import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../settings.dart';
import '../sprint/models.dart';
import '../sprint/recorder.dart';
import '../sprint/stenogram.dart';
import 'theme.dart';

/// Recording / race screen. Landscape on the wheel or handlebar, like the
/// main screen. START arms; the clock starts when you move off. Runs stop
/// by themselves at the finish line (or with STOP).
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.c, required this.type});
  final AppController c;
  final SessionType type;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  AppController get c => widget.c;

  @override
  void dispose() {
    c.closeRecorder();
    super.dispose();
  }

  void _back() {
    final r = c.recorder;
    if (r != null && r.state == RecState.running) {
      c.flash('Press STOP first');
      return;
    }
    Navigator.of(context).pop();
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
    final r = c.recorder;
    final state = r?.state ?? RecState.idle;
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final elapsed = r?.elapsedMs(now) ?? 0;
    final s = c.settings;
    final since = DateTime.now().difference(c.eventAt).inMilliseconds;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(
        children: [
          // ---- top line
          Row(children: [
            IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back), color: kDim),
            Text(
              widget.type == SessionType.run
                  ? '${c.sprint.nextName(SessionType.run).toUpperCase()} · notes: ${c.sprint.reference?.name ?? '—'}'
                  : c.sprint.nextName(widget.type).toUpperCase(),
              style: const TextStyle(color: kDim, fontWeight: FontWeight.w700, letterSpacing: 1),
            ),
            const Spacer(),
            if (since < c.eventMs)
              Text(c.eventText, style: const TextStyle(color: kAccent, fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            _gpsChip(),
          ]),
          // ---- main
          Expanded(
            child: Row(children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          fmtRaceTime(elapsed),
                          style: TextStyle(
                            fontSize: 120,
                            fontWeight: FontWeight.w800,
                            color: state == RecState.running ? kText : kDim,
                            fontFeatures: tabular,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${fmtSpeed(c.trip.speed, s.imperial)}   ${fmtShort(r?.trackPos ?? 0, s.imperial)}'
                          '${(r?.refDistance ?? 0) > 0 ? ' / ${fmtShort(r!.refDistance, s.imperial)}' : ''}',
                          style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w700, color: kText, fontFeatures: tabular),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 4, child: _rightPanel(r)),
            ]),
          ),
          // ---- buttons
          SizedBox(height: 76, child: _controls(r, state)),
        ],
      ),
    );
  }

  Widget _gpsChip() {
    final acc = c.trip.accuracy;
    final age = c.trip.lastFixAt == null ? 999 : DateTime.now().difference(c.trip.lastFixAt!).inSeconds;
    final ok = acc != null && age <= 5;
    final color = !ok ? kWarn : (acc <= 10 ? kGood : (acc <= 25 ? kWarn : kBad));
    return Text(ok ? 'GPS ±${acc.round()} m' : 'GPS …',
        style: TextStyle(color: color, fontWeight: FontWeight.w700));
  }

  /// Run: the next note. Recce: the live grade and corners found.
  Widget _rightPanel(Recorder? r) {
    final cfg = c.gradeConfig;
    if (widget.type == SessionType.run) {
      final ahead = r?.noteAhead();
      final notes = r?.notes ?? c.sprint.reference?.notes ?? const <Note>[];
      final nextText = ahead == null
          ? (notes.isEmpty ? '—' : notes.first.text)
          : ahead.$1.text;
      final dist = ahead == null ? null : ahead.$2;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kAccent, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dist == null ? 'NEXT' : (dist > 0 ? 'NEXT · in ${roundCall(dist)} m' : 'NOW'),
              style: const TextStyle(color: kAccent, fontWeight: FontWeight.w800, letterSpacing: 1),
            ),
            Expanded(
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                child: Text(nextText,
                    style: const TextStyle(fontSize: 90, fontWeight: FontWeight.w800, color: kText)),
              ),
            ),
            Text(
              'live ${cfg.callFor(c.angle)}  ${c.angle.abs().round()}°',
              style: const TextStyle(color: kDim, fontSize: 18, fontFeatures: tabular),
            ),
          ],
        ),
      );
    }
    final a = c.recordDisplayAngle;
    final count = r?.corners.length ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.type == SessionType.bike ? 'CORNER (from radius)' : 'CORNER (steering)',
            style: const TextStyle(color: kDim, fontWeight: FontWeight.w800, letterSpacing: 1),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              child: Text(cfg.callFor(a),
                  style: TextStyle(
                      fontSize: 90,
                      fontWeight: FontWeight.w800,
                      color: a >= 0 ? kLeft : kRight)),
            ),
          ),
          Text(
            '${a.abs().round()}° · $count corners recorded'
            '${widget.type == SessionType.bike && !c.bike.signLearned ? ' · L/R learning' : ''}',
            style: const TextStyle(color: kDim, fontSize: 18, fontFeatures: tabular),
          ),
        ],
      ),
    );
  }

  Widget _controls(Recorder? r, RecState state) {
    switch (state) {
      case RecState.idle:
        return _wide('START', kGood, () => c.startRecording(widget.type));
      case RecState.armed:
        return Row(children: [
          Expanded(
            flex: 3,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(12)),
              child: const Text('ARMED · clock starts when you move off',
                  style: TextStyle(color: kWarn, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: _wide('CANCEL', kLine, c.stopRecording)),
        ]);
      case RecState.running:
        return _wide(widget.type == SessionType.run ? 'STOP (auto at finish)' : 'STOP AT FINISH', kBad,
            c.stopRecording);
      case RecState.finished:
        final s = c.lastSession;
        final err = c.lastSaveError;
        final text = err != null
            ? 'NOT SAVED: $err'
            : s == null
                ? 'Saving…'
                : '✓ SAVED ${s.name.toUpperCase()} · ${fmtRaceTime(s.durationMs)}'
                    '${s.type == SessionType.run ? (s.autoFinish ? ' · finish line' : ' · stopped by hand') : ' · ${s.notes.length} notes'}';
        return Row(children: [
          Expanded(
            flex: 3,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: err == null ? kGood : kBad, borderRadius: BorderRadius.circular(12)),
              child: Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _wide(widget.type == SessionType.run ? 'NEXT RUN' : 'DONE', kAccent, () {
              if (widget.type == SessionType.run) {
                c.closeRecorder();
                c.startRecording(SessionType.run);
              } else {
                Navigator.of(context).pop();
              }
            }),
          ),
        ]);
    }
  }

  Widget _wide(String text, Color color, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: color == kLine ? kText : Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(text, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        ),
      );
}
