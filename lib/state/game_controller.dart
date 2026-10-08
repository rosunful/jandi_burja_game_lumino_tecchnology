import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../logic/dice_roller.dart';
import '../logic/game_engine.dart';
import '../logic/wallet.dart';
import '../models/bet.dart';
import '../models/stats.dart';
import '../models/symbol.dart';
import '../services/audio_service.dart';
import '../services/rewarded_ad_service.dart';
import '../services/storage_service.dart';

/// What the roll button should currently offer the player.
enum RollPhase {
  /// No wagers staged; the button is disabled.
  idle,

  /// Wagers staged and waiting for the throw.
  ready,

  /// Dice are tumbling; input is locked.
  rolling,

  /// Results are on screen and awaiting acknowledgement.
  settled,
}

/// Single source of truth for the game screen.
///
/// A plain [ChangeNotifier] rather than a state-management package: the app
/// has exactly one screen worth of state, and the built-in `ListenableBuilder`
/// is enough. All money maths is delegated to the pure [GameEngine] and
/// [Wallet] so this class only orchestrates.
class GameController extends ChangeNotifier {
  // Named parameters cannot be named after private fields, so the
  // initializing-formal lint does not apply to these three.
  // ignore: prefer_initializing_formals
  GameController({
    required StorageService storage,
    required RewardedAdService ads,
    AudioService? audio,
    DiceRoller? roller,
    // Named parameters cannot be named after private fields, so the
    // initializing-formal form is not expressible for these two.
    // ignore: prefer_initializing_formals
  }) : _storage = storage,
       // ignore: prefer_initializing_formals
       _ads = ads,
       _audio = audio ?? AudioService(),
       _roller = roller ?? DiceRoller() {
    _wallet = Wallet(
      balance: _storage.loadBalance(AppConfig.startingCoins),
      selectedChip: _storage.loadSelectedChip() ?? AppConfig.defaultChip,
    );
    // What the wallet was seeded with, so a tap can tell whether the choice on
    // screen still matches what is on disk without asking storage on every
    // chip placed.
    _persistedChip = _wallet.selectedChip;
    _lastBets = _storage.loadLastBets();
    _stats = _storage.loadStats();
    _audio.configure(
      sound: _storage.loadSoundEnabled(AppConfig.soundEnabledByDefault),
      haptics: _storage.loadHapticsEnabled(AppConfig.hapticsEnabledByDefault),
    );
    // An ad load finishes long after the call that started it, so the service
    // pushes state changes here rather than returning them.
    _ads.onStateChanged = _onAdStateChanged;
  }

  static const GameEngine _engine = GameEngine();

  final StorageService _storage;
  final RewardedAdService _ads;
  final AudioService _audio;
  final DiceRoller _roller;

  late final Wallet _wallet;

  /// The denomination last read from or written to storage.
  ///
  /// Placing a chip does not change the denomination, so the tap path needs
  /// this to know a write is unnecessary without reading storage again.
  late int _persistedChip;

  late Map<Symbol, int> _lastBets;
  late GameStats _stats;

  RollPhase _phase = RollPhase.idle;
  RoundResult? _lastRound;
  List<Symbol> _rollingFaces = const <Symbol>[];
  int _roundSerial = 0;
  BetRejection? _lastRejection;
  bool _adRewardPending = false;
  bool _awaitingAdRetry = false;
  String? _adMessage;
  Timer? _adMessageTimer;

  // ------------------------------------------------------------------ getters
  Wallet get wallet => _wallet;
  GameStats get stats => _stats;
  RollPhase get phase => _phase;
  RoundResult? get lastRound => _lastRound;

  /// Increments once per settled round.
  ///
  /// The UI keys celebrations off this rather than off [lastRound], because a
  /// round stays on screen for as long as the player takes to acknowledge it
  /// and every unrelated notification in the meantime would otherwise re-fire
  /// the same confetti.
  int get roundSerial => _roundSerial;

  /// Faces for the dice currently on the table.
  ///
  /// The throw is generated up front and held for the length of the animation,
  /// so the dice tumble towards the result they are actually going to show
  /// rather than towards a placeholder. Empty while the board is face down.
  List<Symbol> get visibleFaces {
    if (_phase == RollPhase.rolling && _rollingFaces.isNotEmpty) {
      return _rollingFaces;
    }
    return _lastRound?.faces ?? const <Symbol>[];
  }

  /// Symbols the player has money on right now, used to rim-light the dice.
  Set<Symbol> get backedSymbols {
    if (_phase == RollPhase.settled && _lastRound != null) {
      return <Symbol>{
        for (final BetResult r in _lastRound!.results) r.bet.symbol,
      };
    }
    return _wallet.bets.keys.toSet();
  }

  Map<Symbol, int> get lastBets => Map<Symbol, int>.unmodifiable(_lastBets);
  BetRejection? get lastRejection => _lastRejection;
  bool get soundEnabled => _audio.soundEnabled;
  bool get hapticsEnabled => _audio.hapticsEnabled;

  /// The sound and haptics engine, for screens that are not part of a round.
  ///
  /// Read only on purpose. The practice dice are free throws, so the one thing
  /// they must never do is touch the wallet, and handing out the whole service
  /// makes that a convention rather than a rule. Everything the practice screen
  /// needs from a round it gets through the engine it already has.
  AudioService get audio => _audio;
  RewardedAdState get adState => _ads.state;
  String? get adMessage => _adMessage;

  /// True when the player has run out of coins and must watch an ad to
  /// continue. This is the intended end of a losing streak, not a failure.
  bool get isBroke => _wallet.balance < AppConfig.minBet;

  /// The button is live only when wagers are staged and dice are not moving.
  bool get canRoll => _phase == RollPhase.ready && _wallet.hasBets;

  /// The last bet pattern can be repeated only if there is something to repeat.
  bool get canRepeatLast => _lastBets.isNotEmpty;

  // ----------------------------------------------------------------- lifecycle
  Future<void> initialise() async {
    unawaited(_ads.initialize());
    // Off the critical path and not awaited: this preloads the tap sounds so
    // the first chip the player places is not the slowest one. A game that
    // boots muted does not warm at all.
    _audio.warm();
    notifyListeners();
  }

  @override
  void dispose() {
    _adMessageTimer?.cancel();
    unawaited(_audio.dispose());
    unawaited(_ads.dispose());
    super.dispose();
  }

  // --------------------------------------------------------------------- bets
  /// Stages one chip of the currently selected denomination on [symbol].
  ///
  /// Returns false and surfaces a reason when the wager is not legal, so the
  /// UI can explain rather than silently ignoring the tap.
  Future<bool> addBet(Symbol symbol) async {
    if (_phase == RollPhase.rolling || _phase == RollPhase.settled) {
      return false;
    }

    final int chip = _wallet.selectedChip;
    final BetRejection? rejection = _engine.validateBet(
      currentStake: _wallet.bets[symbol] ?? 0,
      additional: chip,
      balance: _wallet.balance,
      existingTotalBet: _wallet.totalBet,
    );

    if (rejection != null) {
      _lastRejection = rejection;
      notifyListeners();
      return false;
    }

    _wallet.addToBet(symbol, chip);
    _lastRejection = null;
    _updatePhase();
    notifyListeners();

    // The denomination is chosen on the coin row, not here, so this only needs
    // writing when it is not already what is on disk. Placing twenty chips in a
    // row used to mean twenty platform writes for one unchanged value.
    if (chip != _persistedChip) {
      _persistedChip = chip;
      unawaited(_storage.saveSelectedChip(chip));
    }
    unawaited(_audio.play(GameSound.chipPlace));
    unawaited(_audio.haptic(HapticLevel.light));
    return true;
  }

  /// Removes one chip from the wager on [symbol].
  Future<void> removeBet(Symbol symbol) async {
    if (_phase == RollPhase.rolling) return;
    _wallet.removeFromBet(symbol, _wallet.selectedChip);
    _updatePhase();
    notifyListeners();
    unawaited(_audio.play(GameSound.select));
    unawaited(_audio.haptic(HapticLevel.selection));
  }

  /// Clears every staged wager, or the last result once settled.
  Future<void> clearBoard() async {
    if (_phase == RollPhase.rolling) return;
    if (_phase == RollPhase.settled) {
      await _acknowledge();
      return;
    }
    _wallet.clearAllBets();
    _lastRejection = null;
    _updatePhase();
    notifyListeners();
    unawaited(_audio.play(GameSound.select));
  }

  /// Undoes the most recent chip placement, one chip at a time.
  Future<void> undoLastBet() async {
    if (_phase == RollPhase.rolling || !_wallet.hasBets) return;

    // With no per-wager timestamp, "most recent" is approximated by the
    // largest stack, which is what a player means by undo in practice.
    MapEntry<Symbol, int>? largest;
    for (final MapEntry<Symbol, int> entry in _wallet.bets.entries) {
      if (largest == null || entry.value > largest.value) largest = entry;
    }
    if (largest == null) return;

    _wallet.removeFromBet(largest.key, _wallet.selectedChip);
    _updatePhase();
    notifyListeners();
    unawaited(_audio.play(GameSound.select));
  }

  /// Restages the previous round's wagers.
  Future<void> repeatLastBet() async {
    if (_phase == RollPhase.rolling || _lastBets.isEmpty) return;
    _wallet.repeat(_lastBets);
    _lastRejection = null;
    _updatePhase();
    notifyListeners();
    unawaited(_audio.play(GameSound.chipPlace));
    unawaited(_audio.haptic(HapticLevel.light));
  }

  /// Adds half the current stake on [symbol], rounded to a whole chip.
  Future<void> addHalf(Symbol symbol) async {
    if (_phase == RollPhase.rolling || _phase == RollPhase.settled) return;
    final int current = _wallet.bets[symbol] ?? 0;
    if (current <= 0) return;
    _wallet.addToBet(symbol, current ~/ 2);
    _lastRejection = null;
    _updatePhase();
    notifyListeners();
    unawaited(_audio.play(GameSound.chipPlace));
  }

  Future<void> selectChip(int denomination) async {
    if (_wallet.selectedChip == denomination) return;
    _wallet.selectChip(denomination);
    _persistedChip = denomination;
    notifyListeners();
    unawaited(_storage.saveSelectedChip(denomination));
    unawaited(_audio.play(GameSound.select));
  }

  // --------------------------------------------------------------------- roll
  /// Throws the dice and settles every staged wager.
  ///
  /// The faces are drawn before the animation starts and the result is applied
  /// only after it finishes, so the dice the player watches are the dice that
  /// are scored. The result is then held until the player acknowledges it.
  Future<void> roll() async {
    if (!canRoll) return;

    final List<Bet> bets = <Bet>[
      for (final MapEntry<Symbol, int> e in _wallet.bets.entries)
        Bet(symbol: e.key, amount: e.value),
    ];
    _lastBets = Map<Symbol, int>.from(_wallet.snapshotBets());
    _rollingFaces = _roller.roll();

    _phase = RollPhase.rolling;
    _lastRound = null;
    _lastRejection = null;
    notifyListeners();

    unawaited(_audio.play(GameSound.diceRattle));
    unawaited(_audio.haptic(HapticLevel.medium));

    // Slightly longer than the tumble in DieFaceView, so the last thing the
    // player sees moving is the dice coming to rest, not the numbers appearing.
    await Future<void>.delayed(const Duration(milliseconds: 950));

    unawaited(_audio.play(GameSound.diceRoll));

    final RoundResult result = _engine.settle(bets, _rollingFaces);
    _wallet.applyRound(result);
    _lastRound = result;
    _rollingFaces = const <Symbol>[];
    _roundSerial++;
    _phase = RollPhase.settled;

    _stats = _stats.copyWith(
      roundsPlayed: _stats.roundsPlayed + 1,
      roundsWon: _stats.roundsWon + (result.won ? 1 : 0),
      coinsWagered: _stats.coinsWagered + result.totalStake,
      coinsReturned: _stats.coinsReturned + result.totalReturned,
      biggestWin: _stats.biggestWin < result.netChange
          ? result.netChange
          : _stats.biggestWin,
      biggestLoss: _stats.biggestLoss > result.netChange
          ? result.netChange
          : _stats.biggestLoss,
    );

    unawaited(_storage.saveBalance(_wallet.balance));
    unawaited(_storage.saveLastBets(_lastBets));
    unawaited(_storage.saveStats(_stats));

    if (result.won) {
      final bool big = result.netChange >= AppConfig.minBet * 5;
      unawaited(_audio.play(big ? GameSound.winBig : GameSound.win));
      unawaited(_audio.haptic(big ? HapticLevel.heavy : HapticLevel.medium));
    } else {
      unawaited(_audio.play(GameSound.lose));
      unawaited(_audio.haptic(HapticLevel.light));
    }

    notifyListeners();
  }

  /// Clears the settled result and returns to a fresh board.
  Future<void> _acknowledge() async {
    _lastRound = null;
    _lastRejection = null;
    _updatePhase();
    notifyListeners();
  }

  void _updatePhase() {
    _phase = _wallet.hasBets ? RollPhase.ready : RollPhase.idle;
  }

  // ---------------------------------------------------------------------- ads
  /// Shows a rewarded ad and credits coins when it is watched to completion.
  ///
  /// Coins are granted only from [RewardedAdService.show]'s reward callback, so
  /// dismissing the ad early grants nothing and cannot be farmed.
  Future<void> watchRewardedAd() async {
    if (_adRewardPending) return;
    _adRewardPending = true;
    notifyListeners();

    try {
      final bool shown = await _ads.show(
        onReward: (int _) {
          // The SDK decides *whether* the ad was watched, never how much it
          // pays. AdMob's own test unit reports 10, which is not a denomination
          // this game trades in, and trusting it silently overrode the
          // configured grant and broke the promise the UI makes on the button.
          final int amount = AppConfig.coinsPerRewardedAd;
          _wallet.credit(amount);
          _stats = _stats.copyWith(
            adsWatched: _stats.adsWatched + 1,
            coinsFromAds: _stats.coinsFromAds + amount,
          );
          unawaited(_storage.saveBalance(_wallet.balance));
          unawaited(_storage.saveStats(_stats));
          _updatePhase();
          _flashMessage('+$amount coins added');
          notifyListeners();
        },
      );

      if (!shown) {
        _flashMessage(_noAdMessage);
      }
    } finally {
      _adRewardPending = false;
      notifyListeners();
    }
  }

  bool get adRewardPending => _adRewardPending;

  /// Nudges the ad layer to fetch a replacement after a failure.
  ///
  /// The outcome is reported by [_onAdStateChanged] when the load lands, since
  /// a real AdMob load completes long after this call returns.
  Future<void> retryAd() async {
    _adMessage = null;
    _awaitingAdRetry = true;
    await _ads.preload();
    // A synchronous implementation (the fake, or a cached response) has
    // already moved the state and been reported by now, so only announce a
    // failure here if nothing else has spoken yet.
    if (_awaitingAdRetry && _ads.state == RewardedAdState.unavailable) {
      _awaitingAdRetry = false;
      _flashMessage(_noAdMessage);
    }
    notifyListeners();
  }

  static const String _noAdMessage =
      'No ad available. Check your connection and try again shortly.';

  void _onAdStateChanged(RewardedAdState state) {
    if (_awaitingAdRetry) {
      _awaitingAdRetry = false;
      if (state == RewardedAdState.ready) {
        _flashMessage('Ad ready.');
      } else if (state == RewardedAdState.unavailable) {
        _flashMessage(_noAdMessage);
      }
    }
    notifyListeners();
  }

  void _flashMessage(String message) {
    _adMessage = message;
    _adMessageTimer?.cancel();
    _adMessageTimer = Timer(const Duration(seconds: 4), () {
      _adMessage = null;
      notifyListeners();
    });
  }

  // ------------------------------------------------------------------ settings
  Future<void> setSoundEnabled(bool value) async {
    _audio.configure(sound: value, haptics: _audio.hapticsEnabled);
    notifyListeners();
    await _storage.saveSoundEnabled(value);
    if (value) unawaited(_audio.play(GameSound.select));
  }

  Future<void> setHapticsEnabled(bool value) async {
    _audio.configure(sound: _audio.soundEnabled, haptics: value);
    notifyListeners();
    await _storage.saveHapticsEnabled(value);
    if (value) unawaited(_audio.haptic(HapticLevel.selection));
  }

  bool get ageAcknowledged => _storage.ageAcknowledged;

  Future<void> acknowledgeAge() => _storage.setAgeAcknowledged(true);

  // -------------------------------------------------------------------- debug
  /// Tops the balance up. Exposed for balancing during development; also the
  /// escape hatch that keeps a player from ever being permanently stuck.
  @visibleForTesting
  void debugCredit(int coins) {
    _wallet.credit(coins);
    unawaited(_storage.saveBalance(_wallet.balance));
    notifyListeners();
  }
}
