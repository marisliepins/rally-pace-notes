// Interop with web/rally.js, which owns the browser sensor APIs
// (motion permission, GPS watch, wake lock, keyboard/BLE-remote keys).
import 'dart:convert';
import 'dart:js_interop';

import 'trip.dart';

@JS('rallyGetMotion')
external JSArray<JSNumber>? _getMotion();

@JS('rallyDrainFixes')
external JSArray<JSNumber>? _drainFixes();

@JS('rallyDrainKeys')
external JSArray<JSString>? _drainKeys();

@JS('rallyStatus')
external JSString? _status();

@JS('rallyLoad')
external JSString? _load();

@JS('rallySave')
external JSString? _save(JSString value);

@JS('rallyStoreSet')
external JSString? _storeSet(JSString key, JSString value);

@JS('rallyStoreGet')
external JSString? _storeGet(JSString key);

@JS('rallyStoreRemove')
external void _storeRemove(JSString key);

@JS('rallySpeak')
external JSString? _speak(JSString text, JSNumber rate);

@JS('rallySpeakStop')
external void _speakStop();

@JS('rallyDownload')
external JSString? _download(JSString filename, JSString mime, JSString text);

class MotionSample {
  const MotionSample(this.gx, this.gy, this.gyro, this.hasGyro, this.count, [this.gz = 0]);
  final double gx;
  final double gy;
  final double gz;
  final List<double> gyro; // accumulated degrees per axis (alpha, beta, gamma)
  final bool hasGyro;
  final int count;
}

class Bridge {
  static MotionSample? motion() {
    try {
      final a = _getMotion();
      if (a == null) return null;
      final l = a.toDart.map((e) => e.toDartDouble).toList();
      if (l.length < 7) return null;
      return MotionSample(
          l[0], l[1], [l[2], l[3], l[4]], l[5] > 0.5, l[6].toInt(), l.length > 7 ? l[7] : 0.0);
    } catch (_) {
      return null;
    }
  }

  static List<Fix> drainFixes() {
    try {
      final a = _drainFixes();
      if (a == null) return const [];
      final l = a.toDart.map((e) => e.toDartDouble).toList();
      final out = <Fix>[];
      for (var i = 0; i + 4 < l.length; i += 5) {
        final speed = l[i + 3];
        out.add(Fix(l[i], l[i + 1], l[i + 2], speed >= 0 ? speed : null, l[i + 4]));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static List<String> drainKeys() {
    try {
      final a = _drainKeys();
      if (a == null) return const [];
      return a.toDart.map((e) => e.toDart).toList();
    } catch (_) {
      return const [];
    }
  }

  static Map<String, dynamic> status() {
    try {
      final s = _status();
      if (s == null) return const {};
      return jsonDecode(s.toDart) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  static String? load() {
    try {
      return _load()?.toDart;
    } catch (_) {
      return null;
    }
  }

  /// Saves to the phone and reads it back. Returns null on success,
  /// otherwise a short error message.
  static String? save(String value) {
    try {
      final r = _save(value.toJS)?.toDart ?? 'no answer from storage';
      return r.isEmpty ? null : r;
    } catch (e) {
      return 'storage error';
    }
  }

  /// Stores a value; null on success, else an error message.
  static String? storeSet(String key, String value) {
    try {
      final r = _storeSet(key.toJS, value.toJS)?.toDart ?? 'no answer from storage';
      return r.isEmpty ? null : r;
    } catch (_) {
      return 'storage error';
    }
  }

  static String? storeGet(String key) {
    try {
      final r = _storeGet(key.toJS)?.toDart;
      return (r == null || r.isEmpty) ? null : r;
    } catch (_) {
      return null;
    }
  }

  static void storeRemove(String key) {
    try {
      _storeRemove(key.toJS);
    } catch (_) {}
  }

  static void speak(String text, {double rate = 1.15}) {
    try {
      _speak(text.toJS, rate.toJS);
    } catch (_) {}
  }

  static void speakStop() {
    try {
      _speakStop();
    } catch (_) {}
  }

  /// null on success, else an error message.
  static String? download(String filename, String mime, String text) {
    try {
      final r = _download(filename.toJS, mime.toJS, text.toJS)?.toDart ?? '';
      return r.isEmpty ? null : r;
    } catch (_) {
      return 'export error';
    }
  }
}
