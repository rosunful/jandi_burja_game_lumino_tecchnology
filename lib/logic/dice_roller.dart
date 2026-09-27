import 'dart:math';

import '../core/config.dart';
import '../models/symbol.dart';

/// Throws dice and returns the resulting faces.
///
/// The generator is injectable so that tests can pin an exact sequence, while
/// the app itself uses [Random.secure] backed by the platform CSPRNG. Rolls
/// must not be predictable, and a real casino would not accept `Random()`.
class DiceRoller {
  DiceRoller({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;

  /// Rolls [AppConfig.diceCount] dice and returns the face showing on each.
  List<Symbol> roll() {
    return List<Symbol>.generate(
      AppConfig.diceCount,
      (_) => Symbol.values[_random.nextInt(Symbol.values.length)],
      growable: false,
    );
  }

  /// Counts how many of [faces] show [symbol].
  static int countOf(Symbol symbol, List<Symbol> faces) {
    int count = 0;
    for (final Symbol face in faces) {
      if (face == symbol) count++;
    }
    return count;
  }
}
