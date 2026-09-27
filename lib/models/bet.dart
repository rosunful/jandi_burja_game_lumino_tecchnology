import '../models/symbol.dart';

/// A single wager: [amount] coins placed on [symbol].
class Bet {
  const Bet({required this.symbol, required this.amount});

  final Symbol symbol;
  final int amount;

  Bet copyWith({int? amount}) =>
      Bet(symbol: symbol, amount: amount ?? this.amount);

  @override
  bool operator ==(Object other) =>
      other is Bet && other.symbol == symbol && other.amount == amount;

  @override
  int get hashCode => Object.hash(symbol, amount);

  @override
  String toString() => 'Bet(${symbol.name}: $amount)';
}

/// The settled outcome of one wager after a roll.
class BetResult {
  const BetResult({
    required this.bet,
    required this.matches,
    required this.profit,
  });

  final Bet bet;

  /// How many of the rolled dice showed [Bet.symbol].
  final int matches;

  /// Net change in coins: positive on a win, equal to `-Bet.amount` on a loss.
  final int profit;

  bool get won => profit > 0;
}

/// Everything produced by one round: the dice, each wager's result, and the
/// net effect on the player's balance.
class RoundResult {
  const RoundResult({
    required this.faces,
    required this.results,
    required this.totalStake,
    required this.netChange,
  });

  final List<Symbol> faces;
  final List<BetResult> results;

  /// Sum of all wagers placed this round.
  final int totalStake;

  /// Sum of every wager's [BetResult.profit]. Negative means the round lost
  /// coins, positive means it won.
  final int netChange;

  bool get won => netChange > 0;

  /// True when the player lost every wager, the common case at this RTP.
  bool get lostEverything => netChange < 0 && totalStake > 0;

  /// Coins actually paid back to the player: a winning wager returns its stake
  /// plus the profit, a losing wager returns nothing.
  ///
  /// This is the numerator of the observed return to player, so it must count
  /// returned stakes. It is deliberately *not* [netChange]: summing profits
  /// alone would report a "return" of -13.87% instead of the true 86.13%.
  /// [netFromPlay] is `totalReturned - totalStake` and does equal [netChange].
  int get totalReturned => results.fold(
    0,
    (int sum, BetResult r) => sum + (r.won ? r.bet.amount + r.profit : 0),
  );
}
