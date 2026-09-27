import '../core/config.dart';
import '../models/bet.dart';
import '../models/symbol.dart';
import 'dice_roller.dart';
import 'payout_table.dart';

/// Settles wagers against a roll. Pure logic: no storage, no plugins, no
/// widgets, and no side effects.
///
/// Keeping this free of Flutter is what allows the entire money system to be
/// verified by fast unit tests before any UI exists.
class GameEngine {
  const GameEngine();

  /// Settles every wager in [bets] against [faces] and returns the round
  /// result. Each wager is settled independently, so betting on three symbols
  /// and having two of them win is a legal and profitable outcome.
  RoundResult settle(List<Bet> bets, List<Symbol> faces) {
    int totalStake = 0;
    int netChange = 0;
    final List<BetResult> results = <BetResult>[];

    for (final Bet bet in bets) {
      if (bet.amount <= 0) continue;

      final int matches = DiceRoller.countOf(bet.symbol, faces);
      final int profit = PayoutTable.profitFor(
        stake: bet.amount,
        matches: matches,
      );

      totalStake += bet.amount;
      netChange += profit;
      results.add(BetResult(bet: bet, matches: matches, profit: profit));
    }

    return RoundResult(
      faces: List<Symbol>.unmodifiable(faces),
      results: List<BetResult>.unmodifiable(results),
      totalStake: totalStake,
      netChange: netChange,
    );
  }

  /// Rolls with [roller] and settles [bets] against the result.
  RoundResult play(List<Bet> bets, DiceRoller roller) =>
      settle(bets, roller.roll());

  /// The reason a wager was rejected, or null if it is legal.
  ///
  /// Returned as a value rather than thrown so the UI can grey out invalid
  /// controls and explain why, instead of showing an opaque error.
  BetRejection? validateBet({
    required int currentStake,
    required int additional,
    required int balance,
    required int existingTotalBet,
  }) {
    if (additional <= 0) return null;

    if (additional < AppConfig.minBet) {
      return BetRejection.tooSmall;
    }
    if (balance - existingTotalBet < additional) {
      return BetRejection.insufficientFunds;
    }
    if (existingTotalBet + additional > AppConfig.maxTotalBet) {
      return BetRejection.totalBetLimitReached;
    }
    if (currentStake + additional > AppConfig.maxBetPerSymbol) {
      return BetRejection.perSymbolLimitReached;
    }
    return null;
  }
}

/// Why a wager cannot be placed.
enum BetRejection {
  tooSmall('Below the minimum bet'),
  insufficientFunds('Not enough coins'),
  perSymbolLimitReached('Maximum bet on one symbol reached'),
  totalBetLimitReached('Maximum total bet for this round reached');

  const BetRejection(this.message);

  final String message;
}
