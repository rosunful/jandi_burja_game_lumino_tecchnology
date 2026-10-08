import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:janda_burja_game_app/core/config.dart';
import 'package:janda_burja_game_app/logic/dice_roller.dart';
import 'package:janda_burja_game_app/logic/payout_table.dart';
import 'package:janda_burja_game_app/models/symbol.dart';

void main() {
  group('DiceRoller', () {
    test('rolls exactly the configured number of dice', () {
      expect(DiceRoller().roll().length, AppConfig.diceCount);
      expect(AppConfig.diceCount, 6);
    });

    test('only ever produces valid symbols', () {
      final DiceRoller roller = DiceRoller();
      for (int i = 0; i < 2000; i++) {
        for (final Symbol face in roller.roll()) {
          expect(Symbol.values, contains(face));
        }
      }
    });

    test('a seeded generator is reproducible', () {
      final List<Symbol> a = DiceRoller(random: Random(42)).roll();
      final List<Symbol> b = DiceRoller(random: Random(42)).roll();
      expect(a, b);
    });

    test('countOf counts matching faces', () {
      const List<Symbol> faces = <Symbol>[
        Symbol.crown,
        Symbol.crown,
        Symbol.heart,
        Symbol.crown,
        Symbol.spade,
        Symbol.club,
      ];
      expect(DiceRoller.countOf(Symbol.crown, faces), 3);
      expect(DiceRoller.countOf(Symbol.heart, faces), 1);
      expect(DiceRoller.countOf(Symbol.flag, faces), 0);
    });
  });

  group('empirical dice distribution', () {
    // Simulated rather than computed, so this independently confirms the
    // closed-form figures asserted in payout_table_test.dart. If the payout
    // table is ever edited, both suites must be updated together.
    test('a fair die shows each symbol about one sixth of the time', () {
      final DiceRoller roller = DiceRoller(random: Random(20260927));
      const int rolls = 60000;
      final Map<Symbol, int> counts = <Symbol, int>{
        for (final Symbol s in Symbol.values) s: 0,
      };

      for (int i = 0; i < rolls; i++) {
        for (final Symbol face in roller.roll()) {
          counts[face] = counts[face]! + 1;
        }
      }

      final int total = rolls * AppConfig.diceCount;
      for (final Symbol s in Symbol.values) {
        expect(
          counts[s]! / total,
          closeTo(1 / 6, 0.01),
          reason: '${s.name} should appear on roughly 1 in 6 faces',
        );
      }
    });

    test(
      'measured RTP converges to the documented 86.13%',
      () {
        // Plays single-symbol 1-coin wagers with a real 1-unit stake and
        // measures the actual coin return, independently of PayoutTable's
        // own arithmetic.
        final DiceRoller roller = DiceRoller(random: Random(31337));
        const int rounds = 200000;
        const int stake = 1;

        int coinDelta = 0;
        for (int i = 0; i < rounds; i++) {
          final List<Symbol> faces = roller.roll();
          for (final Symbol s in Symbol.values) {
            final int matches = DiceRoller.countOf(s, faces);
            coinDelta += PayoutTable.profitFor(stake: stake, matches: matches);
          }
        }

        final double totalStaked = (rounds * Symbol.values.length * stake)
            .toDouble();
        final double measuredRtp = (totalStaked + coinDelta) / totalStaked;

        expect(
          measuredRtp,
          closeTo(PayoutTable.returnToPlayer, 0.01),
          reason:
              'Monte-Carlo RTP $measuredRtp should agree with the analytic '
              '${PayoutTable.returnToPlayer}',
        );
        expect(
          measuredRtp,
          closeTo(0.8613, 0.01),
          reason: 'documented return to player is 86.13%',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('the player loses money over many rounds, so coins can run out', () {
      // This is the property the whole coin economy depends on. If it ever
      // flips, the watch-an-ad refill becomes unreachable and the game is
      // broken, so it is asserted rather than assumed.
      final DiceRoller roller = DiceRoller(random: Random(999));
      const int rounds = 20000;
      const int stake = 100;

      int coinDelta = 0;
      for (int i = 0; i < rounds; i++) {
        final List<Symbol> faces = roller.roll();
        for (final Symbol s in Symbol.values) {
          coinDelta += PayoutTable.profitFor(
            stake: stake,
            matches: DiceRoller.countOf(s, faces),
          );
        }
      }

      expect(
        coinDelta,
        lessThan(0),
        reason:
            'betting every symbol every round must trend negative for a '
            '13.87% house edge',
      );
    });
  });
}
