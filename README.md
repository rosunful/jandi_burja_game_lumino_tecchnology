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
flutter test                # 108 unit and widget tests
flutter analyze             # must stay clean
```

## What is in the app

- **First-run disclosure.** A non-dismissible dialog states 18+, free to play
  and no real money before the table is reachable. Acknowledged once per
  install, then never again. The same copy appears on the rules screen; it
  lives in one widget so the two cannot drift apart.
  - **The hero card.** One card at the top of the table carries the balance on
    the left and the coin refill on the right, side by side, so a player who is
    out of coins sees how to get more without scrolling. The stake for this throw
    sits directly underneath it as plain text rather than inside the card, which
    keeps the card a single glanceable row instead of three stacked facts.
  - **The stake line.** Centred under the card, with the amount on its own line
    below the words, so the number is the middle of the screen rather than
    something at the end of a row to hunt for. Nothing is drawn under the label
    until there is a wager to show, and a player with no coins left gets the
    reason to watch an ad in the same place, so the line never jumps side.
 - **The table.** Six symbols, tap to stage chips, long-press to add half, the
   minus button to wind a wager back. Undo, repeat, and clear sit under the coin
   grid, between the denominations and the roll button.
 - **The coins.** All five denominations as a grid, every value on screen at
   once. A horizontal scroller hid the option you wanted as often as not.
 - **The roll button.** `ROLL THE DICE` is pinned to the bottom of the table and
   never scrolls, while everything above it does. It is the one control a player
   reaches for mid-decision, so it should not move when the rest of the table
   does.
  - **The throw.** `ROLL THE DICE` pushes a separate screen so the dice own the
    whole viewport while they move and the result is the only thing at eye level
    once they stop, with a per-wager breakdown. The balance only moves after the
    dice have stopped. `PLAY AGAIN` and the Android back button both return to
    the table; the back button is ignored mid-throw so nobody leaves an
    unacknowledged result behind.
  - **A practice table for the 3D dice.** `3D DICE` next to the throw opens a
    separate screen where dice can be thrown for nothing, one to six of them
    (chosen on the page), and watched. It is a real 3D scene under a web view,
    not a widget tree: `model_viewer_plus` serves an HTML page over a loopback
    socket and the dice tumble in JavaScript at 240 hertz. It reads nothing from
    the wallet, stages no bet and opens no round: it borrows the controller for
    its sound service and nothing else. On a narrow phone it drops its label to
    an icon so the throw keeps the width.
  - **Rules and stats.** The full payout table and odds; lifetime play and coin
    statistics, including the player's own observed return against the published
    86.13%.
  - **Sound that keeps up with the fingers.** Placing a chip is the most
    repeated action in the game, so its sounds are preloaded at start-up and
    played through low-latency voices rather than being prepared at the moment of
    the tap. Two voices per sound, so a second chip does not cut the first
    click short. A game that boots muted never touches the audio plugin at all.
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
    screens/dice_lab_screen.dart  hosts the 3D practice table and its bridges
    screens/dice_lab_web.dart     the page's HTML/CSS/JS and the viewer builder
```

The rules engine imports nothing from Flutter. That is what lets the whole
economy be unit tested on the Dart VM in milliseconds, and it is why
`test/payout_table_test.dart` can assert the exact 86.13% return to player.

The practice table is split by process rather than by import. `dice_lab_web.dart`
is the whole 3D table — markup, styling, physics — as a single page served into a
`model_viewer_plus` view from a loopback HTTP server, with the dice model bundled
as `assets/dice.glb`. `dice_lab_screen.dart` hosts that view, paints the felt
behind it so nothing flashes white while the server starts, and bridges back two
JavaScript channels: `DiceNav` for the page's own back arrow, `DiceAudio` for
every throw. Flutter never sees a single vertex; the seam is exactly two strings.

`RewardedAdService` is an interface with two implementations: the real
`AdMobRewardedAdService` and `FakeRewardedAdService`. Widget tests use the fake,
so the ad-refill and no-network paths are covered without a device.

## The 3D dice

The practice table is a page of HTML/CSS/JavaScript rendered through a
`model_viewer_plus` web view, not a CustomPainter. The dice are the bundled
`assets/dice.glb` model; the throw is simulated in JavaScript at 240 hertz and
written to the DOM as transforms, so the frame budget belongs to the physics
rather than to the widget tree. Four things about it are less obvious than they
look.

**Flutter hosts, it does not draw.** `dice_lab_screen.dart` owns the chrome, the
felt colour and the two bridge channels; `dice_lab_web.dart` owns the dice. The
back arrow lives inside the page's own app bar and posts `DiceNav`; every throw
posts `DiceAudio`, so the game's own rattle and roll sounds land on this screen
too. Both channels are guarded in JavaScript, so a page served where a channel
is missing degrades to "no sound, no shortcut" rather than a `JS ERROR` banner
over the dice.

**The die colours hold to local truth.** Faces in this game are `1` and `6` red,
and so is the page: `1` is the black heart, `6` the red diamond, and the suits
are drawn rather than loaded. The ported source had the red check back to front
(`3` and `4`); it is corrected here.

**`DiceAudio` fires on the throw, not on the frame.** The page reports the moment
the dice leave the cup, Flutter plays the rattle and a medium haptic at once, and
the roll sound a beat later, so the sound tracks the dice landing rather than
the button press. A rethrow cancels the pending roll, so hammering the table
cannot stack three landings under one throw.

**The model is local and the network is not.** `model_viewer_plus` serves the
page and the `.glb` over a loopback socket, which is why Android allows cleartext
traffic and iOS has embedded views enabled. Everything else the page needs ships
in the bundle, so a practice throw works offline like everything else.

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

Any player can watch a rewarded video to completion for 500 coins; the button
lives in the hero card at all times, so where coins come from is visible before
you need them rather than only once you are already broke. Coins are granted
only from the SDK's reward callback, so dismissing the ad early pays nothing and
the refill cannot be farmed. If no ad can be loaded — typically offline — the
game says so, offers a retry, and stays fully playable.

The amount comes from `AppConfig.coinsPerRewardedAd` alone. The SDK does report
a `RewardItem`, and AdMob's test unit reports **10**, but that is a test
artifact rather than a payout; acting on it credited 10 coins against a button
promising 500. The SDK decides *whether* the ad was watched, never what it pays.

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
- `assets/audio/*.wav` — chip, dice and win/lose sounds
- `assets/dice.glb` — the 3D dice model, served to the practice table
- `assets/felt/felt.png` — the table surface

`tools/generate_assets.py` regenerates the felt texture and every sound
deterministically, using only the standard library.
