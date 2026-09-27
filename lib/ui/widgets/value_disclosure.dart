import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// The 18+ / no-real-money disclosure.
///
/// Lives here rather than inline in a screen because it is legally load-bearing
/// copy: the first-run gate and the rules screen must say the same thing, and
/// two copies of a disclaimer are two copies that eventually disagree.
///
/// [framed] picks the presentation: a felt card on the rules screen, plain text
/// inside the first-run dialog.
class ValueDisclosure extends StatelessWidget {
  const ValueDisclosure({super.key, this.framed = true});

  final bool framed;

  static const String heading = '18+  ·  Free to play  ·  No real money';

  static const String body =
      'Janda Burja is a game of chance played with coins that exist only '
      'inside this app. There is no way to buy coins with money, and no way '
      'to cash out coins or prizes of any kind. Winning has no monetary '
      'value whatsoever.';

  @override
  Widget build(BuildContext context) {
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(
              Icons.verified_user_outlined,
              color: GameColors.brass,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                heading,
                style: const TextStyle(
                  color: GameColors.cream,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          body,
          style: TextStyle(color: GameColors.cream, fontSize: 13, height: 1.4),
        ),
      ],
    );

    if (!framed) return content;

    return Card(
      color: GameColors.brassDark.withValues(alpha: 0.35),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(padding: const EdgeInsets.all(14), child: content),
    );
  }
}
