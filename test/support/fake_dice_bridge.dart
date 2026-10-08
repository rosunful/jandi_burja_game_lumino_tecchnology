import 'package:flutter/material.dart';
import 'package:janda_burja_game_app/models/symbol.dart';
import 'package:janda_burja_game_app/ui/screens/dice_lab_web.dart';

/// A [DiceThrowBridge] that keeps every promise the real one makes, without
/// opening a loopback server or asking a platform for a web view.
///
/// Neither exists under `flutter test`, so anything walking into a 3D throw
/// installs this instead. Every call is recorded so a test can read back what
/// Dart sent and whether the throw actually happened.
class FakeDiceThrowBridge implements DiceThrowBridge {
  /// What `waitForReady` reports. False is the "the page never arrived" case,
  /// which is what the 2D fallback hangs on.
  final bool ready;

  /// What `buildViewer` returned, so a test can assert the screen holds on to
  /// one widget instead of rebuilding the page on every frame.
  final Widget viewer = const SizedBox(key: Key('diceThrowViewer'));

  /// The faces handed to [land], in order, one entry per throw.
  final List<List<Symbol>> landed = <List<Symbol>>[];

  /// How many times [buildViewer] has run.
  int buildCount = 0;

  /// How many times [land] has run, including calls that timed out.
  int landCount = 0;

  FakeDiceThrowBridge({this.ready = true});

  @override
  Widget buildViewer() {
    buildCount++;
    return viewer;
  }

  @override
  Future<bool> waitForReady({Duration timeout = pageLoadTimeout}) async => ready;

  @override
  Future<void> land(
    List<Symbol> faces, {
    Duration timeout = landingTimeout,
  }) async {
    landCount++;
    landed.add(List<Symbol>.of(faces));
  }
}
