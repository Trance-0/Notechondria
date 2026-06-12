import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/notechondria_shared.dart';

void main() {
  group('ReactionSimulator', () {
    test('population grows toward the hardcoded 128-particle target', () {
      final sim = ReactionSimulator(rng: math.Random(42));
      sim.setSize(800, 600);
      // 60 simulated seconds at 60 fps with the population manager
      // firing every 0.5 s, mirroring ReactionSimulatorView's loop.
      var clock = 0.0;
      for (var i = 0; i < 60 * 60; i++) {
        sim.step(1 / 60);
        clock += 1 / 60;
        if (clock >= 0.5) {
          clock = 0;
          sim.populationTick();
        }
      }
      expect(
        sim.particles.length,
        greaterThanOrEqualTo((ReactionSimOptions.maxParticles * 0.6).floor()),
      );
      // Products of in-flight reactions can briefly overshoot the
      // target before the cull marks extras stale; allow headroom.
      expect(sim.particles.length,
          lessThanOrEqualTo(ReactionSimOptions.maxParticles + 12));
      expect(sim.lifetimeReactions, greaterThan(0),
          reason: 'TCA reactions should fire within a simulated minute');
    });

    test('stepped speeds never exceed the max clamp', () {
      // Only the max bound is a hard guarantee: below-min speeds are
      // re-sampled (not floored) per the upstream semantics, and the
      // resample itself can land below the floor for heavy molecules.
      final sim = ReactionSimulator(rng: math.Random(7));
      sim.setSize(640, 480);
      for (var i = 0; i < 40; i++) {
        sim.populationTick();
      }
      for (var i = 0; i < 30; i++) {
        sim.step(1 / 60);
      }
      for (final p in sim.particles) {
        final speed = math.sqrt(p.vx * p.vx + p.vy * p.vy);
        expect(speed, lessThanOrEqualTo(ReactionSimOptions.speedMax + 1e-6));
      }
    });

    test('particles stay inside the torus world', () {
      final sim = ReactionSimulator(rng: math.Random(3));
      sim.setSize(300, 200);
      for (var i = 0; i < 10; i++) {
        sim.populationTick();
      }
      for (var i = 0; i < 600; i++) {
        sim.step(1 / 30);
      }
      for (final p in sim.particles) {
        expect(p.x, inInclusiveRange(0, 300));
        expect(p.y, inInclusiveRange(0, 200));
      }
    });
  });
}
