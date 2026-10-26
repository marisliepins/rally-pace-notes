import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../settings.dart';
import '../sprint/models.dart';
import '../sprint/recorder.dart';
import '../sprint/stenogram.dart';
import 'session_detail.dart';
import 'theme.dart';

/// Recce, check drive or race run. Landscape on the wheel, like the main
/// screen. START arms; the clock starts when you move off. Check drives and
/// runs stop by themselves at the finish line (or with STOP).
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.c, required this.type});
  final AppController c;
  final SessionType type;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  AppController get c => widget.c;
  bool _leaving = false;

  bool get _usesNotes => widget.type == SessionType.run || widget.type == SessionType.check;

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

  /// Opens the notes (editor) in place of this screen.
  void _openNotes(String id) {
    if (_leaving) return;
    _leaving = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => SessionDetailScreen(c: c, id: id),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          // After a recce, go straight to its notes.
          final r = c.recorder;
          final done = c.lastSession;
          if (widget.type == SessionType.car &&
              r != null &&
              r.state == RecState.finished &&
              done != null &&
              c.lastSaveError == null &&
              !_leaving) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _openNotes(done.id);
            });
          }
          return LayoutBuilder(builder: (context, box) {
            final portrait = box.maxHeight > box.maxWidth;
            Widget content = _content();
            if (portrait && c.settings.rotation != 0) {
              content = RotatedBox(quarterTurns: c.settings.rotation, child: content);
            }
            return SafeArea(child: content);
          });
        },
      ),
    );
  }

  String get _title {
    final ref = c.sprint.reference?.name ?? '—';
    return switch (widget.type) {
      SessionType.run => '${c.sprint.nextName(SessionType.run).toUpperCase()} · notes: $ref',
      SessionType.check => 'CHECK DRIVE · notes: $ref · tap the screen on a wrong note',
      _ => c.sprint.nextName(widget.type).toUpperCase(),
    };
  }

  Widget _content() {
    final r = c.recorder;
    final state = r?.state ?? RecState.idle;
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final elapsed = r?.elapsedMs(now) ?? 0;
    final s = c.settings;
    final since = DateTime.now().difference(c.eventAt).inMilliseconds;
    final tapToFlag = widget.type == SessionType.check && state == RecState.running;

    Widget main = Row(children: [
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
    ]);
    if (tapToFlag) {
      main = GestureDetector(behavior: HitTestBehavior.opaque, onTap: c.flagCurrentNote, child: main);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(
        children: [
          Row(children: [
            IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back), color: kDim),
            Flexible(
              child: Text(_title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kDim, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
            const SizedBox(width: 12),
            if (since < c.eventMs)
              Flexible(
                child: Text(c.eventText,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kAccent, fontWeight: FontWeight.w800, fontSize: 18)),
              ),
            const SizedBox(width: 12),
            _gpsChip(),
          ]),
          Expanded(child: main),
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

  /// Run / check: the next note. Recce: the live grade and corners found.
  Widget _rightPanel(Recorder? r) {
    final cfg = c.gradeConfig;
    if (_usesNotes) {
      final ahead = r?.noteAhead();
      final notes = r?.notes ?? c.sprint.reference?.notes ?? const <Note>[];
      final nextText = ahead == null ? (notes.isEmpty ? '—' : notes.first.text) : ahead.$1.text;
      final dist = ahead?.$2;
      final marked = widget.type == SessionType.check ? (r?.flaggedCount ?? 0) : 0;
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
              'live ${cfg.callFor(c.angle)}  ${c.angle.abs().round()}°'
              '${widget.type == SessionType.check ? '  ·  marked: $marked' : ''}',
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
          const Text('CORNER (steering)',
              style: TextStyle(color: kDim, fontWeight: FontWeight.w800, letterSpacing: 1)),
          Expanded(
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              child: Text(cfg.callFor(a),
                  style: TextStyle(fontSize: 90, fontWeight: FontWeight.w800, color: a >= 0 ? kLeft : kRight)),
            ),
          ),
          Text('${a.abs().round()}° · $count corners recorded',
              style: const TextStyle(color: kDim, fontSize: 18, fontFeatures: tabular)),
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
        return _wide(_usesNotes ? 'STOP (auto at finish)' : 'STOP AT FINISH', kBad, c.stopRecording);
      case RecState.finished:
        final err = c.lastSaveError;
        if (widget.type == SessionType.check) {
          final n = r?.flaggedCount ?? 0;
          return _doneRow(
            err != null ? 'MARKS NOT SAVED: $err' : '✓ CHECK DONE · $n ${n == 1 ? 'note' : 'notes'} marked',
            err == null,
            'EDIT NOTES',
            () {
              final id = c.sprint.prefs.refId;
              if (id != null) _openNotes(id);
            },
          );
        }
        final s = c.lastSession;
        final text = err != null
            ? 'NOT SAVED: $err'
            : s == null
                ? 'Saving…'
                : '✓ SAVED ${s.name.toUpperCase()} · ${fmtRaceTime(s.durationMs)}'
                    '${s.type == SessionType.run ? (s.autoFinish ? ' · finish line' : ' · stopped by hand') : ' · ${s.notes.length} notes'}';
        if (widget.type == SessionType.run) {
          return _doneRow(text, err == null, 'NEXT RUN', () {
            c.closeRecorder();
            c.startRecording(SessionType.run);
          });
        }
        return _doneRow(text, err == null, 'NOTES', () {
          if (s != null) _openNotes(s.id);
        });
    }
  }

  Widget _doneRow(String text, bool ok, String button, VoidCallback onTap) => Row(children: [
        Expanded(
          flex: 3,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(color: ok ? kGood : kBad, borderRadius: BorderRadius.circular(12)),
            child: Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _wide(button, kAccent, onTap)),
      ]);

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
          child: FittedBox(child: Text(text, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900))),
        ),
      );
}
