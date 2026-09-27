import 'dart:math';

import '../core/config.dart';
import '../models/symbol.dart';

/// The payout table: how much a wager earns for each number of matching dice.
///
/// This is the mathematical heart of the game, kept as a pure function of
/// `dart:core` alone so it can be exhaustively unit tested without a widget
/// tree, a device, or a random number generator.
///
/// ## Why bets need two or more matching dice
///
/// Six dice, each showing one of six symbols uniformly. For a wager on one
/// symbol the chance of exactly [k] matching dice is:
///
///     C(6, k) * (1/6)^k * (5/6)^(6-k)
///
/// which is 33.49% for k=0 and 40.19% for k=1 - together nearly 74% of all
/// rolls produce at most one match.
///
/// If a single match paid, expected value per unit wagered would be
/// **+0.6651**, i.e. the player would win two thirds of every coin forever. The
/// balance would grow without bound, the player would never run out of coins,
/// and the watch-an-ad refill would be dead code. That is a broken game, not a
/// generous one.
///
/// Requiring two matches to win and paying k x the stake for k >= 2 gives an
/// expected value of **-0.1387** per unit wagered: a return to player of
/// 86.13% and a house edge of 13.87%. Over thousands of rounds a player's
/// balance trends down towards zero, which is exactly what makes running out
/// of coins - and therefore the ad refill - a real event.
///
/// Both figures are asserted by test/payout_table_test.dart and the 86.13% RTP
/// is independently re-derived from scratch by a Monte-Carlo simulation in
/// test/dice_distribution_test.dart, so the table cannot silently drift away
/// from the documented economics.
class PayoutTable {
  const PayoutTable._();

  /// Net profit in coins for a wager of [stake] where [matches] of the dice
  /// showed the wagered symbol.
  ///
  /// Returns a negative number equal to `-stake` when the bet loses, and zero
  /// when no wager was actually placed.
  ///
  /// A bet wins only when [matches] reaches [AppConfig.minDiceToWin]. When it
  /// wins, the profit is [matches] times the stake, matching the traditional
  /// rule "if two, three, four, five or six of the dice display the symbol,
  /// the player wins twice, thrice, four, five or six times the stake".
  static int profitFor({required int stake, required int matches}) {
    if (stake <= 0) return 0;
    if (matches < AppConfig.minDiceToWin) return -stake;
    return stake * matches;
  }

  /// The payout multiplier for [matches] matching dice: k for k >= 2, and 0
  /// for a losing result.
  static int multiplierFor(int matches) {
    if (matches < AppConfig.minDiceToWin) return 0;
    return matches;
  }

  /// Exact probability that exactly [matches] of [AppConfig.diceCount] dice
  /// show one particular symbol, as a value in [0, 1].
  ///
  /// Computed with integer combinatorics and converted once, so results do not
  /// drift with floating point accumulation.
  static double probabilityOfMatches(int matches) {
    final int n = AppConfig.diceCount;
    if (matches < 0 || matches > n) return 0;
    final int favourable = _binomial(n, matches) * pow(5, n - matches).toInt();
    return favourable / pow(6, n).toDouble();
  }

  /// Return to player for a single-unit wager on one symbol, in [0, 1].
  ///
  /// This is 1 + expected value, and is the number quoted on the rules screen.
  static double get returnToPlayer {
    double ev = 0;
    for (int k = 0; k <= AppConfig.diceCount; k++) {
      ev += probabilityOfMatches(k) * profitFor(stake: 1, matches: k);
    }
    return 1 + ev;
  }

  /// House edge for a single-unit wager, in [0, 1]. Always
  /// `1 - returnToPlayer`.
  static double get houseEdge => 1 - returnToPlayer;

  static int _binomial(int n, int k) {
    int result = 1;
    for (int i = 0; i < k; i++) {
      result = result * (n - i) ~/ (i + 1);
    }
    return result;
  }
}
