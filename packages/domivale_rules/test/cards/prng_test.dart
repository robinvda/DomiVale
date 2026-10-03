import 'package:domivale_rules/domivale_rules.dart';
import 'package:test/test.dart';

void main() {
  test('is the minimal standard generator, so its sequence is known', () {
    // The 10000th value from seed 1 is the published check value for the
    // 48271 multiplier (it is what C++'s std::minstd_rand gives).
    final prng = Prng(1);
    expect(prng.next(), 48271);
    for (var i = 2; i < 10000; i++) {
      prng.next();
    }
    expect(prng.next(), 399268537);
  });

  test('stays inside 1 to 2³¹ − 2 whatever the seed', () {
    for (final seed in [0, 1, -5, 2147483646, 2147483647, 1 << 40]) {
      final prng = Prng(seed);
      for (var i = 0; i < 1000; i++) {
        final value = prng.next();
        expect(value, inInclusiveRange(1, 2147483646), reason: 'seed $seed');
      }
    }
  });

  test('shuffles the same list the same way from the same seed', () {
    final one = List.generate(40, (i) => i);
    final two = List.generate(40, (i) => i);
    Prng(42).shuffle(one);
    Prng(42).shuffle(two);
    expect(one, two);
    expect(one, isNot(orderedEquals(List.generate(40, (i) => i))));
    expect(one.toSet(), hasLength(40));

    final other = List.generate(40, (i) => i);
    Prng(43).shuffle(other);
    expect(other, isNot(orderedEquals(one)));
  });

  test('nextInt stays under its bound', () {
    final prng = Prng(7);
    for (var i = 0; i < 1000; i++) {
      expect(prng.nextInt(5), inInclusiveRange(0, 4));
    }
    expect(() => prng.nextInt(0), throwsArgumentError);
  });
}
