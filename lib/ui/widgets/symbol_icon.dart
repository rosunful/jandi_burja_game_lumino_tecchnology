import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/symbol.dart';

/// Renders one of the bundled symbol SVGs, tinted to [color].
///
/// The SVGs are authored as a single white fill so one asset serves every
/// context: dark ink on a cream die face, cream on the green betting board, or
/// brass on a highlight. Tinting is a colour-matrix filter rather than a
/// second set of assets.
class SymbolIcon extends StatelessWidget {
  const SymbolIcon(
    this.symbol, {
    super.key,
    this.size = 32,
    this.color = const Color(0xFFFFFFFF),
  }) : _assetPath = null;

  /// Casino chip, used to show the value of a staged wager.
  const SymbolIcon.chip({
    super.key,
    this.size = 24,
    this.color = const Color(0xFFFFFFFF),
  }) : symbol = null,
       _assetPath = 'assets/symbols/chip.svg';

  /// Coin, used in the balance readout.
  const SymbolIcon.coin({
    super.key,
    this.size = 20,
    this.color = const Color(0xFFD4A94E),
  }) : symbol = null,
       _assetPath = 'assets/symbols/coin.svg';

  final Symbol? symbol;
  final double size;
  final Color color;
  final String? _assetPath;

  @override
  Widget build(BuildContext context) {
    final String path = _assetPath ?? 'assets/symbols/${symbol!.name}.svg';
    return SvgPicture.asset(
      path,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
