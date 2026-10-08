import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../state/game_controller.dart';
import 'symbol_icon.dart';

/// What the player owns, and where more of it comes from.
/// The balance is the number a player looks at most often, so it gets the card
/// to itself on the left at a size that can be read across a table, with the
/// coin refill on the right where it is visible long before the balance runs
/// out. The out-of-coins explanation lives here too, because it explains that
/// button.
/// Deliberately plain English. "Your coins" is how a child would say it;
/// "balance" is how a spreadsheet would say it.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.controller});

  final GameController controller;
  @override
  Widget build(BuildContext context) {
    final int balance = controller.wallet.balance;
    // Worth flagging: at this point the player cannot place any wager and needs
    // an ad to continue, so the whole card tightens up around that fact.
    final bool broke = controller.isBroke;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      decoration: BoxDecoration(
        color: GameColors.feltMid,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: broke ? GameColors.brassDark : const Color(0x22FFFFFF),
          width: broke ? 2 : 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _Balance(value: _grouped(balance), broke: broke),
          ),
          const SizedBox(width: 10),
          _AdButton(controller: controller),
        ],
      ),
    );
  }
}

/// Thousands separators, so a five-figure balance is countable at a glance.
///
/// Hand-rolled rather than pulled from `intl`: this is the only place in the
/// app that formats a number, and one pass over the digits is cheaper than a
/// dependency that would be used once.
String _grouped(int value) {
  final String digits = value.toString();
  final StringBuffer out = StringBuffer();
  // Count from the right so the separator lands in the same place regardless of
  // how many digits there are.
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// The primary action, pinned to the bottom of the betting screen.
///
/// It is the one control that matters most, so it stays outside the scroll view
/// on a phone that cannot fit it and the board at once.
class RollButton extends StatelessWidget {
  const RollButton({super.key, required this.controller, required this.onRoll});

  final GameController controller;
  final VoidCallback onRoll;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: controller.canRoll ? onRoll : null,
        style: FilledButton.styleFrom(
          backgroundColor: GameColors.brass,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: const Text(
          'ROLL THE DICE',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

/// The status line under the hero card: what is staked, or why nothing is.
///
/// No card and no background: it is one line of status, not a second place to
/// look for something. It is also where the out-of-coins explanation lives.
/// That message used to be a banner inside the hero card, which meant a third
/// block competing with the balance, and on a 320 pixel phone it pushed the
/// quick actions off the bottom. One line, reused, beats a banner.
class BetAmount extends StatelessWidget {
  const BetAmount({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    // Out of coins, "you are betting" is a question with no answer: the player
    // cannot place a wager at all, so the line says the useful thing instead.
    if (controller.isBroke) return const _OutOfCoins();

    final int bet = controller.wallet.totalBet;

    // Centred, with the amount on its own line under the label, so the number
    // the player came to read is the middle of the screen rather than something
    // they have to find at the end of a row. Nothing is shown below the label
    // until there is something to show: an empty line reading zero is a worse
    // answer than no line at all.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'You are betting',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF9FB6AA),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        if (bet > 0) ...<Widget>[
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SymbolIcon.chip(size: 18, color: GameColors.brass),
              const SizedBox(width: 5),
              Text(
                _grouped(bet),
                style: const TextStyle(
                  color: GameColors.brass,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Tells a player with nothing left where more comes from.
///
/// Without this they see a brass number and a button labelled with a figure,
/// and no reason to connect the two. The amount is left out because the button
/// directly above it is already labelled with it.
class _OutOfCoins extends StatelessWidget {
  const _OutOfCoins();

  @override
  Widget build(BuildContext context) {
    // Centred like the staked amount it stands in for, so a player who runs out
    // mid-session does not see the line jump to one side.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.info_outline, color: GameColors.brass, size: 15),
        const SizedBox(width: 6),
        const Flexible(
          child: Text(
            'No coins left — watch an ad for more',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: GameColors.brass,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.value, required this.broke});

  final String value;
  final bool broke;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'Your coins',
          style: TextStyle(
            color: Color(0xFF9FB6AA),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 1),
        Row(
          children: <Widget>[
            const SymbolIcon.coin(size: 24),
            const SizedBox(width: 6),
            // Scales the number down rather than clipping it. A balance is the
            // one thing on this card that must never lose a digit, so it gives
            // up size instead, and only once the row genuinely runs out of room.
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    // Brass and only brass when the balance can no longer fund
                    // the smallest wager, so the number that needs attention is
                    // the one that changes colour.
                    color: broke ? GameColors.brass : GameColors.cream,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The coin refill, always on screen.
///
/// It used to appear only once the player was already broke, which meant the
/// first time a child saw it was the first time they needed it. It sits here
/// permanently and simply stops being the thing that needs explaining.
class _AdButton extends StatelessWidget {
  const _AdButton({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final bool pending = controller.adRewardPending;

    return FilledButton.icon(
      onPressed: pending ? null : controller.watchRewardedAd,
      style: FilledButton.styleFrom(
        backgroundColor: GameColors.win,
        // Sized to match the balance block beside it rather than outgrow it.
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      ),
      icon: Icon(
        pending ? Icons.hourglass_top : Icons.play_circle_outline,
        size: 18,
        color: GameColors.ink,
      ),
      // Stacked rather than on one line: "Watch ad +500" side by side is wider
      // than the balance has room to give it on a 320 pixel phone, and the
      // reward figure is the part that has to stay legible.
      label: pending
          ? const Text(
              'Loading',
              style: TextStyle(
                color: GameColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Watch ad',
                  style: TextStyle(
                    color: GameColors.ink,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                Text(
                  '+${AppConfig.coinsPerRewardedAd}',
                  style: const TextStyle(
                    color: GameColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
              ],
            ),
    );
  }
}
