import 'package:flutter_test/flutter_test.dart';
import 'package:janda_burja_game_app/core/config.dart';
import 'package:janda_burja_game_app/logic/game_engine.dart';
import 'package:janda_burja_game_app/logic/wallet.dart';
import 'package:janda_burja_game_app/models/bet.dart';
import 'package:janda_burja_game_app/models/symbol.dart';

/// Builds a roll containing [counts] copies of each given symbol, padding with
/// the first symbol supplied so the list is always the right length.
List<Symbol> rollOf(Map<Symbol, int> counts) {
  final List<Symbol> faces = <Symbol>[];
  counts.forEach((Symbol symbol, int count) {
    for (int i = 0; i < count; i++) {
      faces.add(symbol);
    }
  });
  while (faces.length < AppConfig.diceCount) {
    faces.add(counts.keys.first);
  }
  return faces.take(AppConfig.diceCount).toList();
}

void main() {
  const GameEngine engine = GameEngine();

  group('GameEngine.settle', () {
    test('a single-symbol wager with two matches wins twice the stake', () {
      final RoundResult r = engine.settle(<Bet>[
        const Bet(symbol: Symbol.crown, amount: 100),
      ], rollOf(<Symbol, int>{Symbol.crown: 2, Symbol.heart: 4}));

      expect(r.totalStake, 100);
      expect(r.netChange, 200);
      expect(r.won, isTrue);
      expect(r.results.single.matches, 2);
    });

    test('a single match loses, because two are required', () {
      final RoundResult r = engine.settle(<Bet>[
        const Bet(symbol: Symbol.crown, amount: 100),
      ], rollOf(<Symbol, int>{Symbol.crown: 1, Symbol.heart: 5}));

      expect(r.netChange, -100);
      expect(r.won, isFalse);
      expect(r.results.single.matches, 1);
    });

    test('no matches loses the stake', () {
      final RoundResult r = engine.settle(<Bet>[
        const Bet(symbol: Symbol.crown, amount: 50),
      ], rollOf(<Symbol, int>{Symbol.heart: 6}));

      expect(r.netChange, -50);
      expect(r.results.single.matches, 0);
    });

    test('all six matching pays six times the stake', () {
      final RoundResult r = engine.settle(<Bet>[
        const Bet(symbol: Symbol.anchor, amount: 10),
      ], rollOf(<Symbol, int>{Symbol.anchor: 6}));

      expect(r.netChange, 60);
      expect(r.results.single.matches, 6);
    });

    test('wagers settle independently, so one loss can be offset by a win', () {
      // Crown appears 0 times (loses 100), heart appears 3 times (wins 300).
      final RoundResult r = engine.settle(<Bet>[
        const Bet(symbol: Symbol.crown, amount: 100),
        const Bet(symbol: Symbol.heart, amount: 100),
      ], rollOf(<Symbol, int>{Symbol.heart: 3, Symbol.spade: 3}));

      expect(r.totalStake, 200);
      expect(r.netChange, 300 - 100);
      expect(r.won, isTrue);
      expect(r.results.length, 2);
      expect(r.results[0].won, isFalse);
      expect(r.results[1].won, isTrue);
    });

    test('a round of all-losing wagers nets out to minus the total stake', () {
      final RoundResult r = engine.settle(<Bet>[
        const Bet(symbol: Symbol.crown, amount: 100),
        const Bet(symbol: Symbol.anchor, amount: 200),
        const Bet(symbol: Symbol.club, amount: 50),
      ], rollOf(<Symbol, int>{Symbol.heart: 6}));

      expect(r.totalStake, 350);
      expect(r.netChange, -350);
      expect(r.lostEverything, isTrue);
    });

    test('a round with no wagers is a harmless zero', () {
      final RoundResult r = engine.settle(
        <Bet>[],
        rollOf(<Symbol, int>{Symbol.crown: 6}),
      );

      expect(r.totalStake, 0);
      expect(r.netChange, 0);
      expect(r.results, isEmpty);
      expect(r.won, isFalse);
    });

    test('zero-amount wagers are ignored rather than settled', () {
      final RoundResult r = engine.settle(<Bet>[
        const Bet(symbol: Symbol.crown, amount: 0),
      ], rollOf(<Symbol, int>{Symbol.crown: 6}));

      expect(r.results, isEmpty);
      expect(r.netChange, 0);
    });

    test('exactly minDiceToWin is the boundary between loss and win', () {
      final RoundResult losing = engine.settle(<Bet>[
        const Bet(symbol: Symbol.crown, amount: 100),
      ], rollOf(<Symbol, int>{Symbol.crown: AppConfig.minDiceToWin - 1, Symbol.heart: 6 - (AppConfig.minDiceToWin - 1)}));

      final RoundResult winning = engine.settle(<Bet>[
        const Bet(symbol: Symbol.crown, amount: 100),
      ], rollOf(<Symbol, int>{Symbol.crown: AppConfig.minDiceToWin, Symbol.heart: 6 - AppConfig.minDiceToWin}));

      expect(losing.netChange, -100);
      expect(winning.netChange, 100 * AppConfig.minDiceToWin);
    });

    test('results and dice are unmodifiable so the UI cannot corrupt history',
        () {
      final RoundResult r = engine.settle(<Bet>[
        const Bet(symbol: Symbol.crown, amount: 10),
      ], rollOf(<Symbol, int>{Symbol.crown: 3, Symbol.heart: 3}));

      expect(
        () => r.faces.add(Symbol.club),
        throwsUnsupportedError,
      );
      expect(
        () => r.results.clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('GameEngine.validateBet', () {
    BetRejection? check({
      int currentStake = 0,
      int additional = 50,
      int balance = 5000,
      int existingTotalBet = 0,
    }) => engine.validateBet(
      currentStake: currentStake,
      additional: additional,
      balance: balance,
      existingTotalBet: existingTotalBet,
    );

    test('accepts a normal wager', () {
      expect(check(), isNull);
    });

    test('rejects a wager below the minimum', () {
      expect(
        check(additional: AppConfig.minBet - 1),
        BetRejection.tooSmall,
      );
    });

    test('accepts a wager exactly at the minimum', () {
      expect(check(additional: AppConfig.minBet), isNull);
    });

    test('rejects a wager the player cannot afford', () {
      expect(
        check(additional: 100, balance: 50),
        BetRejection.insufficientFunds,
      );
    });

    test('rejects crossing the per-symbol cap', () {
      expect(
        check(
          currentStake: AppConfig.maxBetPerSymbol - 10,
          additional: 50,
        ),
        BetRejection.perSymbolLimitReached,
      );
    });

    test('accepts wagers that land exactly on the total round cap', () {
      // Reaching the cap is legal, only exceeding it is not. The wager has to
      // be spread across symbols because the per-symbol cap (2000) is lower
      // than the total round cap (6000), so a single wager could never reach
      // the total on its own.
      expect(
        check(
          additional: AppConfig.maxBetPerSymbol,
          existingTotalBet: AppConfig.maxTotalBet - AppConfig.maxBetPerSymbol,
          balance: 1000000,
        ),
        isNull,
      );
    });

    test('rejects crossing the total round cap', () {
      expect(
        check(additional: AppConfig.maxTotalBet + 1, balance: 1000000),
        BetRejection.totalBetLimitReached,
      );
    });

    test('rejects a wager that would push the round past the cap', () {
      expect(
        check(
          additional: 100,
          existingTotalBet: AppConfig.maxTotalBet,
          balance: 1000000,
        ),
        BetRejection.totalBetLimitReached,
      );
    });

    test('ignores a zero additional wager', () {
      expect(check(additional: 0), isNull);
    });
  });

  group('Wallet', () {
    Wallet newWallet({int balance = 5000, int selectedChip = 50}) =>
        Wallet(balance: balance, selectedChip: selectedChip);

    test('starts with the given balance and no wagers', () {
      final Wallet w = newWallet();
      expect(w.balance, 5000);
      expect(w.totalBet, 0);
      expect(w.hasBets, isFalse);
    });

    test('adds wagers and tracks the total', () {
      final Wallet w = newWallet();
      expect(w.addToBet(Symbol.crown, 100), isTrue);
      expect(w.addToBet(Symbol.heart, 200), isTrue);

      expect(w.bets[Symbol.crown], 100);
      expect(w.bets[Symbol.heart], 200);
      expect(w.totalBet, 300);
      expect(w.uncommittedBalance, 4700);
    });

    test('refuses a wager larger than the uncommitted balance', () {
      final Wallet w = newWallet(balance: 100);
      expect(w.addToBet(Symbol.crown, 200), isFalse);
      expect(w.totalBet, 0);
    });

    test('refuses to exceed the per-symbol cap', () {
      final Wallet w = newWallet(balance: 100000);
      w.addToBet(Symbol.crown, AppConfig.maxBetPerSymbol);
      expect(w.addToBet(Symbol.crown, 50), isFalse);
      expect(w.bets[Symbol.crown], AppConfig.maxBetPerSymbol);
    });

    test('removing part of a wager leaves the remainder', () {
      final Wallet w = newWallet();
      w.addToBet(Symbol.crown, 100);
      w.removeFromBet(Symbol.crown, 30);

      expect(w.bets[Symbol.crown], 70);
    });

    test('removing the whole wager deletes the entry', () {
      final Wallet w = newWallet();
      w.addToBet(Symbol.crown, 100);
      w.removeFromBet(Symbol.crown, 100);

      expect(w.bets.containsKey(Symbol.crown), isFalse);
      expect(w.hasBets, isFalse);
    });

    test('clearAllBets empties the board', () {
      final Wallet w = newWallet();
      w.addToBet(Symbol.crown, 100);
      w.addToBet(Symbol.spade, 100);
      w.clearAllBets();

      expect(w.bets, isEmpty);
      expect(w.totalBet, 0);
    });

    test('applying a round moves the balance and clears the board', () {
      final Wallet w = newWallet(balance: 1000);
      w.addToBet(Symbol.crown, 100);
      final RoundResult r = engine.settle(<Bet>[
        const Bet(symbol: Symbol.crown, amount: 100),
      ], rollOf(<Symbol, int>{Symbol.crown: 3, Symbol.heart: 3}));

      w.applyRound(r);

      expect(r.netChange, 300);
      expect(w.balance, 1300);
      expect(w.bets, isEmpty);
    });

    test('a losing round debits the balance', () {
      final Wallet w = newWallet(balance: 1000);
      w.addToBet(Symbol.crown, 400);
      final RoundResult r = engine.settle(<Bet>[
        const Bet(symbol: Symbol.crown, amount: 400),
      ], rollOf(<Symbol, int>{Symbol.heart: 6}));

      w.applyRound(r);

      expect(w.balance, 600);
    });

    test('credit adds coins and ignores non-positive amounts', () {
      final Wallet w = newWallet(balance: 100);
      w.credit(500);
      expect(w.balance, 600);

      w.credit(0);
      w.credit(-100);
      expect(w.balance, 600);
    });

    test('setBalance clamps a negative value to zero', () {
      final Wallet w = newWallet(balance: 100);
      w.setBalance(-50);
      expect(w.balance, 0);
    });

    test('canAffordMinBet is false once the player is nearly broke', () {
      final Wallet w = newWallet(balance: AppConfig.minBet);
      w.addToBet(Symbol.crown, AppConfig.minBet);
      expect(w.uncommittedBalance, 0);
      expect(w.canAffordMinBet, isFalse);
    });

    test('repeat restages the previous pattern', () {
      final Wallet w = newWallet(balance: 5000, selectedChip: 50);
      w.repeat(<Symbol, int>{Symbol.crown: 100, Symbol.heart: 250});

      expect(w.bets[Symbol.crown], 100);
      expect(w.bets[Symbol.heart], 250);
    });

    test('repeat drops wagers the player can no longer afford', () {
      // 50 coins left can stage one 50 chip, but not the full 500 pattern.
      // Wagers are only deducted from the balance when the round settles, so
      // the balance is still 50 with all 50 of it committed to the round.
      final Wallet w = newWallet(balance: 50, selectedChip: 50);
      final Map<Symbol, int> staged = w.repeat(<Symbol, int>{
        Symbol.crown: 500,
      });

      expect(staged.containsKey(Symbol.crown), isTrue);
      expect(staged[Symbol.crown], 50);
      expect(w.balance, 50);
      expect(w.uncommittedBalance, 0);
      expect(w.canAffordMinBet, isFalse);
    });

    test('bets view cannot be mutated from outside', () {
      final Wallet w = newWallet();
      w.addToBet(Symbol.crown, 100);
      expect(
        () => w.bets[Symbol.spade] = 999,
        throwsUnsupportedError,
      );
    });

    test('selectChip only accepts configured denominations', () {
      final Wallet w = newWallet(selectedChip: 50);
      w.selectChip(100);
      expect(w.selectedChip, 100);

      w.selectChip(37);
      expect(w.selectedChip, 100, reason: '37 is not a real chip');
    });
  });

  group('gross return accounting', () {
    test('a losing wager returns nothing, a winning wager returns stake plus profit', () {
      const Bet losing = Bet(symbol: Symbol.crown, amount: 100);
      const Bet winning = Bet(symbol: Symbol.heart, amount: 200);
      final RoundResult result = const GameEngine().settle(
        <Bet>[losing, winning],
        <Symbol>[
          Symbol.crown, // crown x1 -> loses
          Symbol.heart, // heart x2 -> wins 2x
          Symbol.heart,
          Symbol.spade,
          Symbol.spade,
          Symbol.spade,
        ],
      );

      expect(result.netChange, 400 - 100);
      expect(
        result.totalReturned,
        200 + 400,
        reason: 'the winning wager returns its 200 stake plus 400 profit',
      );
      expect(
        result.totalReturned - result.totalStake,
        result.netChange,
        reason: 'gross return minus stake must equal the balance change, '
            'otherwise the stats screen would misreport the player RTP',
      );
    });

    test('a round with no winning wager returns nothing at all', () {
      final RoundResult result = const GameEngine().settle(
        <Bet>[const Bet(symbol: Symbol.crown, amount: 50)],
        <Symbol>[
          Symbol.crown,
          Symbol.heart,
          Symbol.heart,
          Symbol.spade,
          Symbol.spade,
          Symbol.spade,
        ],
      );

      expect(result.won, isFalse);
      expect(result.totalReturned, 0);
      expect(result.totalReturned - result.totalStake, result.netChange);
    });
  });
}
