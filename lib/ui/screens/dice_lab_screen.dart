import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/audio_service.dart';
import '../../state/game_controller.dart';
import 'dice_lab_web.dart';

/// A practice table for the 3D dice. Free throws, no bets, nothing at stake.
///
/// The dice, the physics and this screen's chrome are all inside the web view:
/// [buildDiceLabViewer] hands a loopback-served HTML page to `model_viewer_plus`
/// and the throw runs as JavaScript at 240 hertz, off the Flutter UI thread
/// entirely. Flutter's job here is to host that page, to play the game's own
/// sounds when it throws, and to provide a way out - everything else is the
/// page's.
///
/// Deliberately not wired to [GameController]. Nothing here reads the wallet,
/// moves a chip or advances a round, and that is the whole point: a practice
/// mode that touched the balance would be the real mode with a different label
/// on it. The controller is taken for its sound service alone.
class DiceLabScreen extends StatefulWidget {
  const DiceLabScreen({super.key, required this.controller});

  /// Used only for audio. See the note above.
  final GameController controller;

  /// Test seam for the body of the screen.
  ///
  /// The real viewer opens a local HTTP server and a platform web view in its
  /// `initState`, and neither exists under `flutter test`, where no plugin is
  /// registered. It also parks a spinner on screen until both are ready, which
  /// would never settle. So tests install this and get a plain placeholder;
  /// leaving it null is what a device sees.
  @visibleForTesting
  static Widget Function()? viewerOverride;

  @override
  State<DiceLabScreen> createState() => _DiceLabScreenState();
}

class _DiceLabScreenState extends State<DiceLabScreen> {
  /// The dice-roll sound, held back until the throw sounds like it should.
  ///
  /// One timer rather than a chained pair per throw: tapping quickly must not
  /// leave three roll sounds landing after a single rattle.
  Timer? _rollSound;

  @override
  void dispose() {
    _rollSound?.cancel();
    super.dispose();
  }

  /// Pops the route. Called from the back arrow inside the page's app bar.
  void _goBack() {
    if (mounted) Navigator.of(context).maybePop();
  }

  /// Called from the page the moment the dice leave the cup.
  void _onThrow() {
    if (!mounted) return;
    _rollSound?.cancel();
    unawaited(widget.controller.audio.play(GameSound.diceRattle));
    unawaited(widget.controller.audio.haptic(HapticLevel.medium));
    // Slightly longer than the dice take to leave the hand, so the landing
    // sound arrives as they hit the felt rather than as they are released.
    _rollSound = Timer(const Duration(milliseconds: 950), () {
      if (!mounted) return;
      unawaited(widget.controller.audio.play(GameSound.diceRoll));
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget viewer =
        DiceLabScreen.viewerOverride?.call() ??
        buildDiceLabViewer(onBack: _goBack, onThrow: _onThrow);

    return Scaffold(
      // Matches the page's own app bar, so the web view never flashes white
      // behind its chrome while the loopback server is starting.
      backgroundColor: const Color(0xFF14501A),
      body: SafeArea(
        // The page draws its own bar and positions its dice against the top of
        // the window, so only the bottom is left alone.
        bottom: false,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: viewer),
            const IgnorePointer(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: _NoWagerNote(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one line that keeps this screen honest.
///
/// The launch disclosure is about the game as a whole, and this screen is a
/// separate thing a player walks into on purpose. Saying out loud that nothing
/// here is staked costs one line and removes any doubt about what a practice
/// throw is doing to the balance - which matters more here than it used to,
/// because the page behind it looks like a game with a roll counter in it.
class _NoWagerNote extends StatelessWidget {
  const _NoWagerNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Practice only. No coins are staked and nothing is won or lost.',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: GameColors.cream.withValues(alpha: 0.6),
        fontSize: 12,
      ),
    );
  }
}
