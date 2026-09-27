/// Central, tunable configuration for the whole game.
///
/// Everything a designer or a playtester is likely to want to adjust lives
/// here rather than being scattered through the code. In particular the
/// payout table and the ad identifiers are the two values most likely to
/// change between builds.
class AppConfig {
  const AppConfig._();

  static const String appName = 'Janda Burja';

  // ---------------------------------------------------------------- economy
  /// Coins a brand new player starts with.
  static const int startingCoins = 5000;

  /// Coins granted for watching one rewarded video to completion.
  static const int coinsPerRewardedAd = 500;

  /// Smallest legal wager on a single symbol.
  static const int minBet = 10;

  /// Largest legal wager on a single symbol.
  static const int maxBetPerSymbol = 2000;

  /// Largest legal sum across all symbols in a single round.
  static const int maxTotalBet = 6000;

  /// Chip the player starts with selected.
  static const int defaultChip = 50;

  /// Selectable chip denominations, ascending.
  static const List<int> chipDenominations = <int>[10, 50, 100, 500, 1000];

  // ------------------------------------------------------------------- dice
  /// Number of dice thrown per round.
  static const int diceCount = 6;

  /// How many dice must show the bet symbol for the bet to win.
  ///
  /// This value is the single most important number in the game. At 2 it gives
  /// a return-to-player of 86.13% (house edge 13.87%), which is what makes the
  /// coin economy work: a player genuinely runs out of coins over time.
  ///
  /// Setting this to 1 would pay k x the stake for a single matching die and
  /// hand the player a 166% return, so the balance would grow without bound and
  /// the watch-an-ad refill would never be needed. See docs/rules.md.
  static const int minDiceToWin = 2;

  // -------------------------------------------------------------------- ads
  /// AdMob rewarded-video ad unit.
  ///
  /// THIS IS GOOGLE'S OFFICIAL TEST UNIT ID. It serves a dummy ad and earns
  /// no revenue. It is deliberate: AdMob suspends accounts whose apps serve
  /// test ads in production.
  ///
  /// TODO(RELEASE): replace with your own rewarded ad unit id before
  /// publishing, and flip [usingTestAdIds] to false. The release build
  /// refuses to ship while this flag is true (see
  /// `assertNotShippingTestAds`).
  static const String admobRewardedUnitId =
      'ca-app-pub-3940256099942544/5224354917';

  /// True while the dummy test ad unit is in use.
  static const bool usingTestAdIds = true;

  // ------------------------------------------------------------------ audio
  static const bool soundEnabledByDefault = true;
  static const bool hapticsEnabledByDefault = true;
}
