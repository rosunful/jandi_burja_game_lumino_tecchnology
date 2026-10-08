import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../services/rewarded_ad_service.dart';
import '../../state/game_controller.dart';
import '../widgets/value_disclosure.dart';
import 'help_screen.dart';

/// Sound, haptics, ad status, and the legal disclosure in one place.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    // Pushed as its own route, so nothing above it is listening to the
    // controller. Without this the switches would keep showing the position
    // they were pushed with, even though the model behind them had moved.
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              _Card(
                title: 'Sound and feel',
                children: <Widget>[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: controller.soundEnabled,
                    onChanged: controller.setSoundEnabled,
                    title: const Text('Sound effects'),
                    subtitle: const Text('Chips, dice and wins'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: controller.hapticsEnabled,
                    onChanged: controller.setHapticsEnabled,
                    title: const Text('Vibration'),
                    subtitle: const Text('A pulse on each chip and throw'),
                  ),
                ],
              ),
              _AdCard(controller: controller),
              const ValueDisclosure(),
              _Card(
                title: 'About',
                children: <Widget>[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('How to play'),
                    subtitle: const Text('Rules, payouts and odds'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HelpScreen(),
                      ),
                    ),
                  ),
                  if (AppConfig.usingTestAdIds)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'This build serves Google\'s test ads and earns '
                        'nothing. Replace the ad unit id before publishing.',
                        style: TextStyle(
                          color: GameColors.lose,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Ad availability, with the retry that used to have no way to be triggered.
class _AdCard extends StatelessWidget {
  const _AdCard({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final RewardedAdState state = controller.adState;
    final bool busy =
        state == RewardedAdState.loading || controller.adRewardPending;

    final String description = switch (state) {
      RewardedAdState.loading => 'Looking for an ad…',
      RewardedAdState.ready =>
        'Ready to watch for ${AppConfig.coinsPerRewardedAd} coins',
      RewardedAdState.showing => 'Playing…',
      RewardedAdState.unavailable =>
        'No ad available right now. The game still works; you need coins to '
            'keep betting.',
    };

    return _Card(
      title: 'Rewarded ads',
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              switch (state) {
                RewardedAdState.ready => Icons.check_circle,
                RewardedAdState.showing => Icons.play_circle,
                RewardedAdState.loading => Icons.hourglass_top,
                RewardedAdState.unavailable => Icons.cloud_off,
              },
              color: state == RewardedAdState.unavailable
                  ? GameColors.lose
                  : GameColors.win,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                description,
                style: const TextStyle(color: GameColors.cream, fontSize: 13),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: busy ? null : controller.retryAd,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try again'),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: GameColors.feltMid,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}
