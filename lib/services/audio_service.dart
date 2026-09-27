import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Every sound the game can make.
enum GameSound {
  chipPlace('audio/chip_place.wav'),
  select('audio/select.wav'),
  diceRattle('audio/dice_rattle.wav'),
  diceRoll('audio/dice_roll.wav'),
  win('audio/win.wav'),
  winBig('audio/win_big.wav'),
  lose('audio/lose.wav');

  const GameSound(this.assetPath);

  final String assetPath;
}

/// Plays the bundled offline sound effects and fires haptic pulses.
///
/// Playback is fire-and-forget: a failure to play a sound must never interrupt
/// gameplay, so every call is wrapped and swallowed. The game is designed to be
/// fully playable muted.
class AudioService {
  AudioService({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  bool _soundEnabled = true;
  bool _hapticsEnabled = true;

  /// Set false by the player in settings. When false, [play] is a no-op but
  /// haptics still work, because they are a separate preference.
  bool get soundEnabled => _soundEnabled;

  bool get hapticsEnabled => _hapticsEnabled;

  void configure({required bool sound, required bool haptics}) {
    _soundEnabled = sound;
    _hapticsEnabled = haptics;
  }

  /// Low-latency pooled player, released when the game closes.
  final AudioContext _audioContext = AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
  );

  Future<void> _ensureConfigured() async {
    try {
      await _player.setAudioContext(_audioContext);
      await _player.setReleaseMode(ReleaseMode.stop);
      // Keep the sounds at a sensible level relative to whatever else the
      // player has going, and never duck music.
      await _player.setVolume(0.8);
    } catch (error) {
      debugPrint('AudioService: could not configure player: $error');
    }
  }

  Future<void> play(GameSound sound) async {
    if (!_soundEnabled) return;
    try {
      await _ensureConfigured();
      await _player.play(AssetSource(sound.assetPath));
    } catch (error) {
      debugPrint('AudioService: failed to play ${sound.name}: $error');
    }
  }

  /// [light] for a chip placement, [medium] for a roll, [heavy] for a big win.
  Future<void> haptic(HapticLevel level) async {
    if (!_hapticsEnabled) return;
    try {
      switch (level) {
        case HapticLevel.selection:
          await HapticFeedback.selectionClick();
        case HapticLevel.light:
          await HapticFeedback.lightImpact();
        case HapticLevel.medium:
          await HapticFeedback.mediumImpact();
        case HapticLevel.heavy:
          await HapticFeedback.heavyImpact();
      }
    } catch (error) {
      debugPrint('AudioService: haptic failed: $error');
    }
  }

  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (error) {
      debugPrint('AudioService: dispose failed: $error');
    }
  }
}

enum HapticLevel { selection, light, medium, heavy }
