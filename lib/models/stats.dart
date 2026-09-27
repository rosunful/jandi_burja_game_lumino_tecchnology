/// Lifetime player statistics, persisted across launches.
class GameStats {
  const GameStats({
    this.roundsPlayed = 0,
    this.roundsWon = 0,
    this.coinsWagered = 0,
    this.coinsReturned = 0,
    this.biggestWin = 0,
    this.biggestLoss = 0,
    this.adsWatched = 0,
    this.coinsFromAds = 0,
  });

  final int roundsPlayed;
  final int roundsWon;

  /// Total coins staked across all rounds. The denominator of the observed
  /// return to player, which is worth showing so players can see the real
  /// edge rather than only the headline number.
  final int coinsWagered;

  /// Total coins returned across all rounds, including returned stakes.
  final int coinsReturned;
  final int biggestWin;
  final int biggestLoss;
  final int adsWatched;
  final int coinsFromAds;

  /// Net coin change from gambling alone, excluding ad rewards.
  int get netFromPlay => coinsReturned - coinsWagered;

  /// Observed return to player as a percentage, or null before any coins have
  /// been wagered.
  double? get observedRtp {
    if (coinsWagered <= 0) return null;
    return coinsReturned / coinsWagered;
  }

  /// Share of rounds that were a net win, or null before any rounds.
  double? get winRate {
    if (roundsPlayed <= 0) return null;
    return roundsWon / roundsPlayed;
  }

  GameStats copyWith({
    int? roundsPlayed,
    int? roundsWon,
    int? coinsWagered,
    int? coinsReturned,
    int? biggestWin,
    int? biggestLoss,
    int? adsWatched,
    int? coinsFromAds,
  }) {
    return GameStats(
      roundsPlayed: roundsPlayed ?? this.roundsPlayed,
      roundsWon: roundsWon ?? this.roundsWon,
      coinsWagered: coinsWagered ?? this.coinsWagered,
      coinsReturned: coinsReturned ?? this.coinsReturned,
      biggestWin: biggestWin ?? this.biggestWin,
      biggestLoss: biggestLoss ?? this.biggestLoss,
      adsWatched: adsWatched ?? this.adsWatched,
      coinsFromAds: coinsFromAds ?? this.coinsFromAds,
    );
  }

  Map<String, Object> toMap() => <String, Object>{
    'roundsPlayed': roundsPlayed,
    'roundsWon': roundsWon,
    'coinsWagered': coinsWagered,
    'coinsReturned': coinsReturned,
    'biggestWin': biggestWin,
    'biggestLoss': biggestLoss,
    'adsWatched': adsWatched,
    'coinsFromAds': coinsFromAds,
  };

  factory GameStats.fromMap(Map<String, Object?> map) {
    int read(String key) => (map[key] as int?) ?? 0;
    return GameStats(
      roundsPlayed: read('roundsPlayed'),
      roundsWon: read('roundsWon'),
      coinsWagered: read('coinsWagered'),
      coinsReturned: read('coinsReturned'),
      biggestWin: read('biggestWin'),
      biggestLoss: read('biggestLoss'),
      adsWatched: read('adsWatched'),
      coinsFromAds: read('coinsFromAds'),
    );
  }
}
