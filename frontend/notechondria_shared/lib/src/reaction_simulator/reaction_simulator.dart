import 'dart:math' as math;

import 'reaction_defs.dart';

/// Physics core of the reaction-simulator splash animation.
///
/// Port of `simulator.js` / `particle.js` / `reaction_manager.js` from
/// the owner's `index` repo. Interactive features the splash does not
/// need (particle tracking, hit-testing, labelled reaction boxes,
/// runtime rule/option mutation) are dropped; tuning is hardcoded in
/// [ReactionSimOptions] per the owner's 0.1.128 spec.

class SimParticle {
  SimParticle({
    required this.kind,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    required this.mass,
    required math.Random rng,
    this.ripeAt,
  })  : angle = rng.nextDouble() * math.pi * 2,
        omega = (rng.nextDouble() - 0.5) * 1.2;

  final String kind;
  double x;
  double y;
  double vx;
  double vy;
  double angle;
  final double omega;
  final double r;
  final double mass;
  double age = 0;
  double staleAge = 0;
  double? ripeAt;

  void step(double dt, double w, double h) {
    x += vx * dt;
    y += vy * dt;
    angle += omega * dt;
    age += dt;
    staleAge += dt;
    vx *= 0.999;
    vy *= 0.999;
    if (x < 0) {
      x += w;
    } else if (x >= w) {
      x -= w;
    }
    if (y < 0) {
      y += h;
    } else if (y >= h) {
      y -= h;
    }
  }

  /// Spawn fade-in composed with staleness fade-out.
  double alpha() {
    var a = 1.0;
    if (age < ReactionSimOptions.spawnFadeIn) {
      a = math.min(a, age / ReactionSimOptions.spawnFadeIn);
    }
    const start = ReactionSimOptions.staleFadeStart;
    const end = ReactionSimOptions.staleFadeEnd;
    if (staleAge >= end) {
      a = 0;
    } else if (staleAge > start) {
      a = math.min(a, 1 - (staleAge - start) / (end - start));
    }
    return a < 0 ? 0 : a;
  }
}

/// A short-lived pictogram badge shown where a reaction fired.
class ReactionBadge {
  ReactionBadge({required this.x, required this.y, required this.glyph});

  final double x;
  double y;
  double t = 0;
  final double life = 0.9;
  final String glyph;
}

/// Bimolecular/unimolecular rule lookup (port of `reaction_manager.js`).
class ReactionRules {
  ReactionRules(this.bimol, this.unimol, math.Random rng) : _rng = rng {
    for (final r in bimol) {
      _bimolMap['${r.a}|${r.b}'] = r;
      _bimolMap['${r.b}|${r.a}'] = r;
    }
    for (final r in unimol) {
      _unimolMap[r.kind] = r;
    }
  }

  final List<BimolRule> bimol;
  final List<UnimolRule> unimol;
  final math.Random _rng;
  final Map<String, BimolRule> _bimolMap = {};
  final Map<String, UnimolRule> _unimolMap = {};

  BimolRule? getBimol(String a, String b) => _bimolMap['$a|$b'];

  UnimolRule? getUnimol(String kind) => _unimolMap[kind];

  /// Higher = more likely to react against the current field; drives
  /// the population manager's spawn/cull choices.
  double reactivityScore(String kind, Map<String, int> counts) {
    var s = 0.0;
    for (final r in bimol) {
      if (r.a == kind) {
        s += counts[r.b] ?? 0;
      } else if (r.b == kind) {
        s += counts[r.a] ?? 0;
      }
    }
    if (_unimolMap.containsKey(kind)) s += 2;
    return s;
  }

  double? initialRipeAt(String kind) {
    final u = _unimolMap[kind];
    if (u == null) return null;
    final span = math.max(0.0, u.maxAge - u.minAge);
    return u.minAge + _rng.nextDouble() * span;
  }
}

/// Owns the W x H torus world, the live particle list, and per-tick
/// physics + reaction firing (port of `simulator.js`).
class ReactionSimulator {
  ReactionSimulator({math.Random? rng}) : _rng = rng ?? math.Random() {
    rules = ReactionRules(kTcaBimol, kTcaUnimol, _rng);
  }

  final math.Random _rng;
  late final ReactionRules rules;
  final Map<String, MoleculeDef> defs = kTcaDefs;
  final List<String> spawnable = kTcaSpawnable;
  final List<SimParticle> particles = [];
  final List<ReactionBadge> badges = [];
  double width = 0;
  double height = 0;

  /// Total reaction events ever fired; observability for tests.
  int lifetimeReactions = 0;

  void setSize(double w, double h) {
    width = w;
    height = h;
  }

  double _clippedNormal(double mean, double std) {
    if (std <= 0) return math.max(0, mean);
    final u1 = math.max(1e-9, _rng.nextDouble());
    final u2 = _rng.nextDouble();
    final z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
    return math.max(0, mean + std * z);
  }

  double _sampleSpeed(double mass) {
    final ke = _clippedNormal(
        ReactionSimOptions.energyMean, ReactionSimOptions.energyStd);
    return math.sqrt(2 * ke / math.max(1, mass));
  }

  SimParticle? spawn(String kind,
      {double? x, double? y, double? vx, double? vy}) {
    final def = defs[kind];
    if (def == null) return null;
    final mass = molecularMass(def);
    if (vx == null || vy == null) {
      final speed = _sampleSpeed(mass);
      final ang = _rng.nextDouble() * math.pi * 2;
      vx = math.cos(ang) * speed;
      vy = math.sin(ang) * speed;
    }
    final p = SimParticle(
      kind: kind,
      x: x ?? _rng.nextDouble() * width,
      y: y ?? _rng.nextDouble() * height,
      vx: vx,
      vy: vy,
      r: def.r,
      mass: mass,
      rng: _rng,
      ripeAt: rules.initialRipeAt(kind),
    );
    particles.add(p);
    return p;
  }

  void step(double dt) {
    final w = width, h = height;
    if (w <= 0 || h <= 0) return;
    for (final p in particles) {
      p.step(dt, w, h);
      final sp = math.sqrt(p.vx * p.vx + p.vy * p.vy);
      if (sp < ReactionSimOptions.speedMin) {
        final s2 = _sampleSpeed(p.mass);
        final a =
            sp > 0 ? math.atan2(p.vy, p.vx) : _rng.nextDouble() * math.pi * 2;
        p.vx = math.cos(a) * s2;
        p.vy = math.sin(a) * s2;
      } else if (sp > ReactionSimOptions.speedMax) {
        final k = ReactionSimOptions.speedMax / sp;
        p.vx *= k;
        p.vy *= k;
      }
    }
    _collide();
    _ripen();
    particles.removeWhere((p) => p.staleAge >= ReactionSimOptions.staleFadeEnd);
    for (final b in badges) {
      b.t += dt;
      b.y -= 18 * dt;
    }
    badges.removeWhere((b) => b.t >= b.life);
  }

  void _collide() {
    final ps = particles;
    if (ps.length < 2) return;
    final w = width, h = height;
    var maxR = 0.0;
    for (final p in ps) {
      if (p.r > maxR) maxR = p.r;
    }
    final cell = math.max(16.0, maxR * 2);
    final cols = math.max(1, (w / cell).ceil());
    final rows = math.max(1, (h / cell).ceil());
    final grid = <int, List<int>>{};
    for (var idx = 0; idx < ps.length; idx++) {
      final p = ps[idx];
      final cx = ((p.x / cell).floor() % cols + cols) % cols;
      final cy = ((p.y / cell).floor() % rows + rows) % rows;
      grid.putIfAbsent(cy * cols + cx, () => []).add(idx);
    }

    final consumed = <int>{};
    void checkPair(int i, int j) {
      if (consumed.contains(i) || consumed.contains(j)) return;
      final a = ps[i], b = ps[j];
      var dx = b.x - a.x;
      if (dx > w / 2) {
        dx -= w;
      } else if (dx < -w / 2) {
        dx += w;
      }
      var dy = b.y - a.y;
      if (dy > h / 2) {
        dy -= h;
      } else if (dy < -h / 2) {
        dy += h;
      }
      final d2 = dx * dx + dy * dy;
      final rr = a.r + b.r;
      if (d2 > rr * rr) return;
      final rule = rules.getBimol(a.kind, b.kind);
      if (rule != null) {
        final mx = ((a.x + dx / 2) % w + w) % w;
        final my = ((a.y + dy / 2) % h + h) % h;
        _fireBimol(rule, a, b, mx, my);
        consumed.add(i);
        consumed.add(j);
        return;
      }
      // Equal-mass elastic exchange along the contact normal.
      final d = math.sqrt(d2);
      final dist = d == 0 ? 1.0 : d;
      final nx = dx / dist, ny = dy / dist;
      final va = a.vx * nx + a.vy * ny;
      final vb = b.vx * nx + b.vy * ny;
      final dv = vb - va;
      a.vx += dv * nx;
      a.vy += dv * ny;
      b.vx -= dv * nx;
      b.vy -= dv * ny;
      final overlap = (rr - dist) / 2;
      a.x = ((a.x - nx * overlap) % w + w) % w;
      a.y = ((a.y - ny * overlap) % h + h) % h;
      b.x = ((b.x + nx * overlap) % w + w) % w;
      b.y = ((b.y + ny * overlap) % h + h) % h;
    }

    grid.forEach((key, bucket) {
      final cx = key % cols;
      final cy = (key - cx) ~/ cols;
      for (var i = 0; i < bucket.length; i++) {
        for (var j = i + 1; j < bucket.length; j++) {
          checkPair(bucket[i], bucket[j]);
        }
      }
      const offsets = [(1, 0), (-1, 1), (0, 1), (1, 1)];
      for (final (ox, oy) in offsets) {
        final nx = ((cx + ox) % cols + cols) % cols;
        final ny = ((cy + oy) % rows + rows) % rows;
        if (nx == cx && ny == cy) continue;
        final nb = grid[ny * cols + nx];
        if (nb == null) continue;
        for (final i in bucket) {
          for (final j in nb) {
            checkPair(i, j);
          }
        }
      }
    });
    if (consumed.isNotEmpty) {
      final keep = <SimParticle>[];
      for (var i = 0; i < ps.length; i++) {
        if (!consumed.contains(i)) keep.add(ps[i]);
      }
      particles
        ..clear()
        ..addAll(keep);
    }
  }

  void _spawnProducts(
      List<String> products, double x, double y, double vx, double vy) {
    for (final k in products) {
      final def = defs[k];
      if (def == null) continue;
      final baseSpeed = _sampleSpeed(molecularMass(def));
      final ang = _rng.nextDouble() * math.pi * 2;
      var pvx = vx + math.cos(ang) * baseSpeed * 0.4;
      var pvy = vy + math.sin(ang) * baseSpeed * 0.4;
      if (k == 'co2') pvy -= baseSpeed.abs() * 0.3;
      spawn(k, x: x, y: y, vx: pvx, vy: pvy)?.staleAge = 0;
    }
  }

  void _fireBimol(
      BimolRule rule, SimParticle a, SimParticle b, double mx, double my) {
    _spawnProducts(rule.products, mx, my, (a.vx + b.vx) / 2, (a.vy + b.vy) / 2);
    badges.add(ReactionBadge(x: mx, y: my, glyph: rule.pictogram));
    lifetimeReactions += 1;
  }

  void _ripen() {
    // Iterate a snapshot: `_spawnProducts` appends the reaction
    // products to `particles` mid-loop, which Dart's iterator (unlike
    // JS for..of in the upstream source) treats as a concurrent
    // modification. Fresh products are not in the snapshot, so they
    // first get ripeness-checked on the next tick.
    final snapshot = List<SimParticle>.of(particles);
    final ripened = <SimParticle>{};
    for (final p in snapshot) {
      final ripeAt = p.ripeAt;
      if (ripeAt == null || p.age < ripeAt) continue;
      final rule = rules.getUnimol(p.kind);
      if (rule == null) continue;
      _spawnProducts(rule.products, p.x, p.y, p.vx, p.vy);
      badges.add(ReactionBadge(x: p.x, y: p.y, glyph: rule.pictogram));
      lifetimeReactions += 1;
      ripened.add(p);
    }
    if (ripened.isNotEmpty) {
      particles.removeWhere(ripened.contains);
    }
  }

  /// Re-balance population toward [ReactionSimOptions.maxParticles]:
  /// spawn the most reactive kinds while undersized; mark the least
  /// reactive particle stale-soon while oversized so it fades out.
  void populationTick() {
    if (spawnable.isEmpty) return;
    final counts = <String, int>{};
    for (final p in particles) {
      counts[p.kind] = (counts[p.kind] ?? 0) + 1;
    }
    const target = ReactionSimOptions.maxParticles;
    final minC = (target * 0.6).floor();
    final n = particles.length;

    if (n < minC) {
      final need = math.min(target - n, 6);
      for (var i = 0; i < need; i++) {
        var best = spawnable[0];
        var bestS = -1.0;
        for (final k in spawnable) {
          final s = rules.reactivityScore(k, counts) + _rng.nextDouble() * 0.5;
          if (s > bestS) {
            bestS = s;
            best = k;
          }
        }
        spawn(best);
        counts[best] = (counts[best] ?? 0) + 1;
      }
    } else if (n > target) {
      SimParticle? worst;
      var worstS = double.infinity;
      for (final p in particles) {
        final s = rules.reactivityScore(p.kind, counts);
        if (s < worstS) {
          worstS = s;
          worst = p;
        }
      }
      if (worst != null) {
        worst.staleAge =
            math.max(worst.staleAge, ReactionSimOptions.staleFadeStart + 0.1);
      }
    }
  }
}
