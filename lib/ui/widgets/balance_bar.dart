import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../state/game_controller.dart';
import 'symbol_icon.dart';

/// Coin balance, staged stake, and the roll button.
///
/// Shows the staged stake separately from the balance because a player about to
/// commit coins should always be able to see what the throw will cost.
class BalanceBar extends StatelessWidget {
  const BalanceBar({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final int balance = controller.wallet.balance;
    final int staged = controller.wallet.totalBet;
    final bool rolling = controller.phase == RollPhase.rolling;
    final bool settled = controller.phase == RollPhase.settled;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: GameColors.feltMid,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const SymbolIcon.coin(size: 26),
              const SizedBox(width: 8),
              _Metric(
                label: 'Balance',
                value: '$balance',
                emphasis: balance < AppConfig.minBet,
              ),
              const SizedBox(width: 18),
              _Metric(
                label: 'This throw',
                value: staged == 0 ? '-' : '$staged',
                emphasis: staged > 0,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: settled
                  ? () => controller.clearBoard()
                  : (controller.canRoll && !rolling ? controller.roll : null),
              style: FilledButton.styleFrom(
                backgroundColor: settled ? GameColors.cream : GameColors.brass,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: rolling
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: GameColors.ink,
                      ),
                    )
                  : Text(settled ? 'CLEAR BOARD' : 'ROLL THE DICE'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(color: Color(0xFF9FB6AA), fontSize: 11),
        ),
        Text(
          value,
          style: TextStyle(
            color: emphasis ? GameColors.brass : GameColors.cream,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
