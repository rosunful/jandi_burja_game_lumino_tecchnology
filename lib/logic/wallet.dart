import 'dart:collection';

import '../core/config.dart';
import '../models/bet.dart';
import '../models/symbol.dart';

/// Owns the coin balance and the set of wagers staged for the current round.
///
/// Deliberately framework-free and mutates in place; [GameController] is
/// responsible for notifying the UI.
class Wallet {
  Wallet({required int balance, int? selectedChip})
    : _balance = balance,
      _selectedChip = selectedChip ?? AppConfig.defaultChip;

  int _balance;

  int _selectedChip;

  final Map<Symbol, int> _bets = <Symbol, int>{};

  /// Wagers staged for the round that has not been rolled yet, exposed
  /// unmodifiable so the UI cannot bypass [addToBet] and its limit checks.
  UnmodifiableMapView<Symbol, int> get bets => UnmodifiableMapView<Symbol, int>(_bets);

  int get balance => _balance;

  int get selectedChip => _selectedChip;

  /// Sum of every staged wager.
  int get totalBet => _bets.values.fold(0, (int a, int b) => a + b);

  /// Coins not yet committed to this round.
  int get uncommittedBalance => _balance - totalBet;

  bool get hasBets => _bets.values.any((int amount) => amount > 0);

  /// True when the player can afford at least the smallest legal wager.
  bool get canAffordMinBet => uncommittedBalance >= AppConfig.minBet;

  void selectChip(int denomination) {
    if (AppConfig.chipDenominations.contains(denomination)) {
      _selectedChip = denomination;
    }
  }

  /// Stages [amount] more coins on [symbol]. Returns false and changes nothing
  /// if the wager would break a limit.
  bool addToBet(Symbol symbol, int amount) {
    final int existing = _bets[symbol] ?? 0;
    if (amount <= 0) return false;
    if (existing + amount > AppConfig.maxBetPerSymbol) return false;
    if (totalBet + amount > AppConfig.maxTotalBet) return false;
    if (amount > uncommittedBalance) return false;

    _bets[symbol] = existing + amount;
    return true;
  }

  /// Removes [amount] coins from the wager on [symbol], clearing the entry
  /// entirely once it reaches zero so the board shows no chip stack.
  void removeFromBet(Symbol symbol, int amount) {
    final int existing = _bets[symbol] ?? 0;
    if (existing <= 0 || amount <= 0) return;

    final int next = existing - amount;
    if (next <= 0) {
      _bets.remove(symbol);
    } else {
      _bets[symbol] = next;
    }
  }

  /// Removes the whole wager on [symbol].
  void clearBet(Symbol symbol) => _bets.remove(symbol);

  /// Discards every staged wager.
  void clearAllBets() => _bets.clear();

  /// Stages the same wager pattern and chip amounts as [previous], skipping
  /// any symbol the player can no longer afford.
  ///
  /// Returns the wager pattern actually staged, which the UI needs in order to
  /// tell the player what was dropped.
  Map<Symbol, int> repeat(Map<Symbol, int> previous) {
    clearAllBets();
    for (final MapEntry<Symbol, int> entry in previous.entries) {
      // Add one chip at a time so partial fills respect the per-symbol cap.
      int remaining = entry.value;
      while (remaining > 0) {
        final int chunk = remaining < _selectedChip ? remaining : _selectedChip;
        if (!addToBet(entry.key, chunk)) break;
        remaining -= chunk;
      }
    }
    return Map<Symbol, int>.from(_bets);
  }

  /// Applies a settled [RoundResult] to the balance and clears the board.
  void applyRound(RoundResult result) {
    _balance += result.netChange;
    _bets.clear();
  }

  /// Adds coins, clamped at zero, used by the rewarded-ad refill and by
  /// restoring persisted state.
  void credit(int amount) {
    if (amount > 0) _balance += amount;
  }

  /// Replaces the balance outright, used when loading persisted state. Negative
  /// values are clamped to zero rather than producing a debt the player can
  /// never clear.
  void setBalance(int value) {
    _balance = value < 0 ? 0 : value;
  }

  /// Snapshot of staged wagers, for persisting the last bet.
  Map<Symbol, int> snapshotBets() => Map<Symbol, int>.from(_bets);
}
