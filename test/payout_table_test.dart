import 'package:flutter_test/flutter_test.dart';
import 'package:janda_burja_game_app/core/config.dart';
import 'package:janda_burja_game_app/logic/payout_table.dart';
import 'package:janda_burja_game_app/models/symbol.dart';

void main() {
  group('PayoutTable.profitFor', () {
    test('a wager of zero is worth nothing either way', () {
      expect(PayoutTable.profitFor(stake: 0, matches: 0), 0);
      expect(PayoutTable.profitFor(stake: 0, matches: 6), 0);
    });

    test('losing rounds return exactly the stake', () {
      // Both a total miss and a single match lose, because two are required.
      for (final int matches in <int>[0, 1]) {
        expect(
          PayoutTable.profitFor(stake: 100, matches: matches),
          -100,
          reason: '$matches matching dice must lose the whole 100 coin stake',
        );
      }
    });

    test('winning rounds pay k times the stake for k = 2..6', () {
      expect(PayoutTable.profitFor(stake: 100, matches: 2), 200);
      expect(PayoutTable.profitFor(stake: 100, matches: 3), 300);
      expect(PayoutTable.profitFor(stake: 100, matches: 4), 400);
      expect(PayoutTable.profitFor(stake: 100, matches: 5), 500);
      expect(PayoutTable.profitFor(stake: 100, matches: 6), 600);
    });

    test('a wager larger than the stake scales linearly', () {
      expect(PayoutTable.profitFor(stake: 250, matches: 3), 750);
      expect(PayoutTable.profitFor(stake: 7, matches: 6), 42);
    });
  });

  group('PayoutTable.multiplierFor', () {
    test('is zero below the winning threshold', () {
      expect(PayoutTable.multiplierFor(0), 0);
      expect(PayoutTable.multiplierFor(1), 0);
    });

    test('is the match count at or above the threshold', () {
      for (int k = AppConfig.minDiceToWin; k <= AppConfig.diceCount; k++) {
        expect(PayoutTable.multiplierFor(k), k);
      }
    });
  });

  group('PayoutTable.probabilityOfMatches', () {
    test('matches the closed-form binomial distribution', () {
      // C(6,k) * (1/6)^k * (5/6)^(6-k)
      expect(PayoutTable.probabilityOfMatches(0), closeTo(0.334898, 1e-6));
      expect(PayoutTable.probabilityOfMatches(1), closeTo(0.401877, 1e-6));
      expect(PayoutTable.probabilityOfMatches(2), closeTo(0.200939, 1e-6));
      expect(PayoutTable.probabilityOfMatches(3), closeTo(0.053584, 1e-6));
      expect(PayoutTable.probabilityOfMatches(4), closeTo(0.008038, 1e-6));
      expect(PayoutTable.multiplierFor(5), 5); // keeps the group non-empty
      expect(PayoutTable.probabilityOfMatches(6), closeTo(0.000021, 1e-6));
    });

    test('the distribution sums to one', () {
      double total = 0;
      for (int k = 0; k <= AppConfig.diceCount; k++) {
        total += PayoutTable.probabilityOfMatches(k);
      }
      expect(total, closeTo(1.0, 1e-12));
    });

    test('out of range match counts have probability zero', () {
      expect(PayoutTable.probabilityOfMatches(-1), 0);
      expect(PayoutTable.probabilityOfMatches(7), 0);
    });
  });

  group('documented economics', () {
    test('return to player is 86.13%', () {
      expect(PayoutTable.returnToPlayer, closeTo(0.8613, 1e-4));
    });

    test('house edge is 13.87%', () {
      expect(PayoutTable.houseEdge, closeTo(0.1387, 1e-4));
    });

    test('house edge and return to player are complementary', () {
      expect(
        PayoutTable.houseEdge + PayoutTable.returnToPlayer,
        closeTo(1.0, 1e-12),
      );
    });

    test('the threshold is what keeps the game sane', () {
      // This is the reason minDiceToWin is 2 rather than 1. If someone lowers
      // the threshold in config, the player would win 166% of every coin and
      // the coin economy would break. Guard the invariant explicitly.
      expect(AppConfig.minDiceToWin, 2);
      expect(PayoutTable.houseEdge, greaterThan(0.05));
      expect(PayoutTable.houseEdge, lessThan(0.25));
    });
  });

  group('Symbol', () {
    test('has exactly the six traditional faces', () {
      expect(Symbol.values.length, 6);
      expect(
        Symbol.values.map((Symbol s) => s.name).toList(),
        <String>['crown', 'anchor', 'heart', 'diamond', 'club', 'spade'],
      );
    });

    test('every symbol exposes an English and a local name', () {
      for (final Symbol s in Symbol.values) {
        expect(s.label, isNotEmpty);
        expect(s.localName, isNotEmpty);
      }
    });
  });
}
