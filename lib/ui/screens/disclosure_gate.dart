import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../state/game_controller.dart';
import '../widgets/value_disclosure.dart';
import 'game_screen.dart';

/// Blocks the game behind a one-time disclosure on first launch.
///
/// The dialog is deliberately not dismissible: the point is that a player has
/// read that there is no real money before they can wager coins, so it waits on
/// an explicit acknowledgement rather than a tap anywhere. The acknowledgement
/// is persisted, so this runs exactly once per install.
class DisclosureGate extends StatefulWidget {
  const DisclosureGate({super.key, required this.controller});

  final GameController controller;

  @override
  State<DisclosureGate> createState() => _DisclosureGateState();
}

class _DisclosureGateState extends State<DisclosureGate> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.ageAcknowledged) return;
    // Post-frame, so the dialog is pushed against a mounted navigator rather
    // than during the initial build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  Future<void> _show() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => const _DisclosureDialog(),
    );
    if (!mounted) return;
    await widget.controller.acknowledgeAge();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: GameScreen(controller: widget.controller),
    );
  }
}

class _DisclosureDialog extends StatelessWidget {
  const _DisclosureDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: GameColors.feltMid,
        title: const Text(
          'Before you play',
          style: TextStyle(color: GameColors.brass),
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Janda Burja is a game of chance. It is played with coins that '
                'have no monetary value and cannot be bought or cashed out.',
                style: TextStyle(color: GameColors.cream, height: 1.4),
              ),
              SizedBox(height: 16),
              ValueDisclosure(framed: false),
            ],
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: GameColors.brass,
              foregroundColor: GameColors.ink,
            ),
            child: const Text('I UNDERSTAND'),
          ),
        ],
      ),
    );
  }
}
