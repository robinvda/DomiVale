/// The three goods, each with one job: grain to grow, wood to build, stone to
/// fortify and besiege.
enum Good {
  grain('Grain'),
  wood('Wood'),
  stone('Stone');

  const Good(this.label);

  final String label;
}

/// An amount of each good: a price, a yield or a house's holdings.
class Goods {
  const Goods({this.grain = 0, this.wood = 0, this.stone = 0});

  /// [amount] of one good and nothing else.
  factory Goods.only(Good good, int amount) {
    switch (good) {
      case Good.grain:
        return Goods(grain: amount);
      case Good.wood:
        return Goods(wood: amount);
      case Good.stone:
        return Goods(stone: amount);
    }
  }

  static const none = Goods();

  final int grain;
  final int wood;
  final int stone;

  int of(Good good) {
    switch (good) {
      case Good.grain:
        return grain;
      case Good.wood:
        return wood;
      case Good.stone:
        return stone;
    }
  }

  int get total => grain + wood + stone;

  /// Whether a house holding this could pay [price].
  bool covers(Goods price) =>
      grain >= price.grain && wood >= price.wood && stone >= price.stone;

  Goods operator +(Goods other) => Goods(
        grain: grain + other.grain,
        wood: wood + other.wood,
        stone: stone + other.stone,
      );

  Goods operator -(Goods other) => Goods(
        grain: grain - other.grain,
        wood: wood - other.wood,
        stone: stone - other.stone,
      );

  Goods operator *(int times) => Goods(
        grain: grain * times,
        wood: wood * times,
        stone: stone * times,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Goods &&
          grain == other.grain &&
          wood == other.wood &&
          stone == other.stone;

  @override
  int get hashCode => Object.hash(grain, wood, stone);

  @override
  String toString() => '$grain grain, $wood wood, $stone stone';
}
