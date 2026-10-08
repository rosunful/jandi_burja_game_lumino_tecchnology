import 'package:flutter_test/flutter_test.dart';
import 'package:janda_burja_game_app/models/symbol.dart';

/// The 3D page prints its faces from `SYMBOLS`, a fixed table baked into the
/// page's own art. [Symbol.dieNumber] is the only bridge between that table and
/// the wallet, because the real-money throw sends these numbers to the page and
/// settles whatever the page landed on. One wrong row would animate one symbol
/// while paying out on another.
void main() {
  test('maps each symbol to the die number the 3D page scores it as', () {
    expect(Symbol.heart.dieNumber, 1);
    expect(Symbol.crown.dieNumber, 2);
    expect(Symbol.spade.dieNumber, 3);
    expect(Symbol.club.dieNumber, 4);
    expect(Symbol.flag.dieNumber, 5);
    expect(Symbol.diamond.dieNumber, 6);
  });

  test('numbers every symbol exactly once', () {
    expect(
      Symbol.values.map((Symbol s) => s.dieNumber).toSet(),
      hasLength(Symbol.values.length),
      reason: 'two symbols sharing a die number would make the throw ambiguous',
    );
  });
}
