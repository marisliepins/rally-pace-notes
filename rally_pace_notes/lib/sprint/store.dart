import 'dart:convert';

import '../bridge.dart';
import 'models.dart';

/// Sprint preferences (kept apart from the main settings).
class SprintPrefs {
  SprintPrefs({
    this.speak = true,
    this.lead = 4,
    this.rate = 1.15,
    this.steeringRatio = 15,
    this.wheelbase = 2.5,
    this.refId,
  });

  bool speak;

  /// Seconds before a corner that its note is spoken.
  double lead;

  /// Speech speed (1 = normal).
  double rate;

  /// Car used to turn bike corners into steering angles.
  double steeringRatio;
  double wheelbase;

  /// Recce whose stenogram runs use.
  String? refId;

  Map<String, dynamic> toJson() => {
        'speak': speak,
        'lead': lead,
        'rate': rate,
        'steeringRatio': steeringRatio,
        'wheelbase': wheelbase,
        if (refId != null) 'refId': refId,
      };

  static SprintPrefs fromJson(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return SprintPrefs(
      speak: j['speak'] != false,
      lead: d('lead', 4),
      rate: d('rate', 1.15),
      steeringRatio: d('steeringRatio', 15),
      wheelbase: d('wheelbase', 2.5),
      refId: j['refId'] as String?,
    );
  }
}

/// Saves sessions on the phone: an index of summaries plus one entry per
/// session.
class SprintStore {
  static const _indexKey = 'rally.sprint.index';
  static const _prefsKey = 'rally.sprint.prefs';
  static String _key(String id) => 'rally.sprint.s.$id';

  List<SessionSummary> index = [];
  SprintPrefs prefs = SprintPrefs();

  void load() {
    final raw = Bridge.storeGet(_indexKey);
    if (raw != null) {
      try {
        index = (jsonDecode(raw) as List).map(SessionSummary.fromJson).toList();
      } catch (_) {
        index = [];
      }
    }
    final p = Bridge.storeGet(_prefsKey);
    if (p != null) {
      try {
        prefs = SprintPrefs.fromJson(jsonDecode(p) as Map<String, dynamic>);
      } catch (_) {}
    }
    if (prefs.refId != null && !index.any((s) => s.id == prefs.refId)) {
      prefs.refId = null;
    }
  }

  String? savePrefs() => Bridge.storeSet(_prefsKey, jsonEncode(prefs.toJson()));

  String? _saveIndex() =>
      Bridge.storeSet(_indexKey, jsonEncode(index.map((s) => s.toJson()).toList()));

  /// null on success, else an error message.
  String? save(Session s) {
    final err = Bridge.storeSet(_key(s.id), jsonEncode(s.toJson()));
    if (err != null) return err;
    if (_refCache?.id == s.id) _refCache = s;
    index.removeWhere((x) => x.id == s.id);
    index.add(s.summary);
    index.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return _saveIndex();
  }

  Session? get(String id) {
    final raw = Bridge.storeGet(_key(id));
    if (raw == null) return null;
    try {
      return Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  void delete(String id) {
    Bridge.storeRemove(_key(id));
    if (_refCache?.id == id) _refCache = null;
    index.removeWhere((x) => x.id == id);
    if (prefs.refId == id) {
      prefs.refId = null;
      savePrefs();
    }
    _saveIndex();
  }

  Session? _refCache;

  /// The recce whose notes runs use (cached: the screens ask every frame).
  Session? get reference {
    final id = prefs.refId;
    if (id == null) return null;
    if (_refCache?.id != id) _refCache = get(id);
    return _refCache;
  }

  /// Next name for a new session of this type: "Run 3", "Bike recce 1"...
  String nextName(SessionType t) {
    final n = index.where((s) => s.type == t).length + 1;
    return '${t.label} $n';
  }

  /// Fastest run that used this reference.
  SessionSummary? bestRun(String? refId) {
    SessionSummary? best;
    for (final s in index) {
      if (s.type != SessionType.run || s.refId != refId || s.durationMs <= 0) continue;
      if (best == null || s.durationMs < best.durationMs) best = s;
    }
    return best;
  }
}
