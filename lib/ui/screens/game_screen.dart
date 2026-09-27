import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../logic/game_engine.dart';
import '../../models/bet.dart';
import '../../models/symbol.dart';
import '../../state/game_controller.dart';
import '../widgets/balance_bar.dart';
import '../widgets/betting_board.dart';
import '../widgets/chip_selector.dart';
import '../widgets/die_face_view.dart';
import '../widgets/symbol_icon.dart';
import 'help_screen.dart';
import 'stats_screen.dart';

/// The play surface: balance, dice, betting board, chips, quick actions.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(
      duration: const Duration(milliseconds: 1400),
    );
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _confetti.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final RoundResult? result = widget.controller.lastRound;
    if (result != null && result.won && result.netChange > 0) {
      _confetti.play();
    }
    setState(() {});
  }

  Set<Symbol> get _winningSymbols {
    final RoundResult? result = widget.controller.lastRound;
    if (result == null) return <Symbol>{};
    return <Symbol>{
      for (final BetResult r in result.results)
        if (r.won) r.bet.symbol,
    };
  }

  @override
  Widget build(BuildContext context) {
    final GameController c = widget.controller;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          const _FeltBackdrop(),
          SafeArea(
            child: Column(
              children: <Widget>[
                _TopBar(controller: c),
                Expanded(
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      final bool wide = constraints.maxWidth >= 620;
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _DiceRow(controller: c),
                              const SizedBox(height: 12),
                              if (c.lastRound != null)
                                _ResultPanel(
                                  controller: c,
                                  result: c.lastRound!,
                                )
                              else if (c.lastRejection != null)
                                _RejectionNotice(rejection: c.lastRejection!),
                              const SizedBox(height: 10),
                              BettingBoard(
                                controller: c,
                                bets: c.wallet.bets,
                                enabled: c.phase != RollPhase.rolling &&
                                    c.phase != RollPhase.settled,
                                winningSymbols: _winningSymbols,
                              ),
                              const SizedBox(height: 12),
                              _QuickActions(controller: c),
                              const SizedBox(height: 10),
                              ChipSelector(
                                selected: c.wallet.selectedChip,
                                enabled: c.phase != RollPhase.rolling,
                                onSelect: c.selectChip,
                              ),
                              const SizedBox(height: 12),
                              BalanceBar(controller: c),
                              if (wide) const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              numberOfParticles: 8,
              emissionFrequency: 0.05,
              gravity: 0.3,
              colors: const <Color>[
                GameColors.brass,
                GameColors.cream,
                GameColors.win,
              ],
            ),
          ),
          if (c.adMessage != null)
            Align(
              alignment: const Alignment(0, 0.75),
              child: _Toast(message: c.adMessage!),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Rules',
            icon: const Icon(Icons.help_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const HelpScreen(),
              ),
            ),
          ),
          const Expanded(
            child: Text(
              AppConfig.appName,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: GameColors.brass,
                fontSize: 19,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.5,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Statistics',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => StatsScreen(controller: controller),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The six dice. Before the first throw they sit face down so the board is the
/// only thing to look at.
class _DiceRow extends StatelessWidget {
  const _DiceRow({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final bool rolling = controller.phase == RollPhase.rolling;
    final List<Symbol> faces = controller.visibleFaces;
    final Set<Symbol> backed = controller.backedSymbols;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double dieSize = ((constraints.maxWidth - 5 * 8) / 6).clamp(38.0, 60.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (int i = 0; i < AppConfig.diceCount; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 8),
              if (faces.isEmpty)
                _FaceDownDie(size: dieSize)
              else
                DieFaceView(
                  key: ValueKey<int>(i),
                  symbol: faces[i],
                  size: dieSize,
                  // The controller already knows the outcome, so the tumble is
                  // guaranteed to land on the face that will be scored.
                  spinning: rolling,
                  highlighted: !rolling && backed.contains(faces[i]),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _FaceDownDie extends StatelessWidget {
  const _FaceDownDie({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: GameColors.feltMid,
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Center(
        child: SymbolIcon.chip(
          size: size * 0.4,
          color: const Color(0x55809089),
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.controller, required this.result});

  final GameController controller;
  final RoundResult result;

  @override
  Widget build(BuildContext context) {
    final bool won = result.won;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: (won ? GameColors.win : GameColors.lose).withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (won ? GameColors.win : GameColors.lose).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  won ? 'You won' : 'No payout',
                  style: TextStyle(
                    color: won ? GameColors.win : GameColors.lose,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${won ? '+' : ''}${result.netChange} coins',
                style: TextStyle(
                  color: won ? GameColors.win : GameColors.lose,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final BetResult r in result.results)
            BetResultTile(result: r),
          const SizedBox(height: 2),
          Text(
            'Tap CLEAR BOARD to bet again',
            style: TextStyle(
              color: GameColors.cream.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _RejectionNotice extends StatelessWidget {
  const _RejectionNotice({required this.rejection});

  final BetRejection rejection;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: GameColors.lose.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: GameColors.lose.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.error_outline,
            color: GameColors.lose,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              rejection.message,
              style: const TextStyle(color: GameColors.cream, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final bool busy =
        controller.phase == RollPhase.rolling ||
        controller.phase == RollPhase.settled;
    final bool broke = controller.isBroke;

    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy || !controller.wallet.hasBets
                ? null
                : controller.undoLastBet,
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('Undo'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy || !controller.canRepeatLast
                ? null
                : controller.repeatLastBet,
            icon: const Icon(Icons.replay, size: 18),
            label: const Text('Repeat'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : controller.clearBoard,
            icon: const Icon(Icons.backspace_outlined, size: 18),
            label: const Text('Clear'),
          ),
        ),
        if (broke) ...<Widget>[
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: controller.adRewardPending
                  ? null
                  : controller.watchRewardedAd,
              style: FilledButton.styleFrom(
                backgroundColor: GameColors.win,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(
                Icons.play_circle_outline,
                size: 18,
                color: GameColors.ink,
              ),
              label: Text(
                controller.adRewardPending ? 'Loading' : '+${AppConfig.coinsPerRewardedAd}',
                style: const TextStyle(color: GameColors.ink, fontSize: 13),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The felt table surface, stretched rather than tiled.
class _FeltBackdrop extends StatelessWidget {
  const _FeltBackdrop();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/felt/felt.png'),
          fit: BoxFit.cover,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xAA05170F),
            Color(0x3305170F),
            Color(0xCC05170F),
          ],
          stops: <double>[0, 0.45, 1],
        ),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 26),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xEE05170F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GameColors.brassDark),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.info_outline, color: GameColors.brass, size: 18),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                message,
                style: const TextStyle(color: GameColors.cream, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
