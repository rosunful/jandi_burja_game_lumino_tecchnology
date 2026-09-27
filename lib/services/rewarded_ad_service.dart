import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Lifecycle of the one rewarded ad we keep preloaded.
enum RewardedAdState {
  /// Still fetching the next ad.
  loading,

  /// Ready to show.
  ready,

  /// Showing right now.
  showing,

  /// Could not be loaded, most often because the device is offline. The game
  /// stays fully playable in this state; only the coin refill is unavailable.
  unavailable,
}

/// Abstraction over the ad network.
///
/// The game talks only to this interface, which is what keeps the rules and
/// the coin economy testable: `flutter test` runs on the Dart VM where the real
/// SDK does not exist, so the controller is given a [FakeRewardedAdService]
/// instead.
abstract class RewardedAdService {
  /// Current state, for enabling or disabling the watch-an-ad button.
  RewardedAdState get state;

  /// Registers a listener for state changes.
  ///
  /// Loading an ad is asynchronous and does not report back through
  /// [preload], so a caller that wants to tell the player "the ad you asked
  /// for is now ready" has no way to learn it without this. Set to null to
  /// unsubscribe.
  set onStateChanged(void Function(RewardedAdState state)? listener);

  /// Initialises the SDK. Safe to call more than once.
  Future<void> initialize();

  /// Warms the next ad so the button is usually ready when tapped.
  Future<void> preload();

  /// Shows the preloaded ad.
  ///
  /// [onReward] fires only when the user actually finishes watching, which is
  /// the AdMob contract: closing early earns nothing. Returns false if no ad
  /// was available, in which case [onReward] will not be called.
  Future<bool> show({required void Function(int coins) onReward});

  /// Releases platform resources.
  Future<void> dispose();
}

/// Production implementation backed by AdMob.
class AdMobRewardedAdService implements RewardedAdService {
  AdMobRewardedAdService({required this.adUnitId, this.onLog});

  final String adUnitId;
  final void Function(String message)? onLog;

  RewardedAd? _ad;
  RewardedAdState _state = RewardedAdState.loading;
  bool _initialised = false;
  bool _disposed = false;

  void Function(RewardedAdState state)? _onStateChanged;

  @override
  set onStateChanged(void Function(RewardedAdState state)? listener) =>
      _onStateChanged = listener;

  @override
  RewardedAdState get state => _state;

  /// Single funnel for state changes so a listener can never miss one.
  void _setState(RewardedAdState next) {
    if (_state == next) return;
    _state = next;
    _onStateChanged?.call(next);
  }

  void _log(String message) {
    onLog?.call(message);
    debugPrint('AdMob: $message');
  }

  @override
  Future<void> initialize() async {
    if (_initialised || _disposed) return;
    try {
      await MobileAds.instance.initialize();
      _initialised = true;
      _log('SDK initialised');
      await preload();
    } catch (error) {
      _setState(RewardedAdState.unavailable);
      _log('initialise failed: $error');
    }
  }

  @override
  Future<void> preload() async {
    if (_disposed) return;
    if (!_initialised) {
      _setState(RewardedAdState.unavailable);
      return;
    }

    _setState(RewardedAdState.loading);
    try {
      await RewardedAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) {
            if (_disposed) {
              ad.dispose();
              return;
            }
            _ad = ad;
            _setState(RewardedAdState.ready);
            _log('ad loaded and ready to show');

            ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
              onAdDismissedFullScreenContent: (RewardedAd finished) {
                _setState(RewardedAdState.loading);
                finished.dispose();
                _ad = null;
                // A rewarded ad can only be shown once, so immediately fetch
                // the next one to keep the button enabled.
                preload();
              },
              onAdFailedToShowFullScreenContent: (RewardedAd failed, AdError error) {
                _setState(RewardedAdState.unavailable);
                failed.dispose();
                _ad = null;
                _log('show failed: ${error.code} ${error.message}');
              },
            );
          },
          onAdFailedToLoad: (LoadAdError error) {
            _setState(RewardedAdState.unavailable);
            _log('load failed: code=${error.code} ${error.message}');
          },
        ),
      );
    } catch (error) {
      _setState(RewardedAdState.unavailable);
      _log('load threw: $error');
    }
  }

  @override
  Future<bool> show({required void Function(int coins) onReward}) async {
    final RewardedAd? ad = _ad;
    if (ad == null || _disposed) {
      _setState(RewardedAdState.unavailable);
      return false;
    }

    _setState(RewardedAdState.showing);
    try {
      await ad.show(
        onUserEarnedReward: (AdWithoutView _, RewardItem reward) {
          _log('reward earned: ${reward.amount} ${reward.type}');
          // RewardItem.amount is typed as num by the SDK; coins are whole.
          onReward(reward.amount.toInt());
        },
      );
      return true;
    } catch (error) {
      _setState(RewardedAdState.unavailable);
      _log('show threw: $error');
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _ad?.dispose();
    _ad = null;
  }
}

/// Test and offline stand-in.
///
/// Mirrors the real service's state machine without touching any platform
/// channel, so widget tests and the Dart-VM test runner behave predictably.
class FakeRewardedAdService implements RewardedAdService {
  FakeRewardedAdService({
    this.autoPreload = true,
    this.rewardAmount = 500,
    this.failToLoad = false,
  });

  /// When true the ad becomes ready as soon as [initialize] completes.
  final bool autoPreload;

  /// Coins handed out when an ad is watched to completion.
  final int rewardAmount;

  /// Simulates no network so the unavailable path can be exercised.
  ///
  /// Deliberately mutable so a test can start offline, then flip it to model
  /// the connection coming back when the player taps "try again".
  bool failToLoad;

  int showCount = 0;
  int rewardCount = 0;

  RewardedAdState _state = RewardedAdState.loading;

  void Function(RewardedAdState state)? _onStateChanged;

  @override
  set onStateChanged(void Function(RewardedAdState state)? listener) =>
      _onStateChanged = listener;

  @override
  RewardedAdState get state => _state;

  /// Single funnel for state changes so a listener can never miss one.
  void _setState(RewardedAdState next) {
    if (_state == next) return;
    _state = next;
    _onStateChanged?.call(next);
  }

  @override
  Future<void> initialize() async {
    _state = failToLoad
        ? RewardedAdState.unavailable
        : RewardedAdState.ready;
  }

  @override
  Future<void> preload() async {
    if (failToLoad) {
      _setState(RewardedAdState.unavailable);
    } else {
      _setState(RewardedAdState.ready);
    }
  }

  @override
  Future<bool> show({required void Function(int coins) onReward}) async {
    if (failToLoad) {
      _setState(RewardedAdState.unavailable);
      return false;
    }
    showCount++;
    _setState(RewardedAdState.ready);
    rewardCount++;
    onReward(rewardAmount);
    return true;
  }

  @override
  Future<void> dispose() async {}
}
