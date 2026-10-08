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

  test(
    'a wager saved under the old anchor name still repeats as the flag',
    () async {
      // Wagers are persisted by enum name, so renaming the jhanda symbol from
      // "anchor" to "flag" would otherwise drop the Repeat wager of every install
      // that had one, silently and with nothing to notice.
      expect(
        Symbol.flag.localName,
        'jhanda',
        reason: 'the local name never moved',
      );

      // Seeded the way an install that predates the rename looks on disk.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'last_bets': <String>['anchor:200', 'crown:10'],
      });
      final StorageService storage = await StorageService.open();

      expect(
        storage.loadLastBets(),
        <Symbol, int>{Symbol.flag: 200, Symbol.crown: 10},
        reason: 'the saved wager must follow the symbol to its new name',
      );

      // And the whole point of the saved wager: repeating it stages the flag.
      final GameController c = GameController(
        storage: storage,
        ads: FakeRewardedAdService(),
        roller: DiceRoller(random: Random(3)),
      );
      await c.initialise();
      await c.repeatLastBet();
      expect(c.wallet.bets[Symbol.flag], 200);
      c.dispose();
    },
  );

  test('preloading the tap sounds cannot break a game with no audio', () async {
    // Warming happens at start-up on every device, and on a device with no
    // working audio plugin every one of those loads fails. None of it may reach
    // the player as an error, a hang, or a chip that stops being placed.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sound_enabled': true,
      'haptics_enabled': false,
    });
    final StorageService storage = await StorageService.open();
    final GameController c = GameController(
      storage: storage,
      ads: FakeRewardedAdService(),
      roller: DiceRoller(random: Random(3)),
    );
    await c.initialise();

    // Sound is on, so the warm-up really did run and really did fail.
    expect(c.soundEnabled, isTrue);
    await c.addBet(Symbol.crown);
    await c.addBet(Symbol.crown);

    expect(
      c.wallet.bets[Symbol.crown],
      AppConfig.defaultChip * 2,
      reason: 'a sound that cannot play must not cost the player their wager',
    );
    c.dispose();
  });

  test('a game that boots muted never reaches for the audio plugin', () async {
    // The widget tests rely on this: a muted test must not have platform
    // channels called on its behalf, or every run pays for an audio warm-up it
    // never asked for.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sound_enabled': false,
      'haptics_enabled': false,
    });
    final StorageService storage = await StorageService.open();
    final GameController c = GameController(
      storage: storage,
      ads: FakeRewardedAdService(),
      roller: DiceRoller(random: Random(3)),
    );
    await c.initialise();

    expect(c.soundEnabled, isFalse);
    await c.addBet(Symbol.crown);
    expect(c.wallet.bets[Symbol.crown], AppConfig.defaultChip);
    c.dispose();
  });

  test('the chosen denomination survives a restart', () async {
    // The tap path only writes the denomination when it has changed, so the
    // bookkeeping that decides "changed" is what persistence now rests on.
    final GameController first = await openController(balance: 1000);
    await first.selectChip(100);
    await first.addBet(Symbol.crown);
    first.dispose();

    final StorageService storage = await StorageService.open();
    final GameController second = GameController(
      storage: storage,
      ads: FakeRewardedAdService(),
      roller: DiceRoller(random: Random(3)),
    );
    await second.initialise();

    expect(
      second.wallet.selectedChip,
      100,
      reason: 'the coin the player chose is the coin they come back to',
    );
    second.dispose();
  });

  test('a zero-value ad reward still credits the configured amount', () async {
    final FakeRewardedAdService ads = FakeRewardedAdService(rewardAmount: 0);
    final GameController c = await openController(ads: ads, balance: 0);

    await c.watchRewardedAd();

    expect(
      c.wallet.balance,
      AppConfig.coinsPerRewardedAd,
      reason: 'a zero or missing reward amount must not credit nothing',
    );
    expect(c.stats.coinsFromAds, AppConfig.coinsPerRewardedAd);
    c.dispose();
  });

  test('the ad SDK cannot override the configured reward', () async {
    // AdMob's own test unit reports a RewardItem of 10. Taking the SDK's number
    // at face value paid 10 against a button promising 500, which is the bug
    // this test exists to stop returning.
    final FakeRewardedAdService ads = FakeRewardedAdService(rewardAmount: 10);
    final GameController c = await openController(ads: ads, balance: 100);

    await c.watchRewardedAd();

    expect(
      c.wallet.balance,
      100 + AppConfig.coinsPerRewardedAd,
      reason: 'the SDK decides whether the ad was watched, not what it pays',
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

  test(
    'a pending ad retry reports failure when the ad never arrives',
    () async {
      final FakeRewardedAdService ads = FakeRewardedAdService(failToLoad: true);
      final GameController c = await openController(ads: ads, balance: 0);

      await c.retryAd();

      expect(c.adMessage, contains('No ad available'));
      expect(c.adState, RewardedAdState.unavailable);
      c.dispose();
    },
  );

  test('a pending ad retry reports success when the ad arrives', () async {
    final FakeRewardedAdService ads = FakeRewardedAdService(failToLoad: true);
    final GameController c = await openController(ads: ads, balance: 0);

    // The network comes back, then the player taps "try again".
    ads.failToLoad = false;
    await c.retryAd();

    expect(c.adState, RewardedAdState.ready);
    expect(c.adMessage, contains('Ad ready'));
    c.dispose();
  });

  test('an ad becoming ready on its own does not spam a message', () async {
    final FakeRewardedAdService ads = FakeRewardedAdService(failToLoad: true);
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
