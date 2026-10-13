import 'package:flutter_test/flutter_test.dart';
import 'package:domivale/core/game/game_loop.dart';

/// The clock every Vale game's simulation runs on. A game inherits its tick
/// rate without ever setting one up, so a mistake here is silent and
/// everywhere: too few ticks and everything runs slow, too many and a frame
/// hitch turns into a spiral.
void main() {
  late List<double> ticks;
  late List<double> frames;
  late GameLoop loop;

  setUp(() {
    ticks = [];
    frames = [];
    loop = GameLoop(
      tickRate: 60,
      onFixedUpdate: ticks.add,
      onUpdate: frames.add,
    );
  });

  test('a tick is always the same length, whatever the frame was', () {
    loop.update(1 / 30); // one long frame
    expect(ticks, everyElement(closeTo(1 / 60, 1e-12)));
  });

  test('a long frame runs the ticks it owes', () {
    loop.update(1 / 20); // three ticks' worth
    expect(ticks, hasLength(3));
    expect(loop.tickCount, 3);
  });

  test('leftover time is carried, not dropped', () {
    // Half a tick, twice, is one tick.
    loop.update(1 / 120);
    expect(ticks, isEmpty);
    loop.update(1 / 120);
    expect(ticks, hasLength(1));
  });

  test('the frame callback runs once per frame, at the frame length', () {
    loop.update(1 / 20);
    expect(frames, [1 / 20]);
  });

  test('a huge delta is capped rather than run to the end', () {
    // A resume from the background, or a debugger pause: without the cap the
    // loop owes hours of ticks and never catches up.
    loop.update(60.0);
    expect(ticks, hasLength(15), reason: '0.25s of ticks at 60 per second');
  });

  test('while paused the frame still runs but the simulation does not', () {
    loop.isPaused = true;
    loop.update(1 / 20);
    expect(ticks, isEmpty);
    expect(frames, [1 / 20], reason: 'the view still needs to draw');
  });

  test('unpausing does not run the ticks missed while paused', () {
    loop.isPaused = true;
    loop.update(1.0);
    loop.isPaused = false;
    loop.update(1 / 60);
    expect(ticks, hasLength(1));
  });

  test('the speed multiplier scales how much time a frame delivers', () {
    loop.speedMultiplier = 3.0;
    loop.update(1 / 60);
    expect(ticks, hasLength(3));
  });

  test('speed cannot be set to nothing or to a negative', () {
    loop.speedMultiplier = 0.0;
    expect(loop.speedMultiplier, greaterThan(0.0));
    loop.speedMultiplier = -2.0;
    expect(loop.speedMultiplier, greaterThan(0.0));
  });

  test('alpha says how far between ticks the frame is', () {
    expect(loop.alpha, 0.0);
    loop.update(1 / 120); // half a tick
    expect(loop.alpha, closeTo(0.5, 1e-9));
  });

  test('reset clears the carried time and the count', () {
    loop.update(1 / 40);
    expect(loop.tickCount, greaterThan(0));
    loop.reset();
    expect(loop.tickCount, 0);
    expect(loop.alpha, 0.0);
  });

  group('speed', () {
    test('the multiplier is clamped to the range the game allows', () {
      final loop = GameLoop(onFixedUpdate: ticks.add);
      loop.speedMultiplier = 99.0;
      expect(loop.speedMultiplier, 3.0);
      loop.speedMultiplier = 0.0;
      expect(loop.speedMultiplier, 0.5);
    });

    test('a game may set its own range', () {
      // Which speeds are on offer is a balance decision, so the bounds belong
      // to whoever builds the loop rather than to the loop itself.
      final loop = GameLoop(
        onFixedUpdate: ticks.add,
        minSpeedMultiplier: 1.0,
        maxSpeedMultiplier: 10.0,
      );
      loop.speedMultiplier = 8.0;
      expect(loop.speedMultiplier, 8.0);
      loop.speedMultiplier = 0.5;
      expect(loop.speedMultiplier, 1.0);
    });

    test('a faster multiplier runs more ticks for the same frame', () {
      final loop = GameLoop(onFixedUpdate: ticks.add)..speedMultiplier = 2.0;
      ticks.clear();
      loop.update(1 / 30);
      expect(ticks, hasLength(4));
    });
  });

  test('a different tick rate changes the tick length, not the time covered',
      () {
    final slow = GameLoop(tickRate: 20, onFixedUpdate: ticks.add);
    ticks.clear();
    // A fifth of a second, which is four ticks at 20 a second and would be
    // twelve at 60 — and stays under the delta cap either way.
    slow.update(0.2);
    expect(ticks, hasLength(4));
    expect(ticks.first, closeTo(1 / 20, 1e-12));
    expect(ticks.fold<double>(0, (a, b) => a + b), closeTo(0.2, 1e-9));
  });
}
