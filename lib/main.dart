import 'package:flutter/material.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'services/rewarded_ad_service.dart';
import 'services/storage_service.dart';
import 'state/game_controller.dart';
import 'ui/screens/disclosure_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Storage first, because the controller reads the saved balance in its
  // constructor. A storage failure must not stop the game from starting, so it
  // degrades to an in-memory session rather than a crash.
  final StorageService storage;
  try {
    storage = await StorageService.open();
  } catch (error) {
    debugPrint('Could not open storage, running without persistence: $error');
    return runApp(const BootstrapErrorApp());
  }

  final GameController controller = GameController(
    storage: storage,
    ads: AdMobRewardedAdService(
      adUnitId: AppConfig.admobRewardedUnitId,
      onLog: (String message) {
        if (AppConfig.usingTestAdIds) {
          debugPrint('[test ads] $message');
        } else {
          debugPrint('[ads] $message');
        }
      },
    ),
  );

  await controller.initialise();
  runApp(JandaBurjaApp(controller: controller));
}

class JandaBurjaApp extends StatelessWidget {
  const JandaBurjaApp({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: GameTheme.build(),
      home: DisclosureGate(controller: controller),
    );
  }
}

/// Shown only if the device refuses to give us storage at all.
class BootstrapErrorApp extends StatelessWidget {
  const BootstrapErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: GameTheme.build(),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'Janda Burja could not start on this device.\n\n'
              'Please restart the app.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
