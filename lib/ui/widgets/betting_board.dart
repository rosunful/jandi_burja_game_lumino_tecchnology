import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../models/bet.dart';
import '../../models/symbol.dart';
import '../../state/game_controller.dart';
import 'symbol_icon.dart';

/// The six-symbol betting grid.
///
/// Tapping a cell stages one chip; the small minus button on a funded cell
/// removes one, so a bet can be built up and wound back without leaving the
/// board. Long-pressing adds half, which is the quickest route to a big stack.
class BettingBoard extends StatelessWidget {
  const BettingBoard({
    super.key,
    required this.controller,
    required this.bets,
    required this.enabled,
    required this.winningSymbols,
  });

  final GameController controller;

  /// Currently staged wagers, so the board can be a pure function of state.
  final Map<Symbol, int> bets;

  /// False while the dice are moving or a result is awaiting acknowledgement.
  final bool enabled;

  /// Symbols that paid out this round, highlighted with a brass rim.
  final Set<Symbol> winningSymbols;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Three columns on a phone in portrait, six across when there is room
        // for it, so the same widget serves both orientations.
        final int columns = constraints.maxWidth >= 560 ? 6 : 3;
        const double gap = 8;
        final double cellWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final Symbol symbol in Symbol.values)
              SizedBox(
                width: cellWidth,
                child: _BetCell(
                  symbol: symbol,
                  amount: bets[symbol] ?? 0,
                  enabled: enabled,
                  winning: winningSymbols.contains(symbol),
                  onAdd: () => controller.addBet(symbol),
                  onRemove: () => controller.removeBet(symbol),
                  onAddHalf: () => controller.addHalf(symbol),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BetCell extends StatelessWidget {
  const _BetCell({
    required this.symbol,
    required this.amount,
    required this.enabled,
    required this.winning,
    required this.onAdd,
    required this.onRemove,
    required this.onAddHalf,
  });

  final Symbol symbol;
  final int amount;
  final bool enabled;
  final bool winning;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onAddHalf;

  bool get _funded => amount > 0;

  @override
  Widget build(BuildContext context) {
    final Color border = winning
        ? GameColors.win
        : _funded
        ? GameColors.brass
        : const Color(0x33FFFFFF);

    return Semantics(
      button: true,
      label: '${symbol.label} bet',
      value: _funded ? '$amount coins' : 'no bet',
      child: Material(
        color: _funded
            ? GameColors.feltLight.withValues(alpha: 0.55)
            : GameColors.feltMid,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onAdd : null,
          onLongPress: _funded && enabled ? onAddHalf : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border, width: _funded ? 2 : 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Long-press doubles a wager, so the shortcut is discoverable.
                if (_funded && enabled)
                  Align(
                    alignment: Alignment.topRight,
                    child: InkResponse(
                      onTap: onRemove,
                      radius: 16,
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.remove_circle_outline,
                          size: 18,
                          color: GameColors.cream,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 2),
                SymbolIcon(symbol, size: 38, color: GameColors.cream),
                const SizedBox(height: 4),
                Text(
                  symbol.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: GameColors.cream,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  symbol.localName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF9FB6AA),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 4),
                _StakeChip(amount: amount),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The wager sitting on a cell: a chip icon with the amount, or a dimmed
/// minimum-bet hint so the player can see what a tap would cost.
class _StakeChip extends StatelessWidget {
  const _StakeChip({required this.amount});

  final int amount;

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) {
      return Text(
        'min ${AppConfig.minBet}',
        style: const TextStyle(color: Color(0x7799AFA3), fontSize: 10),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: GameColors.brass,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SymbolIcon.chip(size: 13, color: GameColors.ink),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              '$amount',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: GameColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only summary of how a single wager settled, shown in the result sheet.
class BetResultTile extends StatelessWidget {
  const BetResultTile({super.key, required this.result});

  final BetResult result;

  @override
  Widget build(BuildContext context) {
    final bool won = result.won;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          SymbolIcon(
            result.bet.symbol,
            size: 24,
            color: won ? GameColors.cream : const Color(0xFF7E8F86),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${result.matches} of ${AppConfig.diceCount} matched',
              style: const TextStyle(color: GameColors.cream, fontSize: 14),
            ),
          ),
          Text(
            '${won ? '+' : ''}${result.profit}',
            style: TextStyle(
              color: won ? GameColors.win : GameColors.lose,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
