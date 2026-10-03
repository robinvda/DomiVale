/// A small deterministic random number generator for the market shuffle.
///
/// The Park-Miller "minimal standard" generator: `state = state × 48271
/// mod (2³¹ − 1)`. It is written here rather than taken from `dart:math`
/// because a seed has to shuffle the same deck on the VM and in a browser,
/// where a Dart `int` is a JavaScript double. The product never passes 2⁴⁷,
/// so it stays exact there, and no bitwise operation is used.
class Prng {
  /// Any seed is accepted; it is folded into the generator's range of
  /// 1 to 2³¹ − 2, with seeds 1 to 2³¹ − 2 used as they are.
  Prng(int seed) : _state = (seed - 1) % (_modulus - 1) + 1;

  static const int _modulus = 2147483647;
  static const int _multiplier = 48271;

  int _state;

  /// The next value, 1 to 2³¹ − 2.
  int next() {
    _state = (_state * _multiplier) % _modulus;
    return _state;
  }

  /// A value from 0 up to but not including [max].
  int nextInt(int max) {
    if (max < 1) {
      throw ArgumentError.value(max, 'max', 'must be at least 1');
    }
    return next() % max;
  }

  /// Shuffles [list] in place, Fisher-Yates from the end.
  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final swap = list[i];
      list[i] = list[j];
      list[j] = swap;
    }
  }
}
