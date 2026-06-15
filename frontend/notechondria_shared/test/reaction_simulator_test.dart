import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/notechondria_shared.dart';

void main() {
  group('ReactionSimulator', () {
    test('population grows toward the area-scaled target at 1920x1080', () {
      final sim = ReactionSimulator(rng: math.Random(42));
      sim.setSize(1920, 1080); // reference viewport => ~128 target
      final target = sim.targetParticles;
      expect(target, ReactionSimOptions.referenceParticles);
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
      // Steady state oscillates around the target: it can dip just
      // under the 0.6*target spawn trigger right before a population
      // tick, and overshoot a little when reaction products land before
      // the stale cull catches up. Assert a robust band, not an exact
      // count.
      expect(
          sim.particles.length, greaterThanOrEqualTo((target * 0.5).floor()));
      expect(sim.particles.length, lessThanOrEqualTo(target + 12));
      expect(sim.lifetimeReactions, greaterThan(0),
          reason: 'TCA reactions should fire within a simulated minute');
    });

    test('particle target scales with viewport area and clamps', () {
      final sim = ReactionSimulator(rng: math.Random(1));
      // Before any setSize: falls back to the reference count.
      expect(sim.targetParticles, ReactionSimOptions.referenceParticles);
      // Reference viewport: exactly the reference count.
      sim.setSize(1920, 1080);
      expect(sim.targetParticles, ReactionSimOptions.referenceParticles);
      // Half the area => roughly half the particles.
      sim.setSize(960, 1080);
      expect(sim.targetParticles, closeTo(64, 2));
      // A small phone is clamped up to the minimum, not left sparse.
      sim.setSize(360, 640);
      expect(sim.targetParticles, ReactionSimOptions.minParticles);
      // A huge monitor is capped, not overwhelming.
      sim.setSize(7680, 4320);
      expect(sim.targetParticles, ReactionSimOptions.maxParticlesCap);
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
