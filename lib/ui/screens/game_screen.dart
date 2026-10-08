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
  /// the system back button lands on the same clean state as PLAY AGAIN. It
  /// runs only when a round actually settled: a player who leaves before the
  /// dice have been dealt keeps the wagers they staged, because clearing them
  /// there would take coins off the table for a throw that never happened.
  Future<void> _throw(BuildContext context, {required bool throw3d}) async {
    if (!controller.canRoll) return;
    final int serial = controller.roundSerial;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            RollScreen(controller: controller, throw3d: throw3d),
      ),
    );
    if (!context.mounted) return;
    if (controller.roundSerial == serial) return;
    await controller.clearBoard();
  }

  /// The 2D throw.
  Future<void> _roll(BuildContext context) => _throw(context, throw3d: false);

  /// The real-money 3D throw: same round, dice that are actually three
  /// dimensional.
  Future<void> _roll3d(BuildContext context) =>
      _throw(context, throw3d: true);

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
                          // labels no longer fit side by side, and the row
                          // would squeeze the throw. The 3D throw is the one
                          // that gives up its label, because the throw is the
                          // control that has to be obvious.
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
                              _ThreeDThrowButton(
                                controller: c,
                                onRoll: () => _roll3d(context),
                                compact: compact,
                              ),
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

/// The real-money 3D throw, kept level with [RollButton] so the two ways to
/// roll are found in the same place.
///
/// It sits beside the roll rather than buried in the top bar because it is the
/// same round as the roll: it stages nothing of its own, it needs the same
/// wagers and it goes live at the same moment, so gating it on
/// [GameController.canRoll] rather than on a practice screen's "always open" is
/// what keeps the two buttons honest. The free throw lives in the top bar,
/// where nothing about it can be mistaken for a wager.
class _ThreeDThrowButton extends StatelessWidget {
  const _ThreeDThrowButton({
    required this.controller,
    required this.onRoll,
    this.compact = false,
  });

  final GameController controller;

  /// Pushes the throw, exactly as [RollButton.onRoll] does.
  final VoidCallback onRoll;

  /// Whether to drop the label and show the cube on its own.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ButtonStyle style = OutlinedButton.styleFrom(
      foregroundColor: GameColors.brass,
      side: BorderSide(color: GameColors.brass.withValues(alpha: 0.55)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
    );

    // Disabled alongside ROLL THE DICE, not on its own schedule: a 3D throw
    // with nothing staged would push a screen that has no round to run.
    final VoidCallback? throw3d = controller.canRoll ? onRoll : null;

    // The label is the only thing saying what this is, so it goes only when
    // there is genuinely no room for it. A tooltip is not a substitute for it
    // and is not pretending to be, it is what a short tap has instead.
    if (compact) {
      return Tooltip(
        message: 'Throw in 3D',
        child: OutlinedButton(
          onPressed: throw3d,
          style: style,
          child: const Icon(Icons.view_in_ar_outlined, size: 20),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: throw3d,
      icon: const Icon(Icons.view_in_ar_outlined, size: 20),
      label: const Text('3D DICE'),
      style: style,
    );
  }
}

/// The free throw, in the top bar where the practice table has always been
/// expected to be.
///
/// Labelled whenever there is room for the words and icon-only below that: at
/// 320px a permanent label would push the app title off the screen, and the
/// title is the one thing on this bar that cannot be reached from anywhere
/// else. [labelled] is decided by [_TopBar]'s own width, so the choice tracks
/// the phone rather than a hard-coded breakpoint somewhere else.
class _CustomDiceButton extends StatelessWidget {
  const _CustomDiceButton({required this.controller, required this.labelled});

  final GameController controller;

  final bool labelled;

  void _openPractice(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiceLabScreen(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!labelled) {
      return IconButton(
        tooltip: 'Custom 3D dice',
        icon: const Icon(Icons.threed_rotation),
        onPressed: () => _openPractice(context),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => _openPractice(context),
      icon: const Icon(Icons.threed_rotation, size: 18),
      label: const Text('CUSTOM 3D DICE'),
      style: OutlinedButton.styleFrom(
        foregroundColor: GameColors.brass,
        side: BorderSide(color: GameColors.brass.withValues(alpha: 0.55)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final GameController controller;

  /// Below this the label on [_CustomDiceButton] no longer fits beside the app
  /// title without pushing it into a second line or off a small phone, so the
  /// control drops to its icon.
  ///
  /// The title is given an ellipsis rather than being allowed to wrap, so
  /// whatever is left over is always one line and this threshold is the only
  /// thing deciding how the bar looks.
  static const double _labelledWidth = 480;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The free-throw control sits between the help icon and the title, so
        // the bar stays balanced: two controls left, two right, and the title
        // centred between them rather than drifting.
        final bool labelled = constraints.maxWidth >= _labelledWidth;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Rules',
                icon: const Icon(Icons.help_outline),
                onPressed: () => Navigator.of(
                  context,
                ).push(
                  MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
                ),
              ),
              _CustomDiceButton(controller: controller, labelled: labelled),
              const Expanded(
                child: Text(
                  AppConfig.appName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
      },
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
