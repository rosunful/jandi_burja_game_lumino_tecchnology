import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/symbol.dart';
import 'symbol_icon.dart';

/// A single die. While [spinning] is true it tumbles through random symbols and
/// settles on [symbol].
///
/// [highlighted] draws a brass rim, used to point out the symbols the player
/// backed.
class DieFaceView extends StatelessWidget {
  const DieFaceView({
    super.key,
    required this.symbol,
    this.size = 52,
    this.spinning = false,
    this.highlighted = false,
  });

  final Symbol symbol;
  final double size;
  final bool spinning;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    if (spinning) {
      return _TumblingDie(
        key: ValueKey<int>(symbol.index),
        realFace: symbol,
        size: size,
        highlighted: highlighted,
      );
    }
    return _DieBody(
      symbol: symbol,
      size: size,
      highlighted: highlighted,
    );
  }
}

class _DieBody extends StatelessWidget {
  const _DieBody({
    required this.symbol,
    required this.size,
    required this.highlighted,
  });

  final Symbol symbol;
  final double size;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: GameColors.dieFace,
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(
          color: highlighted ? GameColors.brass : GameColors.dieEdge,
          width: highlighted ? 2.4 : 1.2,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: SymbolIcon(symbol, size: size * 0.6, color: GameColors.ink),
      ),
    );
  }
}

/// Cycles through random symbols for the duration of one round, then reveals
/// the real face.
///
/// This deliberately renders its own faces rather than swapping a prebuilt
/// child, otherwise the key changes but the artwork stays identical and the
/// dice appear frozen.
class _TumblingDie extends StatefulWidget {
  const _TumblingDie({
    super.key,
    required this.realFace,
    required this.size,
    required this.highlighted,
  });

  final Symbol realFace;
  final double size;
  final bool highlighted;

  @override
  State<_TumblingDie> createState() => _TumblingDieState();
}

class _TumblingDieState extends State<_TumblingDie>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final Random _random = Random();

  Symbol _shown = Symbol.crown;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _shown = widget.realFace;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 880),
    );
    _controller.forward();
    // ~55ms per face reads as a tumble rather than a strobe.
    _ticker = Timer.periodic(const Duration(milliseconds: 55), (_) {
      if (!mounted || !_controller.isAnimating) return;
      setState(
        () => _shown = Symbol.values[_random.nextInt(Symbol.values.length)],
      );
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool settled = _controller.isCompleted;
    return RotationTransition(
      turns: Tween<double>(begin: 0, end: 1.4).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      ),
      child: _DieBody(
        // Before settling, show tumbling faces; on the final frame snap to the
        // real one so the result is never ambiguous.
        symbol: settled ? widget.realFace : _shown,
        size: widget.size,
        highlighted: widget.highlighted,
      ),
    );
  }
}
