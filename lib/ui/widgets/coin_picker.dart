import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import 'symbol_icon.dart';

/// The coin denominations, as a grid.
///
/// A horizontal scroller was the wrong shape for five values: the player had to
/// discover that there were more off-screen, and the one they wanted was as often
/// as not the one they could not see. Every denomination now fits on screen at
/// once, with the selected chip filled brass so the current choice reads without
/// having to be told.
class CoinPicker extends StatelessWidget {
  const CoinPicker({
    super.key,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final int selected;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Five across at any width. The widest value is four digits, which
        // still fits the narrowest phone this app supports, so there is no
        // breakpoint to reason about and nothing to scroll.
        const double gap = 8;
        final int count = AppConfig.chipDenominations.length;
        final double cellWidth =
            (constraints.maxWidth - gap * (count - 1)) / count;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final int value in AppConfig.chipDenominations)
              SizedBox(
                width: cellWidth,
                child: _Coin(
                  value: value,
                  active: value == selected,
                  enabled: enabled,
                  onTap: () => onSelect(value),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Coin extends StatelessWidget {
  const _Coin({
    required this.value,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final int value;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = active ? GameColors.ink : GameColors.cream;

    return Semantics(
      button: true,
      selected: active,
      label: '$value coin',
      child: Material(
        color: active ? GameColors.brass : GameColors.feltMid,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active ? GameColors.brass : const Color(0x33FFFFFF),
                width: active ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SymbolIcon.chip(size: 16, color: foreground),
                const SizedBox(height: 1),
                Text(
                  '$value',
                  maxLines: 1,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
