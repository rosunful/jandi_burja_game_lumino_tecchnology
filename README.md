# Janda Burja

An Android dice game of chance in the Jhandi Munda / Crown and Anchor
tradition. Six dice, six symbols, play-money coins, and optional rewarded ads to
refill a balance that a 13.87% house edge will genuinely drain.

No real money is involved anywhere: no purchases, no deposits, no cash-out, and
no prizes. The game is fully playable offline.

Full rules and the payout mathematics: [`docs/rules.md`](docs/rules.md).

## Running it

```bash
flutter pub get
flutter run                 # debug, on a connected device
flutter test                # 86 unit and widget tests
flutter analyze             # must stay clean
```

## What is in the app

- **First-run disclosure.** A non-dismissible dialog states 18+, free to play
  and no real money before the table is reachable. Acknowledged once per
  install, then never again. The same copy appears on the rules screen; it
  lives in one widget so the two cannot drift apart.
- **The table.** Six dice, six symbols, tap to stage chips, long-press to add
  half, the minus button to wind a wager back. Undo, repeat, and clear.
- **Results.** Winnings light the symbols that paid, with a per-wager
  breakdown, and the balance only moves once the dice have stopped.
- **Rules and stats.** The full payout table and odds; lifetime play and coin
  statistics, including the player's own observed return against the published
  86.13%.
- **Settings.** Sound and haptics toggles, ad status with a working retry, and
  the value disclosure.

## How it is put together

```
lib/
  core/       config and theme; every tunable number lives in core/config.dart
  models/     Symbol, Bet, RoundResult, GameStats - plain data
  logic/      payout table, dice roller, game engine, wallet - pure Dart, no Flutter
  services/   storage, audio, rewarded ads
  state/      GameController - the single ChangeNotifier the UI listens to
  ui/         screens and widgets
```

The rules engine imports nothing from Flutter. That is what lets the whole
economy be unit tested on the Dart VM in milliseconds, and it is why
`test/payout_table_test.dart` can assert the exact 86.13% return to player.

`RewardedAdService` is an interface with two implementations: the real
`AdMobRewardedAdService` and `FakeRewardedAdService`. Widget tests use the fake,
so the ad-refill and no-network paths are covered without a device.

## Coins

| Setting                   | Value              |
| ------------------------- | ------------------ |
| Starting balance          | 5000               |
| Smallest wager            | 10                 |
| Largest wager, one symbol | 2000               |
| Largest total, one throw  | 6000               |
| Chips                     | 10, 50, 100, 500, 1000 |
| Coins per rewarded ad     | 500                |

Balance, selected chip, last wagers, lifetime statistics, and the sound and
haptics preferences all persist via `shared_preferences`.

## Ads

The app ships with **Google's official test ad unit**, so it earns nothing and
cannot risk the AdMob account:

- App ID: `ca-app-pub-3940256099942544~3347511713`
- Rewarded unit: `ca-app-pub-3940256099942544/5224354917`

A player who runs out of coins is offered 500 coins for watching one rewarded
video to completion. Coins are granted only from the SDK's reward callback, so
dismissing the ad early pays nothing and the refill cannot be farmed. If no ad
can be loaded — typically offline — the game says so, offers a retry, and stays
fully playable.

`RewardedAdService` pushes state changes to the controller rather than
returning them, because a real AdMob load finishes long after the call that
started it. Without that, a retry could never report success.

## Before you publish

1. **Replace the ad unit.** Put your own rewarded unit id in
   `AppConfig.admobRewardedUnitId` and replace the App ID in
   `android/app/src/main/AndroidManifest.xml`, then set
   `AppConfig.usingTestAdIds` to `false`. Publishing with Google's test ids
   earns nothing; serving them to real users can get the AdMob account
   suspended.
2. **Sign the release build.** `android/app/build.gradle.kts` still falls back
   to debug signing. Create a keystore, add a `key.properties` (git-ignored)
   with `storeFile`, `storePassword`, `keyAlias` and `keyPassword`, and wire it
   into the `signingConfigs` block. Never commit the keystore.
3. **Add consent handling** if you serve ads in the EEA/UK. There is no UMP
   flow yet.
4. **Set the Play listing as gambling / 18+** with the free-to-play and
   no-cash-out disclosures already on the rules screen.

## Assets

All artwork and audio is bundled, so nothing is downloaded at runtime:

- `assets/symbols/*.svg` — six symbols plus a chip and a coin, hand-authored as
  single-colour SVG and tinted at render time
- `assets/felt/felt.png` — the table surface
- `assets/audio/*.wav` — chip, dice and win/lose sounds

`tools/generate_assets.py` regenerates the felt texture and every sound
deterministically, using only the standard library.
