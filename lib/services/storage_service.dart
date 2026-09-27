import 'package:shared_preferences/shared_preferences.dart';

import '../models/stats.dart';
import '../models/symbol.dart';

/// Persists everything that must survive an app restart.
///
/// Every read is defensive: a corrupt or partially written value falls back to
/// a sane default rather than crashing the game on launch, because losing a
/// stats screen is never worth a white screen.
class StorageService {
  StorageService(this._prefs);

  final SharedPreferences _prefs;

  static const String _kBalance = 'balance';
  static const String _kChip = 'selected_chip';
  static const String _kLastBets = 'last_bets';
  static const String _kStats = 'stats';
  static const String _kSound = 'sound_enabled';
  static const String _kHaptics = 'haptics_enabled';
  static const String _kAgeAck = 'age_acknowledged';

  static Future<StorageService> open() async =>
      StorageService(await SharedPreferences.getInstance());

  // ------------------------------------------------------------------ balance
  int loadBalance(int fallback) => _prefs.getInt(_kBalance) ?? fallback;

  Future<void> saveBalance(int value) => _prefs.setInt(_kBalance, value);

  // --------------------------------------------------------------------- chip
  int? loadSelectedChip() => _prefs.getInt(_kChip);

  Future<void> saveSelectedChip(int value) => _prefs.setInt(_kChip, value);

  // ---------------------------------------------------------------- last bets
  /// Reads the previous round's wagers so the player can repeat them.
  ///
  /// Persisted as a list of `"symbolName:amount"` strings rather than a map
  /// because SharedPreferences on some platforms mangles map values.
  Map<Symbol, int> loadLastBets() {
    final List<String>? raw = _prefs.getStringList(_kLastBets);
    if (raw == null) return <Symbol, int>{};

    final Map<Symbol, int> result = <Symbol, int>{};
    for (final String entry in raw) {
      final int split = entry.lastIndexOf(':');
      if (split <= 0) continue;
      final String name = entry.substring(0, split);
      final int? amount = int.tryParse(entry.substring(split + 1));
      if (amount == null || amount <= 0) continue;
      for (final Symbol s in Symbol.values) {
        if (s.name == name) {
          result[s] = amount;
          break;
        }
      }
    }
    return result;
  }

  Future<void> saveLastBets(Map<Symbol, int> bets) {
    final List<String> encoded = bets.entries
        .where((MapEntry<Symbol, int> e) => e.value > 0)
        .map((MapEntry<Symbol, int> e) => '${e.key.name}:${e.value}')
        .toList();
    return _prefs.setStringList(_kLastBets, encoded);
  }

  // -------------------------------------------------------------------- stats
  GameStats loadStats() {
    final String? raw = _prefs.getString(_kStats);
    if (raw == null) return const GameStats();

    final Map<String, Object?> values = <String, Object?>{};
    for (final String pair in raw.split(',')) {
      final int split = pair.lastIndexOf(':');
      if (split <= 0) continue;
      final int? parsed = int.tryParse(pair.substring(split + 1));
      if (parsed == null) continue;
      values[pair.substring(0, split)] = parsed;
    }
    return GameStats.fromMap(values);
  }

  Future<void> saveStats(GameStats stats) => _prefs.setString(
    _kStats,
    stats.toMap().entries
        .map((MapEntry<String, Object> e) => '${e.key}:${e.value}')
        .join(','),
  );

  // ------------------------------------------------------------------- toggles
  bool loadSoundEnabled(bool fallback) =>
      _prefs.getBool(_kSound) ?? fallback;

  Future<void> saveSoundEnabled(bool value) => _prefs.setBool(_kSound, value);

  bool loadHapticsEnabled(bool fallback) =>
      _prefs.getBool(_kHaptics) ?? fallback;

  Future<void> saveHapticsEnabled(bool value) =>
      _prefs.setBool(_kHaptics, value);

  // -------------------------------------------------------------- age gate ack
  bool get ageAcknowledged => _prefs.getBool(_kAgeAck) ?? false;

  Future<void> setAgeAcknowledged(bool value) =>
      _prefs.setBool(_kAgeAck, value);
}
