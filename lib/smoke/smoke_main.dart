// Temporary verification entrypoint, used only during the step-2 risk
// checkpoint. Delete once the real app shell is in place.
//
// Build and run with:
//   flutter run -t lib/smoke/smoke_main.dart
//
// Its whole job is to prove the Google Mobile Ads SDK actually initialises,
// loads a rewarded ad, and reports a reward on a real Android device, rather
// than merely compiling.

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmokeApp());
}

class SmokeApp extends StatelessWidget {
  const SmokeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const SmokePage(),
    );
  }
}

class SmokePage extends StatefulWidget {
  const SmokePage({super.key});

  @override
  State<SmokePage> createState() => _SmokePageState();
}

class _SmokePageState extends State<SmokePage> {
  final List<String> _log = <String>[];
  RewardedAd? _ad;
  bool _loading = false;
  bool _showing = false;

  void _say(String message) {
    if (!mounted) return;
    setState(() => _log.add(message));
  }

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    _say('platform: ${defaultTargetPlatform.name}');
    _say('unit id: ${AppConfig.admobRewardedUnitId}');
    try {
      await MobileAds.instance.initialize();
      _say('MobileAds.initialize(): OK');
    } catch (e) {
      _say('MobileAds.initialize(): FAILED $e');
      return;
    }
    _load();
  }

  void _load() {
    setState(() => _loading = true);
    _say('--- requesting rewarded ad ---');
    RewardedAd.load(
      adUnitId: AppConfig.admobRewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          _loading = false;
          _ad = ad;
          _say('onAdLoaded: OK');
          ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
            onAdDismissedFullScreenContent: (RewardedAd ad) {
              _showing = false;
              _say('onAdDismissedFullScreenContent');
              ad.dispose();
              _ad = null;
              _load();
            },
            onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
              _showing = false;
              _say('onAdFailedToShow: ${error.code} ${error.message}');
              ad.dispose();
              _ad = null;
              _load();
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          _loading = false;
          _say('onAdFailedToLoad: code=${error.code} msg=${error.message}');
        },
      ),
    );
  }

  void _show() {
    final RewardedAd? ad = _ad;
    if (ad == null) return;
    setState(() => _showing = true);
    ad.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        _say('onUserEarnedReward: +${reward.amount} ${reward.type}');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AdMob smoke test')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                FilledButton(
                  onPressed: _loading || _showing || _ad == null ? null : _show,
                  child: const Text('Show test rewarded ad'),
                ),
                if (_loading) const CircularProgressIndicator(),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _log.length,
              itemBuilder: (BuildContext context, int i) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 3,
                ),
                child: Text('${i + 1}. ${_log[i]}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
