
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:janda_burja_game_app/state/game_controller.dart';
import 'package:janda_burja_game_app/ui/screens/dice_lab_screen.dart';
import 'package:janda_burja_game_app/ui/widgets/symbol_icon.dart';

import 'game_screen_test.dart' show buildController;

/// The practice screen, so far as the test VM can see it.
///
/// The dice, the throw button and the chrome around them live in HTML inside a
/// web view served over a loopback socket, and neither that server nor the web
/// view plugin exists under `flutter test` - `DiceLabScreen.viewerOverride`
/// swaps the body out for a placeholder, and these tests hold the rest of the
/// screen to the promises the Flutter side actually makes: it hosts the page,
/// it says that nothing is staked, it never touches the money, and it lets the
/// player leave.
void main() {
  const String note =
      'Practice only. No coins are staked and nothing is won or lost.';

  setUp(() {
    DiceLabScreen.viewerOverride = () => const SizedBox(key: Key('diceLabViewer'));
  });

  tearDown(() {
    DiceLabScreen.viewerOverride = null;
  });

  Future<void> openLab(WidgetTester tester, GameController controller) async {
    await tester.pumpWidget(
      MaterialApp(home: DiceLabScreen(controller: controller)),
    );
    await tester.pump();
  }

  testWidgets('opens on a quiet table with nothing thrown', (
    WidgetTester tester,
  ) async {
    final GameController controller = await buildController();
    addTearDown(controller.dispose);
    await openLab(tester, controller);

    // The page is hosted full bleed, behind everything else, so the felt shows
    // the moment the route is pushed rather than a white rectangle waiting on
    // the loopback server to come up.
    expect(find.byKey(const Key('diceLabViewer')), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      const Color(0xFF14501A),
    );
    // No result has been dealt: the page has not thrown yet, and no symbol is
    // on screen pretending otherwise.
    expect(find.byType(SymbolIcon), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('says out loud that nothing is staked', (
    WidgetTester tester,
  ) async {
    final GameController controller = await buildController();
    addTearDown(controller.dispose);
    await openLab(tester, controller);

    expect(find.text(note), findsOneWidget);
  });

  testWidgets('leaves the caption out of the way of the dice', (
    WidgetTester tester,
  ) async {
    final GameController controller = await buildController();
    addTearDown(controller.dispose);
    await openLab(tester, controller);

    // The note floats over the page. It must not be the thing a tap reaches:
    // dragging a die through the bottom of the screen is a normal throw.
    // MaterialApp itself wraps the tree in at least one `IgnorePointer`; the
    // one that matters is the screen's own, which is the one ignoring.
    expect(
      find.ancestor(
        of: find.text(note),
        matching: find.byWidgetPredicate(
          (Widget w) => w is IgnorePointer && w.ignoring,
        ),
      ),
      findsWidgets,
    );
  });

  testWidgets('leaves the balance and the board exactly as it found them', (
    WidgetTester tester,
  ) async {
    final GameController controller = await buildController(
      startingBalance: 1000,
    );
    addTearDown(controller.dispose);

    final int balance = controller.wallet.balance;
    final int round = controller.roundSerial;

    await openLab(tester, controller);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(DiceLabScreen), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(home: const SizedBox()), // pop the route
    );
    await tester.pump();

    expect(controller.wallet.balance, balance);
    expect(controller.wallet.totalBet, 0);
    expect(controller.roundSerial, round);
    expect(controller.lastRound, isNull);
    expect(controller.phase, RollPhase.idle);
  });

  testWidgets('goes back to the table with the system back button', (
    WidgetTester tester,
  ) async {
    final GameController controller = await buildController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DiceLabScreen(controller: controller),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(DiceLabScreen), findsOneWidget);

    // The Android back gesture, not a button on screen: the page draws its own
    // arrow and posts it down a channel, which the test VM cannot reach.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(DiceLabScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
