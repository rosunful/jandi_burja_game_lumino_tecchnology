import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../logic/payout_table.dart';
import '../../models/symbol.dart';
import '../widgets/symbol_icon.dart';

/// Rules, the payout table, and the age / no-real-money acknowledgements.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('How to play')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          const _Section(
            title: 'The idea',
            body:
                'Six dice are thrown, each showing one of six symbols. Put '
                'coins on any of the six symbols, then throw. You need two or '
                'more dice to show your chosen symbol to win.',
          ),
          _PayoutTableCard(),
          const _Section(
            title: 'Multiple bets',
            body:
                'You can back several symbols in the same throw. Each one is '
                'settled on its own, so two winning symbols will pay out even '
                'if a third loses.',
          ),
          const _Section(
            title: 'The symbols',
            body: 'Each symbol has both an English and a local name.',
          ),
          const Card(
            color: GameColors.feltMid,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: SymbolLegend(),
            ),
          ),
          _LimitsCard(),
          const _AgeAndValueNotice(),
          const _Disclaimer(),
        ],
      ),
    );
  }
}

class _PayoutTableCard extends StatelessWidget {
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
              'PAYOUTS',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Wins pay the number of matching dice times your bet.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            for (int k = 0; k <= AppConfig.diceCount; k++)
              _PayoutRow(matches: k),
            const Divider(height: 22),
            _FactRow(
              label: 'Return to player',
              value:
                  '${(PayoutTable.returnToPlayer * 100).toStringAsFixed(2)}%',
            ),
            _FactRow(
              label: 'House edge',
              value: '${(PayoutTable.houseEdge * 100).toStringAsFixed(2)}%',
            ),
            const SizedBox(height: 8),
            Text(
              'About one in six dice shows your chosen symbol, so a single '
              'match is common. That is why two matches are needed to win, and '
              'why a losing streak is a normal part of playing rather than a '
              'sign of anything wrong.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.matches});

  final int matches;

  @override
  Widget build(BuildContext context) {
    final int multiplier = PayoutTable.multiplierFor(matches);
    final bool winning = multiplier > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 26,
            child: Text(
              '$matches',
              style: TextStyle(
                color: winning ? GameColors.win : GameColors.lose,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Icon(
            winning ? Icons.check_circle : Icons.cancel,
            size: 15,
            color: winning ? GameColors.win : GameColors.lose,
          ),
          const SizedBox(width: 8),
          Text(
            matches == 0
                ? 'no matches'
                : '$matches matching ${matches == 1 ? 'die' : 'dice'}',
            style: const TextStyle(color: GameColors.cream, fontSize: 13),
          ),
          const Spacer(),
          Text(
            winning ? 'pays ${multiplier}x' : 'bet lost',
            style: TextStyle(
              color: winning ? GameColors.win : GameColors.lose,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _LimitsCard extends StatelessWidget {
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
            Text('LIMITS', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _FactRow(
              label: 'Smallest bet',
              value: '${AppConfig.minBet} coins',
            ),
            _FactRow(
              label: 'Largest bet, one symbol',
              value: '${AppConfig.maxBetPerSymbol} coins',
            ),
            _FactRow(
              label: 'Largest total, one throw',
              value: '${AppConfig.maxTotalBet} coins',
            ),
            _FactRow(
              label: 'Coins for a rewarded ad',
              value: '${AppConfig.coinsPerRewardedAd} coins',
            ),
          ],
        ),
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Text(
            value,
            style: const TextStyle(
              color: GameColors.cream,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AgeAndValueNotice extends StatelessWidget {
  const _AgeAndValueNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: GameColors.brassDark.withValues(alpha: 0.35),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.verified_user_outlined,
                    color: GameColors.brass, size: 18),
                SizedBox(width: 8),
                Text(
                  '18+  ·  Free to play  ·  No real money',
                  style: TextStyle(
                    color: GameColors.cream,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Janda Burja is a game of chance played with coins that exist '
              'only inside this app. There is no way to buy coins with money, '
              'and no way to cash out coins or prizes of any kind. Winning has '
              'no monetary value whatsoever.',
              style: TextStyle(color: GameColors.cream, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        'Coins are earned by watching short videos. Ads are provided by Google '
        'AdMob and require a network connection; the game itself works '
        'completely offline. Ads do not affect the fairness of the dice: every '
        'throw uses a cryptographically secure random source, and no outcome '
        'is influenced by whether an ad was watched.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Symbol key, so the local names are documented somewhere.
class SymbolLegend extends StatelessWidget {
  const SymbolLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (final Symbol s in Symbol.values)
          Row(
            children: <Widget>[
              SymbolIcon(s, size: 26, color: GameColors.cream),
              const SizedBox(width: 12),
              Text(
                s.label,
                style: const TextStyle(color: GameColors.cream),
              ),
              const Spacer(),
              Text(
                s.localName,
                style: const TextStyle(color: Color(0xFF9FB6AA)),
              ),
            ],
          ),
      ],
    );
  }
}
