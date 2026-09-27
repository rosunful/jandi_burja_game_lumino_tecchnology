import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import 'symbol_icon.dart';

/// Horizontal row of chip denominations. The selected chip is brass, the rest
/// recede so the current choice is always obvious at a glance.
class ChipSelector extends StatelessWidget {
  const ChipSelector({
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
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: AppConfig.chipDenominations.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final int value = AppConfig.chipDenominations[index];
          final bool active = value == selected;
          return Semantics(
            button: true,
            selected: active,
            label: '$value coin chip',
            child: Material(
              color: active ? GameColors.brass : GameColors.feltMid,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: enabled ? () => onSelect(value) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: active
                          ? GameColors.brass
                          : const Color(0x33FFFFFF),
                      width: active ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SymbolIcon.chip(
                        size: 20,
                        color: active ? GameColors.ink : GameColors.cream,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$value',
                        style: TextStyle(
                          color: active ? GameColors.ink : GameColors.cream,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
