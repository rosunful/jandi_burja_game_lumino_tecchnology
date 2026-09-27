/// The six symbols printed on the faces of every die.
///
/// Order is deliberate and load-bearing: the betting board renders symbols in
/// this order, and [Symbol.values] indexes into per-symbol state maps. Do not
/// reorder without updating those maps.
enum Symbol {
  /// Burja / Jhanda - the crown. The namesake symbol of the game.
  crown('Crown', 'burja'),

  /// Jhanda / Jandi - the anchor, the second non-card-suit symbol.
  anchor('Anchor', 'jhanda'),

  heart('Heart', 'paan'),
  diamond('Diamond', 'itta'),
  club('Club', 'chidi'),
  spade('Spade', 'hukum');

  const Symbol(this.label, this.localName);

  /// English name, shown on the betting board and rules screen.
  final String label;

  /// Traditional name in the game's native vocabulary, shown alongside
  /// [label] so the game reads as Jhandi Munda rather than a generic casino
  /// dice game. These are the names used in Nepal and northern India.
  final String localName;
}
