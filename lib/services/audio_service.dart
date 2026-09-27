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
  AudioService({AudioPlayer? player}) : _injected = player;

  /// Created on first use rather than in the constructor.
  ///
  /// Building an `AudioPlayer` reaches a platform channel, so constructing one
  /// eagerly would make merely creating a [GameController] depend on the audio
  /// plugin being present and working. Lazily, a device with a broken or
  /// missing audio implementation still gets a playable game.
  final AudioPlayer? _injected;
  AudioPlayer? _player;
  bool _configured = false;

  AudioPlayer? get _instance => _player ??= _injected ?? AudioPlayer();

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
    if (_configured) return;
    final AudioPlayer? player = _instance;
    if (player == null) return;
    try {
      await player.setAudioContext(_audioContext);
      await player.setReleaseMode(ReleaseMode.stop);
      // Keep the sounds at a sensible level relative to whatever else the
      // player has going, and never duck music.
      await player.setVolume(0.8);
      _configured = true;
    } catch (error) {
      debugPrint('AudioService: could not configure player: $error');
    }
  }

  Future<void> play(GameSound sound) async {
    if (!_soundEnabled) return;
    final AudioPlayer? player = _instance;
    if (player == null) return;
    try {
      await _ensureConfigured();
      await player.play(AssetSource(sound.assetPath));
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
      await _player?.dispose();
    } catch (error) {
      debugPrint('AudioService: dispose failed: $error');
    } finally {
      _player = null;
      _configured = false;
    }
  }
}

enum HapticLevel { selection, light, medium, heavy }
