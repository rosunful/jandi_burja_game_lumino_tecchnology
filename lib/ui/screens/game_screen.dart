import 'package:flutter/material.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../logic/game_engine.dart';
import '../../services/rewarded_ad_service.dart';
import '../../state/game_controller.dart';
import '../widgets/betting_board.dart';
import '../widgets/coin_picker.dart';
import '../widgets/felt_backdrop.dart';
import '../widgets/hero_card.dart';
import 'dice_lab_screen.dart';
import 'help_screen.dart';
import 'roll_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

/// The betting table: quick actions, balance, the six symbols, and the throw.
/// Deliberately contains no dice. The throw happens on its own screen, so this
/// one is only ever about deciding where the coins go.
class GameScreen extends StatelessWidget {
  const GameScreen({super.key, required this.controller});

  final GameController controller;

  /// Hands the throw to [RollScreen] and, on the way back, guarantees a clean
  /// board.
  ///
  /// The reset happens here rather than on the roll screen's own button so that
  /// the system back button lands on the same clean state as PLAY AGAIN.
  Future<void> _roll(BuildContext context) async {
    if (!controller.canRoll) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RollScreen(controller: controller),
      ),
    );
    if (!context.mounted) return;
    await controller.clearBoard();
  }

  @override
  Widget build(BuildContext context) {
    // The controller is the source of truth and a ChangeNotifier, so the whole
    // table rebuilds from it rather than from local state.
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) => _buildTable(context),
    );
  }

  Widget _buildTable(BuildContext context) {
    final GameController c = controller;
    // Locked only while the dice are moving or a result is unacknowledged.
    // Treating "not idle" as locked would disable the board, the chips and the
    // quick actions the instant a single bet was staged.
    final bool locked =
        c.phase == RollPhase.rolling || c.phase == RollPhase.settled;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          const FeltBackdrop(),
          SafeArea(
            child: Column(
              children: <Widget>[
                _TopBar(controller: c),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            HeroCard(controller: c),
                            const SizedBox(height: 6),
                            BetAmount(controller: c),
                            if (c.lastRejection != null) ...<Widget>[
                              const SizedBox(height: 6),
                              _RejectionNotice(rejection: c.lastRejection!),
                            ],
                            const SizedBox(height: 6),
                            BettingBoard(
                              controller: c,
                              bets: c.wallet.bets,
                              enabled: !locked,
                            ),
                            const SizedBox(height: 6),
                            CoinPicker(
                              selected: c.wallet.selectedChip,
                              enabled: !locked,
                              onSelect: c.selectChip,
                            ),
                            const SizedBox(height: 6),
                            // Under the coins rather than above the board, so
                            // the order on screen runs the way the round does:
                            // pick a coin, place it, fix a mistake.
                            _QuickActions(controller: c),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Pinned outside the scroll view: the one control that matters
                // most must stay reachable on a small phone without scrolling.
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints constraints) {
                          // Below about a third of a normal phone's width the
                          // two labels no longer fit side by side, and the row
                          // would squeeze the throw. The practice button is the
                          // one that gives up its label, because the throw is
                          // the control that has to be obvious.
                          final bool compact = constraints.maxWidth < 340;
                          return Row(
                            children: <Widget>[
                              Expanded(
                                child: RollButton(
                                  controller: c,
                                  onRoll: () => _roll(context),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _DiceLabButton(controller: c, compact: compact),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (c.adMessage != null)
            Align(
              alignment: const Alignment(0, 0.75),
              child: _Toast(
                message: c.adMessage!,
                onRetry: c.adState == RewardedAdState.ready
                    ? null
                    : () => c.retryAd(),
              ),
            ),
        ],
      ),
    );
  }
}

/// The way into the practice table, kept level with [RollButton] so the throw
/// and the place to practise throws are found in the same place.
///
/// Beside the roll rather than buried in the top bar on purpose. This is the one
/// thing on the screen a player cannot do by accident, and it is the one thing
/// that is easier to understand once you have seen a real throw, so it wants to
/// be somewhere that is read rather than hunted for.
class _DiceLabButton extends StatelessWidget {
  const _DiceLabButton({required this.controller, this.compact = false});

  final GameController controller;

  /// Whether to drop the label and show the cube on its own.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    void open() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiceLabScreen(controller: controller),
      ),
    );

    final ButtonStyle style = OutlinedButton.styleFrom(
      foregroundColor: GameColors.brass,
      side: BorderSide(color: GameColors.brass.withValues(alpha: 0.55)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
    );

    // The label is the only thing saying what this is, so it goes only when
    // there is genuinely no room for it. A tooltip is not a substitute for it
    // and is not pretending to be, it is what a short tap has instead.
    if (compact) {
      return Tooltip(
        message: 'Dice practice',
        child: OutlinedButton(
          onPressed: open,
          style: style,
          child: const Icon(Icons.view_in_ar_outlined, size: 20),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: open,
      icon: const Icon(Icons.view_in_ar_outlined, size: 20),
      label: const Text('3D DICE'),
      style: style,
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
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen())),
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
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(controller: controller),
              ),
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
        border: Border.all(color: GameColors.lose.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline, color: GameColors.lose, size: 18),
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

/// Undo, repeat and clear, sitting above the board.
///
/// The ad refill used to be a fourth button here, squeezed in only when the
/// player was already broke. It now lives in the hero card, where there is room
/// to explain it.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final bool busy =
        controller.phase == RollPhase.rolling ||
        controller.phase == RollPhase.settled;

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
      ],
    );
  }
}

/// Transient message bar, with a retry that only appears when there is
/// something to retry.
class _Toast extends StatelessWidget {
  const _Toast({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
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
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: GameColors.brass,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Try again'),
              ),
          ],
        ),
      ),
    );
  }
}
