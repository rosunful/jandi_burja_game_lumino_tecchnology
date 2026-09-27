import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:janda_burja_game_app/core/config.dart';
import 'package:janda_burja_game_app/logic/dice_roller.dart';
import 'package:janda_burja_game_app/models/symbol.dart';
import 'package:janda_burja_game_app/services/rewarded_ad_service.dart';
import 'package:janda_burja_game_app/services/storage_service.dart';
import 'package:janda_burja_game_app/state/game_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opens a controller over fresh in-memory preferences, muted so no audio
/// plugin is touched.
Future<GameController> openController({
  FakeRewardedAdService? ads,
  int seed = 3,
  int? balance,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final StorageService storage = await StorageService.open();
  await storage.saveSoundEnabled(false);
  await storage.saveHapticsEnabled(false);
  if (balance != null) await storage.saveBalance(balance);
  final GameController controller = GameController(
    storage: storage,
    ads: ads ?? FakeRewardedAdService(),
    roller: DiceRoller(random: Random(seed)),
  );
  await controller.initialise();
  return controller;
}

/// Plays one round of [chips] coins on [symbol] and settles it.
Future<void> playRound(
  GameController controller,
  Symbol symbol,
  int chips,
) async {
  for (int i = 0; i < chips; i++) {
    await controller.addBet(symbol);
  }
  await controller.roll();
}

void main() {
  // These are pure logic tests, but the controller builds an AudioService in its
  // constructor, and that touches a platform channel. The test binding makes the
  // call a harmless no-op instead of a crash.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('balance, stats and last wagers survive a restart', () async {
    final GameController first = await openController(balance: 1000);
    await playRound(first, Symbol.crown, 2);
    final int expectedBalance = first.wallet.balance;
    final int expectedSerial = first.stats.roundsPlayed;
    final Map<Symbol, int> expectedLastBets = first.lastBets;
    first.dispose();

    // A second controller over the same preferences, as if relaunched.
    final StorageService storage = await StorageService.open();
    final GameController second = GameController(
      storage: storage,
      ads: FakeRewardedAdService(),
      roller: DiceRoller(random: Random(99)),
    );

    expect(second.wallet.balance, expectedBalance);
    expect(second.stats.roundsPlayed, expectedSerial);
    expect(second.lastBets, expectedLastBets);
    second.dispose();
  });

  test('a zero-value ad reward still credits the configured amount', () async {
    final FakeRewardedAdService ads = FakeRewardedAdService(rewardAmount: 0);
    final GameController c = await openController(
      ads: ads,
      balance: 0,
    );

    await c.watchRewardedAd();

    expect(
      c.wallet.balance,
      AppConfig.coinsPerRewardedAd,
      reason: 'a zero or missing reward amount must not credit nothing',
    );
    expect(c.stats.coinsFromAds, AppConfig.coinsPerRewardedAd);
    c.dispose();
  });

  test('repeat cannot stage more than the balance allows', () async {
    final GameController c = await openController(balance: 120);
    // A pattern from a richer session than the current balance could fund.
    await c.selectChip(50);
    for (int i = 0; i < 5; i++) {
      await c.addBet(Symbol.crown);
    }
    await c.selectChip(100);
    await c.addBet(Symbol.heart);
    await c.roll();
    c.dispose();

    final StorageService storage = await StorageService.open();
    final GameController broke = GameController(
      storage: storage,
      ads: FakeRewardedAdService(),
      roller: DiceRoller(random: Random(5)),
    );
    // Force the poor state the round could plausibly have produced.
    broke.debugCredit(0);

    await broke.repeatLastBet();

    expect(
      broke.wallet.totalBet,
      lessThanOrEqualTo(broke.wallet.balance),
      reason: 'staged wagers must never exceed the coins actually held',
    );
    for (final MapEntry<Symbol, int> bet in broke.wallet.bets.entries) {
      expect(bet.value, greaterThan(0));
    }
    broke.dispose();
  });

  test('sound and haptics preferences persist', () async {
    final GameController c = await openController();
    expect(c.soundEnabled, isFalse, reason: 'the harness starts muted');

    await c.setSoundEnabled(true);
    await c.setHapticsEnabled(true);

    final StorageService storage = await StorageService.open();
    expect(storage.loadSoundEnabled(false), isTrue);
    expect(storage.loadHapticsEnabled(false), isTrue);
    c.dispose();
  });

  test('a pending ad retry reports failure when the ad never arrives', () async {
    final FakeRewardedAdService ads = FakeRewardedAdService(failToLoad: true);
    final GameController c = await openController(ads: ads, balance: 0);

    await c.retryAd();

    expect(c.adMessage, contains('No ad available'));
    expect(c.adState, RewardedAdState.unavailable);
    c.dispose();
  });

  test('a pending ad retry reports success when the ad arrives', () async {
    final FakeRewardedAdService ads = FakeRewardedAdService(
      failToLoad: true,
    );
    final GameController c = await openController(ads: ads, balance: 0);

    // The network comes back, then the player taps "try again".
    ads.failToLoad = false;
    await c.retryAd();

    expect(c.adState, RewardedAdState.ready);
    expect(c.adMessage, contains('Ad ready'));
    c.dispose();
  });

  test('an ad becoming ready on its own does not spam a message', () async {
    final FakeRewardedAdService ads = FakeRewardedAdService(
      failToLoad: true,
    );
    final GameController c = await openController(ads: ads, balance: 0);
    expect(c.adMessage, isNull);

    // A background preload succeeding is not a player-visible event.
    ads.failToLoad = false;
    await ads.preload();

    expect(c.adMessage, isNull);
    c.dispose();
  });

  test('the roll serial only advances on a settled round', () async {
    final GameController c = await openController(balance: 500);
    expect(c.roundSerial, 0);

    await playRound(c, Symbol.crown, 1);
    expect(c.roundSerial, 1);

    // Staging another wager must not look like a new round.
    await c.addBet(Symbol.heart);
    expect(c.roundSerial, 1);
    c.dispose();
  });
}
