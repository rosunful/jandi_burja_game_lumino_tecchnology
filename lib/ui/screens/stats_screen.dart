import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../logic/payout_table.dart';
import '../../models/stats.dart';
import '../../state/game_controller.dart';

/// Lifetime statistics, including the player's own observed return so the
/// published house edge can be compared against their own history.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final GameStats s = controller.stats;

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          if (s.roundsPlayed == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'No rounds played yet.\nPlace a bet and throw the dice.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: GameColors.cream),
                ),
              ),
            )
          else ...<Widget>[
            _StatCard(
              title: 'Play',
              rows: <_Row>[
                _Row('Rounds played', '${s.roundsPlayed}'),
                _Row('Rounds won', '${s.roundsWon}'),
                _Row(
                  'Win rate',
                  s.winRate == null
                      ? '-'
                      : '${(s.winRate! * 100).toStringAsFixed(1)}%',
                ),
                _Row('Biggest win', '${s.biggestWin} coins'),
                _Row('Biggest loss', '${s.biggestLoss} coins'),
              ],
            ),
            _StatCard(
              title: 'Coins',
              rows: <_Row>[
                _Row('Total wagered', '${s.coinsWagered}'),
                _Row('Total returned', '${s.coinsReturned}'),
                _Row('Net from play', '${s.netFromPlay}'),
                _Row(
                  'Coins from ads',
                  '${s.coinsFromAds} (${s.adsWatched} ads)',
                ),
              ],
            ),
            _StatCard(
              title: 'Your odds',
              rows: <_Row>[
                _Row(
                  'Your return to player',
                  s.observedRtp == null
                      ? '-'
                      : '${(s.observedRtp! * 100).toStringAsFixed(2)}%',
                ),
                _Row(
                  'Published return',
                  '${(PayoutTable.returnToPlayer * 100).toStringAsFixed(2)}%',
                ),
              ],
              footer:
                  'Your figure is your own history and will swing around the '
                  'published one, especially over a small number of rounds. '
                  'Over many rounds the two converge.',
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.rows, this.footer});

  final String title;
  final List<_Row> rows;
  final String? footer;

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
            const SizedBox(height: 8),
            for (final _Row row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        row.label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      row.value,
                      style: const TextStyle(
                        color: GameColors.cream,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            if (footer != null) ...<Widget>[
              const Divider(height: 20),
              Text(footer!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row {
  const _Row(this.label, this.value);

  final String label;
  final String value;
}
