import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../grading.dart';
import '../settings.dart';
import 'theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.c});
  final AppController c;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Settings _draft = widget.c.settings.copy();
  late List<TextEditingController> _anchorCtl;
  late TextEditingController _deadCtl;
  late TextEditingController _longCtl;
  late TextEditingController _superCtl;

  @override
  void initState() {
    super.initState();
    _bindControllers();
  }

  void _bindControllers() {
    _anchorCtl = [for (final a in _draft.anchors) TextEditingController(text: _num(a))];
    _deadCtl = TextEditingController(text: _num(_draft.deadZone));
    _longCtl = TextEditingController(text: _num(_draft.longCorner));
    _superCtl = TextEditingController(text: _num(_draft.superLongCorner));
  }

  @override
  void dispose() {
    for (final t in _anchorCtl) {
      t.dispose();
    }
    _deadCtl.dispose();
    _longCtl.dispose();
    _superCtl.dispose();
    super.dispose();
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  double? _parse(String s) => double.tryParse(s.replaceAll(',', '.').trim());

  void _readFields() {
    for (var i = 0; i < 6; i++) {
      final v = _parse(_anchorCtl[i].text);
      if (v != null) _draft.anchors[i] = v;
    }
    _draft.deadZone = _parse(_deadCtl.text) ?? _draft.deadZone;
    _draft.longCorner = _parse(_longCtl.text) ?? _draft.longCorner;
    _draft.superLongCorner = _parse(_superCtl.text) ?? _draft.superLongCorner;
  }

  void _save() {
    _readFields();
    for (var i = 0; i < 6; i++) {
      if (_parse(_anchorCtl[i].text) == null) {
        return _error('Grade angle ${i + 1} is not a number.');
      }
    }
    final err = validateAnchors(_draft.anchors, _draft.deadZone);
    if (err != null) return _error(err);
    if (_draft.superLongCorner <= _draft.longCorner) {
      return _error('"Super long" must be longer than "long".');
    }
    widget.c.saveSettings(_draft);
    Navigator.of(context).pop();
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: kBad),
    );
  }

  void _restoreDefaults() {
    setState(() {
      for (final t in _anchorCtl) {
        t.dispose();
      }
      _deadCtl.dispose();
      _longCtl.dispose();
      _superCtl.dispose();
      _draft = Settings();
      _bindControllers();
    });
  }

  @override
  Widget build(BuildContext context) {
    const unitLen = 'm';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _save, child: const Text('SAVE')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _livePreview(),
          _section('Corner grades'),
          SegmentedButton<GradeMode>(
            segments: const [
              ButtonSegment(value: GradeMode.oneToSix, label: Text('1 → 6  (6 = sharpest)')),
              ButtonSegment(value: GradeMode.sixToOne, label: Text('6 → 1  (1 = sharpest)')),
            ],
            selected: {_draft.mode},
            onSelectionChanged: (v) => setState(() => _draft.mode = v.first),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < 6; i++) _anchorRow(i),
          const SizedBox(height: 8),
          Text('"+" / "−" zone: plain grade within ±${_draft.zonePercent.round()}% of the gap around each angle',
              style: const TextStyle(color: kDim)),
          Slider(
            min: 5,
            max: 40,
            divisions: 35,
            value: _draft.zonePercent.clamp(5, 40).toDouble(),
            label: '${_draft.zonePercent.round()}%',
            onChanged: (v) => setState(() => _draft.zonePercent = v),
          ),
          _numberField('Straight (no grade) below', _deadCtl, '°'),
          _section('Corner length'),
          _numberField('LONG from', _longCtl, unitLen),
          _numberField('SUPER LONG from', _superCtl, unitLen),
          _section('Display'),
          SwitchListTile(
            title: const Text('Imperial units (mi, yd, mph)'),
            value: _draft.imperial,
            onChanged: (v) => setState(() => _draft.imperial = v),
          ),
          SwitchListTile(
            title: const Text('Show speed'),
            value: _draft.showSpeed,
            onChanged: (v) => setState(() => _draft.showSpeed = v),
          ),
          ListTile(
            title: const Text('Landscape rotation'),
            subtitle: const Text('Used when the iPhone is portrait-locked. Pick the one that reads upright on the wheel.'),
            trailing: DropdownButton<int>(
              value: _draft.rotation,
              items: const [
                DropdownMenuItem(value: 1, child: Text('Rotate right')),
                DropdownMenuItem(value: 3, child: Text('Rotate left')),
                DropdownMenuItem(value: 0, child: Text('Off')),
              ],
              onChanged: (v) => setState(() => _draft.rotation = v ?? 1),
            ),
          ),
          _section('Steering sensor'),
          SwitchListTile(
            title: const Text('Swap left / right'),
            subtitle: const Text('Turn on if a left turn shows R'),
            value: _draft.invertDirection,
            onChanged: (v) => setState(() => _draft.invertDirection = v),
          ),
          SwitchListTile(
            title: const Text('Use gyroscope'),
            subtitle: const Text('Smoother and less affected by cornering forces'),
            value: _draft.useGyro,
            onChanged: (v) => setState(() => _draft.useGyro = v),
          ),
          ListTile(
            title: Text('Smoothing: ${_draft.smoothing.toStringAsFixed(1)} s'),
            subtitle: Slider(
              min: 0.2,
              max: 3,
              divisions: 28,
              value: _draft.smoothing.clamp(0.2, 3).toDouble(),
              onChanged: (v) => setState(() => _draft.smoothing = v),
            ),
          ),
          _section('Status'),
          ListenableBuilder(
            listenable: widget.c,
            builder: (context, _) {
              final s = widget.c.status;
              return Text(
                'Motion: ${s['motion'] ?? '-'}\n'
                'GPS: ${s['geo'] ?? '-'}\n'
                'Screen awake: ${s['wake'] ?? '-'}\n'
                'Gyro axis: ${widget.c.steering.gyroInfo}',
                style: const TextStyle(color: kDim, height: 1.5),
              );
            },
          ),
          const SizedBox(height: 24),
          OutlinedButton(onPressed: _restoreDefaults, child: const Text('Restore default values')),
          const SizedBox(height: 12),
          const Text(
            'Remote / keyboard: Space, Enter, → or ↓ = next segment.  ← ↑ Backspace or Esc = reset all.',
            style: TextStyle(color: kDim),
          ),
        ],
      ),
    );
  }

  Widget _livePreview() {
    return ListenableBuilder(
      listenable: widget.c,
      builder: (context, _) {
        _readFieldsSilently();
        final angle = widget.c.angle;
        final call = _draft.gradeConfig.callFor(angle);
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Text(call, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: kText)),
              const SizedBox(width: 16),
              Text('${angle.abs().round()}°',
                  style: const TextStyle(fontSize: 24, color: kDim, fontFeatures: tabular)),
              const Spacer(),
              OutlinedButton(onPressed: widget.c.setZero, child: const Text('ZERO')),
            ],
          ),
        );
      },
    );
  }

  /// Live preview uses whatever is typed so far.
  void _readFieldsSilently() {
    for (var i = 0; i < 6; i++) {
      final v = _parse(_anchorCtl[i].text);
      if (v != null) _draft.anchors[i] = v;
    }
    _draft.deadZone = _parse(_deadCtl.text) ?? _draft.deadZone;
  }

  Widget _anchorRow(int i) {
    final label = _draft.gradeConfig.numberAt(i);
    final hint = i == 0 ? 'gentlest' : (i == 5 ? 'sharpest' : '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text('Grade $label', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          SizedBox(width: 72, child: Text(hint, style: const TextStyle(color: kDim))),
          SizedBox(
            width: 110,
            child: TextField(
              controller: _anchorCtl[i],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              decoration: const InputDecoration(suffixText: '°', isDense: true, border: OutlineInputBorder()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberField(String label, TextEditingController ctl, String suffix) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            SizedBox(
              width: 150,
              child: TextField(
                controller: ctl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                decoration: InputDecoration(suffixText: suffix, isDense: true, border: const OutlineInputBorder()),
              ),
            ),
          ],
        ),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(title.toUpperCase(),
            style: const TextStyle(color: kAccent, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      );
}
