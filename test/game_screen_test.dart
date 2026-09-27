import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:janda_burja_game_app/core/config.dart';
import 'package:janda_burja_game_app/core/theme.dart';
import 'package:janda_burja_game_app/logic/dice_roller.dart';
import 'package:janda_burja_game_app/models/symbol.dart';
import 'package:janda_burja_game_app/services/rewarded_ad_service.dart';
import 'package:janda_burja_game_app/services/storage_service.dart';
import 'package:janda_burja_game_app/state/game_controller.dart';
import 'package:janda_burja_game_app/ui/screens/disclosure_gate.dart';
import 'package:janda_burja_game_app/ui/screens/game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds a controller backed by in-memory preferences and the fake ad service,
/// so the whole game loop can be exercised on the Dart VM where the real AdMob
/// SDK and audio plugin do not exist.
///
/// Sound and haptics are persisted off: `AudioService` swallows platform
/// channel errors, but silencing at the preference level keeps the test output
/// clean and guarantees no audio is attempted.
Future<GameController> buildController({
  FakeRewardedAdService? ads,
  int seed = 7,
  int? startingBalance,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final StorageService storage = await StorageService.open();
  await storage.saveSoundEnabled(false);
  await storage.saveHapticsEnabled(false);
  if (startingBalance != null) await storage.saveBalance(startingBalance);

  final GameController controller = GameController(
    storage: storage,
    ads: ads ?? FakeRewardedAdService(),
    roller: DiceRoller(random: Random(seed)),
  );
  await controller.initialise();
  return controller;
}

Widget wrap(GameController controller) => MaterialApp(
  theme: GameTheme.build(),
  home: GameScreen(controller: controller),
);

/// Drives the fake clock past the 950ms roll delay and the 880ms tumble, then
/// drains any celebration animation so no timers outlive the test.
Future<void> finishRound(WidgetTester tester) async {
  for (int i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pumpAndSettle();
}

/// Grows the test surface so a long scrolling screen is built in full.
///
/// A `ListView` only builds what is near the viewport, so without this the
/// disclaimer at the bottom of the rules screen simply does not exist as far as
/// the finder is concerned.
void useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// A 320x568 logical viewport, the narrowest phone worth supporting.
void useSmallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('renders the board, chips and all six symbols', (
    WidgetTester tester,
  ) async {
    final GameController c = await buildController();
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    expect(find.text(AppConfig.appName), findsOneWidget);

    for (final Symbol s in Symbol.values) {
      expect(
        find.text(s.label),
        findsOneWidget,
        reason: '${s.label} should have a cell on the board',
      );
    }

    for (final int chip in AppConfig.chipDenominations) {
      expect(find.text('$chip'), findsWidgets);
    }
    c.dispose();
  });

  testWidgets('tapping a symbol stages a chip and raises the total', (
    WidgetTester tester,
  ) async {
    final GameController c = await buildController();
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    expect(c.wallet.totalBet, 0);

    await tester.tap(find.text('Crown'));
    await tester.pump();

    expect(c.wallet.bets[Symbol.crown], c.wallet.selectedChip);
    expect(c.wallet.totalBet, c.wallet.selectedChip);
    expect(c.phase, RollPhase.ready);
    c.dispose();
  });

  testWidgets('the roll button is disabled until a bet is staged', (
    WidgetTester tester,
  ) async {
    final GameController c = await buildController();
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    final Finder roll = find.text('ROLL THE DICE');
    expect(roll, findsOneWidget);
    expect(c.canRoll, isFalse);

    await tester.tap(find.text('Crown'));
    await tester.pump();

    expect(c.canRoll, isTrue);
    c.dispose();
  });

  testWidgets('a settled round moves the balance by exactly the net change', (
    WidgetTester tester,
  ) async {
    final GameController c = await buildController(seed: 1);
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    final int before = c.wallet.balance;
    await c.addBet(Symbol.crown);
    await c.selectChip(AppConfig.chipDenominations.last);
    await c.addBet(Symbol.crown);
    await c.addBet(Symbol.crown);

    unawaited(c.roll());
    expect(c.phase, RollPhase.rolling);
    expect(
      c.visibleFaces.length,
      AppConfig.diceCount,
      reason: 'the dice must be dealt up front so the tumble lands truthfully',
    );

    await finishRound(tester);

    expect(c.phase, RollPhase.settled);
    expect(c.lastRound, isNotNull);
    expect(c.stats.roundsPlayed, 1);
    expect(
      c.wallet.balance,
      before + c.lastRound!.netChange,
      reason: 'balance must move by exactly the round net change',
    );
    expect(c.wallet.hasBets, isFalse, reason: 'the board is cleared on settle');
    expect(find.text('CLEAR BOARD'), findsOneWidget);
    c.dispose();
  });

  testWidgets('the dice are face down before the first throw', (
    WidgetTester tester,
  ) async {
    final GameController c = await buildController();
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    expect(c.visibleFaces, isEmpty);
    expect(find.text('ROLL THE DICE'), findsOneWidget);
    c.dispose();
  });

  testWidgets('quick actions clear, undo and repeat', (
    WidgetTester tester,
  ) async {
    final GameController c = await buildController();
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    await tester.tap(find.text('Crown'));
    await tester.tap(find.text('Heart'));
    await tester.pump();
    expect(c.wallet.totalBet, c.wallet.selectedChip * 2);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(c.wallet.totalBet, c.wallet.selectedChip);

    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(c.wallet.totalBet, 0);

    await tester.tap(find.text('Crown'));
    await tester.pump();
    unawaited(c.roll());
    await finishRound(tester);

    await tester.tap(find.text('CLEAR BOARD'));
    await tester.pump();
    expect(c.phase, RollPhase.idle);

    await tester.tap(find.text('Repeat'));
    await tester.pump();
    expect(c.wallet.bets[Symbol.crown], isNotNull);
    c.dispose();
  });

  testWidgets('a broke player is offered coins for a rewarded ad', (
    WidgetTester tester,
  ) async {
    final FakeRewardedAdService ads = FakeRewardedAdService(rewardAmount: 500);
    final GameController c = await buildController(
      ads: ads,
      startingBalance: 0,
    );
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    expect(c.isBroke, isTrue);
    expect(find.text('+${AppConfig.coinsPerRewardedAd}'), findsOneWidget);

    await tester.tap(find.text('+${AppConfig.coinsPerRewardedAd}'));
    await tester.pump();
    await tester.pump();

    expect(ads.rewardCount, 1);
    expect(c.wallet.balance, 500);
    expect(c.stats.adsWatched, 1);
    expect(c.stats.coinsFromAds, 500);
    expect(c.isBroke, isFalse);
    c.dispose();
  });

  testWidgets('the game stays playable when no ad can be loaded', (
    WidgetTester tester,
  ) async {
    final FakeRewardedAdService ads = FakeRewardedAdService(failToLoad: true);
    final GameController c = await buildController(
      ads: ads,
      startingBalance: 0,
    );
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    expect(c.adState, RewardedAdState.unavailable);

    await tester.tap(find.text('+${AppConfig.coinsPerRewardedAd}'));
    await tester.pump();

    // No coins granted, no crash, and the player is told why.
    expect(c.wallet.balance, 0);
    expect(c.adMessage, isNotNull);
    expect(find.textContaining('No ad available'), findsOneWidget);
    c.dispose();
  });

  testWidgets('changing chip affects the next wager', (
    WidgetTester tester,
  ) async {
    final GameController c = await buildController();
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    await c.selectChip(500);
    await tester.pump();
    await tester.tap(find.text('Crown'));
    await tester.pump();

    expect(c.wallet.bets[Symbol.crown], 500);
    c.dispose();
  });

  testWidgets('stats and rules screens open from the game screen', (
    WidgetTester tester,
  ) async {
    useTallViewport(tester);
    final GameController c = await buildController();
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();
    expect(find.text('How to play'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Statistics'), findsOneWidget);
    expect(find.textContaining('No rounds played yet'), findsOneWidget);
    c.dispose();
  });

  testWidgets('rules screen states the real RTP and the no-cashout notice', (
    WidgetTester tester,
  ) async {
    useTallViewport(tester);
    final GameController c = await buildController();
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();

    expect(find.textContaining('86.13%'), findsOneWidget);
    expect(find.textContaining('13.87%'), findsOneWidget);
    expect(find.textContaining('No real money'), findsOneWidget);
    expect(find.textContaining('no way to cash out'), findsOneWidget);
    c.dispose();
  });

  testWidgets('the symbol legend names every symbol in the local vocabulary', (
    WidgetTester tester,
  ) async {
    useTallViewport(tester);
    final GameController c = await buildController();
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();

    for (final Symbol s in Symbol.values) {
      expect(find.text(s.localName), findsOneWidget, reason: s.name);
    }
    c.dispose();
  });

  testWidgets('the first-run disclosure blocks play until acknowledged', (
    WidgetTester tester,
  ) async {
    useTallViewport(tester);
    final GameController c = await buildController();
    expect(c.ageAcknowledged, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        theme: GameTheme.build(),
        home: DisclosureGate(controller: c),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Before you play'), findsOneWidget);
    expect(find.textContaining('no way to cash out'), findsOneWidget);
    expect(find.textContaining('18+'), findsOneWidget);

    // The barrier is not dismissible, so a tap outside must not get rid of it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Before you play'), findsOneWidget);

    await tester.tap(find.text('I UNDERSTAND'));
    await tester.pumpAndSettle();

    expect(find.text('Before you play'), findsNothing);
    expect(c.ageAcknowledged, isTrue);
    c.dispose();
  });

  testWidgets('the disclosure does not reappear on a later launch', (
    WidgetTester tester,
  ) async {
    useTallViewport(tester);
    final GameController first = await buildController();
    await first.acknowledgeAge();
    first.dispose();

    // Relaunch over the same stored preferences.
    final StorageService storage = await StorageService.open();
    final GameController second = GameController(
      storage: storage,
      ads: FakeRewardedAdService(),
    );
    await second.initialise();

    await tester.pumpWidget(
      MaterialApp(
        theme: GameTheme.build(),
        home: DisclosureGate(controller: second),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Before you play'), findsNothing);
    expect(find.text('ROLL THE DICE'), findsOneWidget);
    second.dispose();
  });

  testWidgets('settings toggles sound and haptics', (
    WidgetTester tester,
  ) async {
    useTallViewport(tester);
    final GameController c = await buildController();
    expect(c.soundEnabled, isFalse, reason: 'the harness starts muted');

    await tester.pumpWidget(wrap(c));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Sound effects'));
    await tester.pumpAndSettle();
    expect(c.soundEnabled, isTrue);

    await tester.tap(find.text('Vibration'));
    await tester.pumpAndSettle();
    expect(c.hapticsEnabled, isTrue);
    c.dispose();
  });

  testWidgets('settings links to the rules screen', (
    WidgetTester tester,
  ) async {
    useTallViewport(tester);
    final GameController c = await buildController();
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('How to play'));
    await tester.pumpAndSettle();

    expect(find.text('How to play'), findsWidgets);
    expect(find.textContaining('86.13%'), findsOneWidget);
    c.dispose();
  });

  testWidgets('the ad failure message offers a retry that recovers', (
    WidgetTester tester,
  ) async {
    final FakeRewardedAdService ads = FakeRewardedAdService(
      failToLoad: true,
    );
    final GameController c = await buildController(
      ads: ads,
      startingBalance: 0,
    );
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    await tester.tap(find.text('+${AppConfig.coinsPerRewardedAd}'));
    await tester.pump();

    expect(find.textContaining('No ad available'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(c.wallet.balance, 0);

    // The network comes back and the player retries.
    ads.failToLoad = false;
    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(c.adState, RewardedAdState.ready);
    expect(find.textContaining('Ad ready'), findsOneWidget);
    c.dispose();
  });

  testWidgets('lays out on a small phone with the ad button showing', (
    WidgetTester tester,
  ) async {
    useSmallPhone(tester);
    final GameController c = await buildController(
      ads: FakeRewardedAdService(failToLoad: true),
      startingBalance: 0,
    );
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    // The four-button quick-action row is the tightest layout in the game.
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Repeat'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(
      find.text('+${AppConfig.coinsPerRewardedAd}'),
      findsOneWidget,
      reason: 'a broke player must get the fourth button, or this test is '
          'not covering the layout it claims to',
    );
    expect(tester.takeException(), isNull);
    c.dispose();
  });

  testWidgets('lays out on a small phone with a result panel showing', (
    WidgetTester tester,
  ) async {
    useSmallPhone(tester);
    final GameController c = await buildController(startingBalance: 500);
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    await c.addBet(Symbol.crown);
    unawaited(c.roll());
    await finishRound(tester);

    expect(c.lastRound, isNotNull);
    expect(tester.takeException(), isNull);
    c.dispose();
  });
}
