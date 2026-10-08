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
import 'package:janda_burja_game_app/ui/screens/dice_lab_screen.dart';
import 'package:janda_burja_game_app/ui/screens/disclosure_gate.dart';
import 'package:janda_burja_game_app/ui/screens/game_screen.dart';
import 'package:janda_burja_game_app/ui/widgets/die_face_view.dart';
import 'package:janda_burja_game_app/ui/widgets/hero_card.dart';
import 'package:janda_burja_game_app/ui/widgets/symbol_icon.dart';
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

/// The coin-refill button, which lives in the hero card.
///
/// Matched on a phrase rather than the whole label so the wording can be
/// reworked without rewriting every ad test. The pending state renders the
/// single word "Loading", so this never matches the wrong button.
Finder get adButton => find.textContaining('Watch ad');

/// Taps ROLL and lands on the throw screen mid-animation.
///
/// Pumps a fixed 400ms rather than `pumpAndSettle` on purpose: settling would
/// also run the 950ms throw to completion, and several tests need to observe the
/// dice while they are still moving. 400ms is enough for the push transition to
/// finish, which also takes the betting screen offstage.
Future<void> throwDice(WidgetTester tester) async {
  // Flush the rebuild that enables the button: staging a bet from a test
  // notifies the controller, but the rebuild only lands on the next frame.
  await tester.pump();
  await tester.tap(find.text('ROLL THE DICE'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The value of the settings switch on the row labelled [label].
///
/// The switch is a sibling of the label inside a [SwitchListTile], so the tile
/// is located first and the switch read from within it. Without this the test
/// would pass on the controller value alone even if the switch itself never
/// moved.
bool? _switchValue(WidgetTester tester, String label) {
  final Finder tile = find.widgetWithText(SwitchListTile, label);
  return tester
      .widget<Switch>(find.descendant(of: tile, matching: find.byType(Switch)))
      .value;
}

/// A 320x568 logical viewport, the narrowest phone worth supporting.
void useSmallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  // The 3D practice screen hosts a web view through a loopback HTTP server and
  // a platform plugin, neither of which exists on the test VM. Every test that
  // walks into that screen gets this placeholder instead.
  setUp(() {
    DiceLabScreen.viewerOverride = () => const SizedBox(key: Key('diceLabViewer'));
  });
  tearDown(() {
    DiceLabScreen.viewerOverride = null;
  });

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

    await throwDice(tester);
    expect(c.phase, RollPhase.rolling);
    expect(
      c.visibleFaces.length,
      AppConfig.diceCount,
      reason: 'the dice must be dealt up front so the tumble lands truthfully',
    );
    expect(find.text('ROLLING\u2026'), findsOneWidget);

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
    expect(find.text('PLAY AGAIN'), findsOneWidget);
    c.dispose();
  });

  testWidgets(
    'the throw happens on its own screen and PLAY AGAIN restores the table',
    (WidgetTester tester) async {
      final GameController c = await buildController();
      await tester.pumpWidget(wrap(c));
      await tester.pump();

      await c.addBet(Symbol.crown);
      await throwDice(tester);

      // The throw screen owns the input. The betting screen is still built
      // underneath to preserve its state, so "not tappable" rather than
      // "not present" is the honest assertion.
      expect(find.text('ROLLING\u2026'), findsOneWidget);
      expect(
        find.text('ROLL THE DICE').hitTestable(),
        findsNothing,
        reason: 'the table underneath must not be touchable during a throw',
      );

      await finishRound(tester);
      // The result is stated on this screen, including the wager that was backed.
      expect(find.textContaining('matched'), findsWidgets);
      expect(find.textContaining('Balance'), findsOneWidget);

      await tester.tap(find.text('PLAY AGAIN'));
      await tester.pumpAndSettle();

      // Back at the table: all six symbols, an empty board, and no result.
      for (final Symbol symbol in Symbol.values) {
        expect(find.text(symbol.label), findsOneWidget, reason: symbol.name);
      }
      expect(c.phase, RollPhase.idle);
      expect(c.wallet.hasBets, isFalse);
      expect(c.canRoll, isFalse);
      expect(
        find.text('ROLL THE DICE').hitTestable(),
        findsOneWidget,
        reason: 'the table must be live again after PLAY AGAIN',
      );
      c.dispose();
    },
  );

  testWidgets('the system back button also returns to a clean table', (
    WidgetTester tester,
  ) async {
    final GameController c = await buildController();
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    await c.addBet(Symbol.crown);
    await throwDice(tester);
    await finishRound(tester);
    expect(find.text('PLAY AGAIN'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(c.phase, RollPhase.idle);
    expect(c.wallet.hasBets, isFalse);
    expect(find.text('ROLL THE DICE').hitTestable(), findsOneWidget);
    c.dispose();
  });

  testWidgets('back is ignored while the dice are still moving', (
    WidgetTester tester,
  ) async {
    final GameController c = await buildController();
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    await c.addBet(Symbol.crown);
    await throwDice(tester);
    expect(c.phase, RollPhase.rolling);

    // Leaving now would settle a round with nobody watching the result.
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(c.phase, RollPhase.rolling);
    expect(find.text('ROLLING\u2026'), findsOneWidget);

    await finishRound(tester);
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
    await throwDice(tester);
    await finishRound(tester);

    await tester.tap(find.text('PLAY AGAIN'));
    await tester.pumpAndSettle();
    expect(c.phase, RollPhase.idle);

    await tester.tap(find.text('Repeat'));
    await tester.pump();
    expect(c.wallet.bets[Symbol.crown], isNotNull);
    c.dispose();
  });

  testWidgets('the bet line centres its label and stacks the amount below', (
    WidgetTester tester,
  ) async {
    final GameController c = await buildController();
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    final Finder line = find.byType(BetAmount);
    final Rect empty = tester.getRect(line);

    // Nothing staged: the label on its own. A zero the player has to interpret
    // is not a helpful line, so the slot is left empty until it means something.
    expect(find.text('You are betting'), findsOneWidget);
    expect(
      find.descendant(of: line, matching: find.text('0')),
      findsNothing,
      reason: 'a bare zero is not a line worth showing',
    );
    expect(
      (tester.getRect(find.text('You are betting')).center.dx - empty.center.dx)
          .abs(),
      lessThan(1),
      reason: 'the label is centred, not hung off one side',
    );

    // Ten coins, chosen because it needs no thousands separator to read back.
    await tester.tap(find.text('10'));
    await tester.pump();
    await tester.tap(find.text('Crown'));
    await tester.pump();

    final Rect label = tester.getRect(find.text('You are betting'));
    final Rect amount = tester.getRect(
      find.descendant(of: line, matching: find.text('10')),
    );
    expect(
      amount.top,
      greaterThanOrEqualTo(label.bottom),
      reason: 'the amount is on its own line below the label',
    );
    // The coin and its number are centred as a pair, so the number itself sits
    // right of centre: it is the pair a player sees as one thing.
    final Rect coin = tester.getRect(
      find.descendant(of: line, matching: find.byType(SymbolIcon)),
    );
    expect(
      (coin.left + amount.right) / 2,
      closeTo(empty.center.dx, 1),
      reason: 'the coin and the amount are centred under the label',
    );
    c.dispose();
  });

  testWidgets('a broke player is offered coins for a rewarded ad', (
    WidgetTester tester,
  ) async {
    // 10 is what AdMob's own test unit reports. Crediting the SDK's number
    // instead of the configured one is exactly the bug this test now pins.
    final FakeRewardedAdService ads = FakeRewardedAdService(rewardAmount: 10);
    final GameController c = await buildController(
      ads: ads,
      startingBalance: 0,
    );
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    expect(c.isBroke, isTrue);
    expect(adButton, findsOneWidget);
    expect(
      find.text('No coins left — watch an ad for more'),
      findsOneWidget,
      reason: 'a player with no coins must be told where more come from',
    );

    await tester.tap(adButton);
    await tester.pump();
    await tester.pump();

    expect(ads.rewardCount, 1);
    expect(c.wallet.balance, AppConfig.coinsPerRewardedAd);
    expect(c.stats.adsWatched, 1);
    expect(c.stats.coinsFromAds, AppConfig.coinsPerRewardedAd);
    expect(c.isBroke, isFalse);
    c.dispose();
  });

  testWidgets('the ad button is offered to a player with coins to spare', (
    WidgetTester tester,
  ) async {
    final FakeRewardedAdService ads = FakeRewardedAdService();
    final GameController c = await buildController(
      ads: ads,
      startingBalance: AppConfig.startingCoins,
    );
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    expect(c.isBroke, isFalse);
    expect(
      adButton,
      findsOneWidget,
      reason:
          'a player must be able to see where coins come from before '
          'they run out, not only once they have',
    );
    expect(
      find.text('You are betting'),
      findsOneWidget,
      reason: 'a player who can afford to bet is told what they are betting',
    );
    expect(
      find.textContaining('No coins left'),
      findsNothing,
      reason: 'the out-of-coins notice belongs to the broke state only',
    );

    await tester.tap(adButton);
    await tester.pump();
    await tester.pump();

    expect(
      c.wallet.balance,
      AppConfig.startingCoins + AppConfig.coinsPerRewardedAd,
    );
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

    await tester.tap(adButton);
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

    // The switches are driven by the controller, so a stale control would
    // still report the new model value while showing the wrong position.
    expect(_switchValue(tester, 'Sound effects'), isFalse);

    await tester.tap(find.text('Sound effects'));
    await tester.pumpAndSettle();
    expect(c.soundEnabled, isTrue);
    expect(_switchValue(tester, 'Sound effects'), isTrue);

    await tester.tap(find.text('Vibration'));
    await tester.pumpAndSettle();
    expect(c.hapticsEnabled, isTrue);
    expect(_switchValue(tester, 'Vibration'), isTrue);
    c.dispose();
  });

  testWidgets('lays out the throw screen on a small phone', (
    WidgetTester tester,
  ) async {
    useSmallPhone(tester);
    final GameController c = await buildController();
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    await c.addBet(Symbol.crown);
    await throwDice(tester);
    expect(tester.takeException(), isNull);

    await finishRound(tester);
    // Dice and result both fit a 320x568 screen without overflowing.
    expect(find.text('PLAY AGAIN'), findsOneWidget);
    expect(tester.takeException(), isNull);
    c.dispose();
  });

  testWidgets('the dice sit in the middle of the throw screen', (
    WidgetTester tester,
  ) async {
    final GameController c = await buildController();
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    await c.addBet(Symbol.crown);
    await throwDice(tester);

    // Measured mid-throw, before the result panel claims the bottom of the
    // screen. That is the state this is about: the dice own the space they are
    // given, rather than being pushed up under the app bar by a panel.
    final Finder dice = find.byType(DieFaceView);
    expect(dice, findsNWidgets(AppConfig.diceCount));

    double top = double.infinity;
    double bottom = 0;
    for (int i = 0; i < AppConfig.diceCount; i++) {
      final Rect r = tester.getRect(dice.at(i));
      if (r.top < top) top = r.top;
      if (r.bottom > bottom) bottom = r.bottom;
    }
    final double blockCentre = (top + bottom) / 2;
    // Logical pixels, like the rects above: the physical size is three times
    // the default test viewport.
    final double screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    // Top-aligned, the six dice used to sit with their centre at roughly a
    // fifth of the way down. These bounds are loose enough to survive a status
    // bar or a device with a different aspect ratio, and still fail outright
    // for a layout that pins them to the top.
    expect(
      blockCentre,
      greaterThan(screenHeight * 0.30),
      reason: 'the dice must not be jammed against the top of the screen',
    );
    expect(
      blockCentre,
      lessThan(screenHeight * 0.70),
      reason: 'the dice must stay clear of the result panel at the bottom',
    );

    await finishRound(tester);
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
    final FakeRewardedAdService ads = FakeRewardedAdService(failToLoad: true);
    final GameController c = await buildController(
      ads: ads,
      startingBalance: 0,
    );
    await tester.pumpWidget(wrap(c));
    await tester.pump();

    await tester.tap(adButton);
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

    // The hero card carries the most text in the game, so at 320 logical pixels
    // it is the layout most at risk of overflowing. Both it and the three quick
    // actions must survive. This player is broke, which is the taller of the two
    // states, so it is the worst case for pushing the quick actions off screen.
    expect(find.text('Your coins'), findsOneWidget);
    expect(
      find.text('No coins left — watch an ad for more'),
      findsOneWidget,
      reason: 'the status line explains why betting is unavailable',
    );
    expect(find.text('ROLL THE DICE'), findsOneWidget);
    expect(adButton, findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Repeat'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);

    // The quick actions sit under the coin grid, at the very bottom of the
    // scrolling column, which is exactly where they get pushed off screen.
    // Checked geometrically rather than with `hitTestable`: a `Text` never
    // registers as a hit-test target, and the buttons are disabled in this
    // state, so that finder would pass or fail for reasons unrelated to
    // whether the row is on screen at all.
    final double viewHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    for (final String action in <String>['Undo', 'Repeat', 'Clear']) {
      final Rect row = tester.getRect(find.text(action));
      expect(
        row.bottom,
        lessThanOrEqualTo(viewHeight),
        reason:
            '$action must be visible without scrolling on the narrowest '
            'phone this app supports',
      );
    }

    // Every coin denomination fits on screen rather than needing a scroll.
    for (final int value in AppConfig.chipDenominations) {
      expect(
        find.text('$value'),
        findsWidgets,
        reason: 'the $value coin must be reachable without scrolling',
      );
    }

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
    await throwDice(tester);
    await finishRound(tester);

    expect(c.lastRound, isNotNull);
    expect(tester.takeException(), isNull);
    c.dispose();
  });

  group('the practice table', () {
    testWidgets('is offered next to the throw, not buried', (
      WidgetTester tester,
    ) async {
      final GameController c = await buildController();
      await tester.pumpWidget(wrap(c));
      await tester.pump();

      expect(find.widgetWithText(OutlinedButton, '3D DICE'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'ROLL THE DICE'),
        findsOneWidget,
      );
      c.dispose();
    });

    testWidgets('opens the practice screen when tapped', (
      WidgetTester tester,
    ) async {
      final GameController c = await buildController();
      await tester.pumpWidget(wrap(c));
      await tester.pump();

      await tester.tap(find.text('3D DICE'));
      await tester.pumpAndSettle();
      expect(find.byType(DiceLabScreen), findsOneWidget);
      c.dispose();
    });

    testWidgets('returns to a table that is still playable', (
      WidgetTester tester,
    ) async {
      final GameController c = await buildController(startingBalance: 500);
      await tester.pumpWidget(wrap(c));
      await tester.pump();

      await tester.tap(find.text('3D DICE'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // A visit to the practice table must not have staged, cleared or spent
      // anything on the way in or out.
      expect(c.wallet.totalBet, 0);
      expect(c.wallet.balance, 500);
      expect(c.phase, RollPhase.idle);
      expect(find.text('3D DICE'), findsOneWidget);
      c.dispose();
    });

    testWidgets('drops its label rather than crowding the throw', (
      WidgetTester tester,
    ) async {
      useSmallPhone(tester);
      final GameController c = await buildController(startingBalance: 500);
      await tester.pumpWidget(wrap(c));
      await tester.pump();

      // Pinned with the throw, so it is on screen rather than below the fold on
      // the smallest phone the app is expected to run on, and the throw is the
      // control that keeps its space.
      expect(find.byIcon(Icons.view_in_ar_outlined), findsOneWidget);
      expect(find.text('3D DICE'), findsNothing);
      expect(find.byTooltip('Dice practice'), findsOneWidget);

      final Size roll = tester.getSize(
        find.widgetWithText(FilledButton, 'ROLL THE DICE'),
      );
      expect(roll.width, greaterThan(200));
      expect(tester.takeException(), isNull);
      c.dispose();
    });

    testWidgets('keeps its label when there is room for it', (
      WidgetTester tester,
    ) async {
      final GameController c = await buildController(startingBalance: 500);
      await tester.pumpWidget(wrap(c));
      await tester.pump();

      expect(find.text('3D DICE'), findsOneWidget);
      final Size roll = tester.getSize(
        find.widgetWithText(FilledButton, 'ROLL THE DICE'),
      );
      expect(
        roll.width,
        greaterThan(tester.getSize(find.text('3D DICE')).width * 2),
      );
      c.dispose();
    });
  });
}
