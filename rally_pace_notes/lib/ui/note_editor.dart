import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../sprint/edit.dart';
import '../sprint/models.dart';
import '../sprint/stenogram.dart';
import 'theme.dart';

class NoteEditResult {
  NoteEditResult(this.notes, this.total);
  final List<Note> notes;
  final double total;
}

/// Big-button editor for one note. Works on a copy; returns the changed
/// list (and finish distance) on SAVE, or null on cancel.
Future<NoteEditResult?> showNoteEditor(
  BuildContext context, {
  required AppController c,
  required Session session,
  required int index,
}) {
  return showModalBottomSheet<NoteEditResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kBg,
    builder: (_) => _NoteEditor(c: c, session: session, index: index),
  );
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({required this.c, required this.session, required this.index});
  final AppController c;
  final Session session;
  final int index;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late List<Note> notes = [for (final n in widget.session.notes) n.copy()];
  late double total = widget.session.distance;
  late int i = widget.index;
  CallParts? parts;
  final TextEditingController _extra = TextEditingController();
  final TextEditingController _group = TextEditingController();
  bool _textChanged = false;

  String Function(double) get _label => widget.c.settings.lengthLabel;

  @override
  void initState() {
    super.initState();
    _loadParts();
  }

  @override
  void dispose() {
    _extra.dispose();
    _group.dispose();
    super.dispose();
  }

  Note get n => notes[i];

  void _loadParts() {
    if (n.group) {
      parts = null;
      _group.text = n.text;
    } else {
      parts = parseCall(n.text) ?? CallParts('L', '1', '', '');
      _extra.text = parts!.extra;
    }
    _textChanged = false;
  }

  /// Writes the buttons/text into the note.
  void _apply() {
    final p = parts;
    if (p != null) {
      p.extra = _extra.text;
      final composed = composeCall(p, n.length, _label);
      if (_textChanged || composed != n.text) n.custom = composed;
    } else {
      final t = _group.text.trim();
      if (t.isNotEmpty && t != n.text) n.custom = t;
    }
    n.flagged = false;
  }

  void _set(VoidCallback f) => setState(() {
        f();
        _textChanged = true;
      });

  void _save() {
    _apply();
    Navigator.pop(context, NoteEditResult(notes, total));
  }

  void _msg(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: kBad));

  @override
  Widget build(BuildContext context) {
    final p = parts;
    final straight = straightBefore(notes, i);
    final label = _label(n.length).toLowerCase();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Text('NOTE ${i + 1} of ${notes.length}',
                    style: const TextStyle(color: kAccent, fontWeight: FontWeight.w800, letterSpacing: 1)),
                const Spacer(),
                Text('measured: ${n.call}', style: const TextStyle(color: kDim)),
              ]),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  p != null ? composeCall(p..extra = _extra.text, n.length, _label) : _group.text,
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 8),
              if (p != null) ...[
                Row(children: [
                  for (final d in const ['L', 'R'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: _choice(d == 'L' ? 'LEFT' : 'RIGHT', p.dir == d, () => _set(() => p.dir = d),
                            color: d == 'L' ? kLeft : kRight, height: 56),
                      ),
                    ),
                ]),
                Row(children: [
                  for (var g = 1; g <= 6; g++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: _choice('$g', p.grade == '$g', () => _set(() => p.grade = '$g'), height: 60),
                      ),
                    ),
                ]),
                Row(children: [
                  for (final m in const ['-', '', '+'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: _choice(m.isEmpty ? '·' : (m == '-' ? '−' : '+'), p.mod == m,
                            () => _set(() => p.mod = m), height: 52),
                      ),
                    ),
                ]),
                const SizedBox(height: 6),
                TextField(
                  controller: _extra,
                  onChanged: (_) => setState(() => _textChanged = true),
                  decoration: const InputDecoration(
                      labelText: 'Extra words (optional)', hintText: 'caution, don\'t cut, over crest',
                      border: OutlineInputBorder(), isDense: true),
                ),
              ] else
                TextField(
                  controller: _group,
                  onChanged: (_) => setState(() => _textChanged = true),
                  decoration: const InputDecoration(
                      labelText: 'Group / chicane', hintText: 'R3L2R4', border: OutlineInputBorder()),
                ),
              const SizedBox(height: 14),
              _stepper('Straight before', straight, (v) => setState(() {
                    total = setStraightBefore(notes, i, v, total);
                  })),
              _stepper('Corner length${label.isEmpty ? '' : ' ($label)'}', n.length, (v) => setState(() {
                    total = setLength(notes, i, v, total);
                  })),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton(
                  onPressed: () => setState(() {
                    n.custom = null;
                    _loadParts();
                  }),
                  child: const Text('Use measured'),
                ),
                OutlinedButton(
                  onPressed: i + 1 < notes.length
                      ? () => setState(() {
                            _apply();
                            mergeWithNext(notes, i);
                            _loadParts();
                          })
                      : null,
                  child: const Text('Merge with next'),
                ),
                if (n.group)
                  OutlinedButton(
                    onPressed: () => setState(() {
                      if (!splitNote(notes, i, widget.session.corners, widget.c.gradeConfig, _label)) {
                        _msg('Nothing to split here');
                      }
                      _loadParts();
                    }),
                    child: const Text('Split group'),
                  ),
                OutlinedButton(
                  onPressed: () => setState(() {
                    _apply();
                    i = insertAfter(notes, i, total);
                    _loadParts();
                  }),
                  child: const Text('Insert note after'),
                ),
                OutlinedButton(
                  onPressed: () {
                    notes.removeAt(i);
                    Navigator.pop(context, NoteEditResult(notes, total));
                  },
                  child: const Text('Delete note', style: TextStyle(color: kBad)),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: const Text('CANCEL'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52), backgroundColor: kGood, foregroundColor: Colors.black),
                    child: const Text('SAVE', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choice(String text, bool on, VoidCallback onTap, {Color color = kAccent, double height = 52}) {
    return SizedBox(
      height: height,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: on ? color : kPanel,
          foregroundColor: on ? Colors.black : kText,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      ),
    );
  }

  /// "−10 −5 [ 120 m ] +5 +10"
  Widget _stepper(String label, double value, ValueChanged<double> onChanged) {
    Widget b(String t, double d) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: SizedBox(
            width: 52,
            height: 44,
            child: OutlinedButton(
              onPressed: () => onChanged(value + d),
              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
        b('−10', -10),
        b('−5', -5),
        SizedBox(
          width: 76,
          child: Text('${value.round()} m',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFeatures: tabular)),
        ),
        b('+5', 5),
        b('+10', 10),
      ]),
    );
  }
}
